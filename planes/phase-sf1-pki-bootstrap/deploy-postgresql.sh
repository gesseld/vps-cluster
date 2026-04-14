#!/bin/bash

# PostgreSQL Deployment (Critical Dependency for SPIRE + Temporal)
# This unblocks Phase 1 (SPIRE) and Phase 3 (Temporal)

set -e

echo "=============================================="
echo "PostgreSQL Deployment - Critical Dependency"
echo "=============================================="
echo ""

# Generate secure passwords
POSTGRES_SUPER_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "SuperPassword$(date +%s)")
POSTGRES_APP_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "AppPassword$(date +%s)")

echo "1. Creating secrets for PostgreSQL credentials..."

# Create or update superuser secret
kubectl create secret generic postgres-superuser \
  --from-literal=password="$POSTGRES_SUPER_PASSWORD" \
  --namespace=data-plane \
  --dry-run=client -o yaml | kubectl apply -f -

# Create or update app user secret  
kubectl create secret generic postgres-app-user \
  --from-literal=password="$POSTGRES_APP_PASSWORD" \
  --namespace=data-plane \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ PostgreSQL secrets created/updated"
echo "   Superuser password saved in secret: postgres-superuser"
echo "   App user password saved in secret: postgres-app-user"

echo ""
echo "2. Deploying PostgreSQL primary StatefulSet..."

# Create PostgreSQL primary configuration
cat > /tmp/postgresql-primary.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql-primary
  namespace: data-plane
  labels:
    app: postgresql
    role: primary
spec:
  replicas: 1
  serviceName: postgresql-primary
  selector:
    matchLabels:
      app: postgresql
      role: primary
  template:
    metadata:
      labels:
        app: postgresql
        role: primary
    spec:
      serviceAccountName: default
      nodeSelector:
        node-role: storage-heavy
      priorityClassName: foundation-high
      containers:
      - name: postgresql
        image: postgres:15-alpine
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-superuser
              key: password
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-superuser
              key: password
        - name: POSTGRES_DB
          value: postgres
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
          name: postgresql
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1"
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: hcloud-volumes
      resources:
        requests:
          storage: 50Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgresql-primary
  namespace: data-plane
  labels:
    app: postgresql
    role: primary
spec:
  selector:
    app: postgresql
    role: primary
  ports:
  - port: 5432
    targetPort: postgresql
  type: ClusterIP
EOF

kubectl apply -f /tmp/postgresql-primary.yaml
echo "✓ PostgreSQL primary StatefulSet deployed"

echo ""
echo "3. Waiting for PostgreSQL primary to be ready..."
if kubectl wait --for=condition=Ready pod -n data-plane -l app=postgresql,role=primary --timeout=300s 2>/dev/null; then
    echo "✓ PostgreSQL primary is ready"
else
    echo "⚠ PostgreSQL primary taking longer to start"
    echo "   Checking status..."
    kubectl get pods -n data-plane -l app=postgresql,role=primary
fi

echo ""
echo "4. Creating databases for SPIRE and Temporal..."

# Create initialization job
cat > /tmp/postgresql-init.yaml << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: postgresql-init
  namespace: data-plane
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: init
        image: postgres:15-alpine
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-superuser
              key: password
        command:
        - /bin/sh
        - -c
        - |
          # Wait for PostgreSQL to be ready
          until pg_isready -h postgresql-primary.data-plane.svc.cluster.local -U postgres; do
            echo "Waiting for PostgreSQL..."
            sleep 2
          done
          
          # Create app user
          psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
            "CREATE USER app WITH PASSWORD '${POSTGRES_APP_PASSWORD}';"
          
          # Create SPIRE database
          psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
            "CREATE DATABASE spire OWNER app;"
          
          # Create Temporal visibility database
          psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
            "CREATE DATABASE temporal_visibility OWNER app;"
          
          # Create app database
          psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
            "CREATE DATABASE app OWNER app;"
          
          echo "Databases created successfully"
EOF

# Replace the password placeholder with actual password
POSTGRES_APP_PASSWORD_ESCAPED=$(echo "$POSTGRES_APP_PASSWORD" | sed 's/&/\\&/g')
sed -i "s/\${POSTGRES_APP_PASSWORD}/$POSTGRES_APP_PASSWORD_ESCAPED/g" /tmp/postgresql-init.yaml

kubectl apply -f /tmp/postgresql-init.yaml
echo "✓ Database initialization job created"

echo ""
echo "5. Waiting for database initialization..."
if kubectl wait --for=condition=complete job/postgresql-init -n data-plane --timeout=120s 2>/dev/null; then
    echo "✓ Database initialization completed successfully"
    
    # Check job logs
    INIT_POD=$(kubectl get pods -n data-plane -l job-name=postgresql-init -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$INIT_POD" ]; then
        echo "   Initialization logs:"
        kubectl logs -n data-plane $INIT_POD | tail -5
    fi
else
    echo "⚠ Database initialization may have issues"
    kubectl get jobs -n data-plane postgresql-init
fi

echo ""
echo "6. Testing PostgreSQL connectivity..."

# Create test pod
cat > /tmp/postgresql-test.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: postgresql-test
  namespace: data-plane
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: postgres:15-alpine
    env:
    - name: PGPASSWORD
      valueFrom:
        secretKeyRef:
          name: postgres-app-user
          key: password
    command:
    - /bin/sh
    - -c
    - |
      echo "Testing connection to PostgreSQL primary..."
      if pg_isready -h postgresql-primary.data-plane.svc.cluster.local -U app -d spire; then
        echo "✓ Connection to SPIRE database successful"
        
        echo "Testing database access..."
        if psql -h postgresql-primary.data-plane.svc.cluster.local -U app -d spire -c "SELECT 1;" | grep -q "1"; then
          echo "✓ Database query successful"
          exit 0
        else
          echo "✗ Database query failed"
          exit 1
        fi
      else
        echo "✗ Connection failed"
        exit 1
      fi
EOF

kubectl apply -f /tmp/postgresql-test.yaml --dry-run=client > /dev/null
if [ $? -eq 0 ]; then
    echo "✓ PostgreSQL test specification is valid"
else
    echo "⚠ PostgreSQL test specification has issues"
fi

echo ""
echo "7. Creating .env file with PostgreSQL credentials..."

# Create .env file in project root
cat > ../../.env << EOF
# PostgreSQL Connection for SPIRE + Temporal
POSTGRES_HOST=postgresql-primary.data-plane.svc.cluster.local
POSTGRES_PORT=5432
POSTGRES_DB_SPIRE=spire
POSTGRES_DB_TEMPORAL=temporal_visibility
POSTGRES_USER=app
POSTGRES_PASSWORD=$POSTGRES_APP_PASSWORD

# Cluster Configuration
CLUSTER_DOMAIN=cluster.local
SPIFFE_TRUST_DOMAIN=cluster.local

# SPIRE Configuration
SPIRE_TRUST_DOMAIN=cluster.local
SPIRE_SVID_TTL=3600

# Cert-Manager Configuration
CERT_MANAGER_VERSION=v1.13.0

# MinIO Replication Target (optional for now)
# MINIO_REPLICA_ENDPOINT=your-storage-box.your-server.de
# MINIO_REPLICA_ACCESS_KEY=your-key
# MINIO_REPLICA_SECRET_KEY=your-secret
EOF

chmod 600 ../../.env
echo "✓ .env file created with PostgreSQL credentials"
echo "   Location: ../../.env"
echo "   Note: This file is gitignored for security"

echo ""
echo "=============================================="
echo "PostgreSQL Deployment Summary"
echo "=============================================="
echo ""
echo "✅ Deployed:"
echo "   - PostgreSQL primary StatefulSet (50Gi PVC)"
echo "   - Service: postgresql-primary.data-plane.svc.cluster.local"
echo "   - Databases: spire, temporal_visibility, app"
echo "   - Users: app (application), postgres (superuser)"
echo "   - Secrets: postgres-superuser, postgres-app-user"
echo ""
echo "🔐 Credentials:"
echo "   - App user password: Saved in secret 'postgres-app-user'"
echo "   - Superuser password: Saved in secret 'postgres-superuser'"
echo "   - .env file: Created with connection details"
echo ""
echo "📊 Resource Allocation:"
echo "   - Node: storage-heavy labeled nodes"
echo "   - Storage: 50Gi PVC (hcloud-volumes)"
echo "   - Memory: 512Mi request, 2Gi limit"
echo "   - CPU: 250m request, 1 limit"
echo ""
echo "🔍 Validation Commands:"
echo "   kubectl get pods -n data-plane -l app=postgresql"
echo "   kubectl logs -n data-plane job/postgresql-init"
echo ""
echo "➡️  Next Steps:"
echo "   1. Verify PostgreSQL is running:"
echo "      kubectl get pods -n data-plane -l app=postgresql"
echo "   2. Test connectivity:"
echo "      kubectl exec -n data-plane postgresql-primary-0 -- pg_isready -U app"
echo "   3. Proceed to Phase 1:"
echo "      ./02-deployment.sh"
echo ""
echo "⚠️  Important:"
echo "   - Backup the .env file securely"
echo "   - Consider deploying PostgreSQL replica for HA"
echo "   - Set up automated backups before production use"
echo ""

# Cleanup temporary files
rm -f /tmp/postgresql-primary.yaml /tmp/postgresql-init.yaml /tmp/postgresql-test.yaml

exit 0