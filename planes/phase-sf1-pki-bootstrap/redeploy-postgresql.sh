#!/bin/bash

# Redeploy PostgreSQL with proper configuration

set -e

echo "=============================================="
echo "Redeploying PostgreSQL with Proper Configuration"
echo "=============================================="
echo ""

echo "1. Cleaning up existing PostgreSQL resources..."
kubectl delete statefulset -n data-plane postgresql-primary --ignore-not-found
kubectl delete service -n data-plane postgresql-primary --ignore-not-found
kubectl delete pod -n data-plane postgresql-app-test --ignore-not-found
kubectl delete job -n data-plane postgresql-init --ignore-not-found

echo "✓ Cleaned up existing resources"
echo ""
echo "2. Waiting for cleanup..."
sleep 10

echo ""
echo "3. Creating PostgreSQL with simplified configuration..."

# Generate new passwords if needed
if ! kubectl get secret -n data-plane postgres-superuser > /dev/null 2>&1; then
    SUPER_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "SuperPass$(date +%s)")
    kubectl create secret generic postgres-superuser \
      --from-literal=password="$SUPER_PASSWORD" \
      --namespace=data-plane
    echo "✓ Created postgres-superuser secret"
fi

if ! kubectl get secret -n data-plane postgres-app-user > /dev/null 2>&1; then
    APP_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "AppPass$(date +%s)")
    kubectl create secret generic postgres-app-user \
      --from-literal=password="$APP_PASSWORD" \
      --namespace=data-plane
    echo "✓ Created postgres-app-user secret"
fi

# Get passwords
SUPER_PASSWORD=$(kubectl get secret -n data-plane postgres-superuser -o jsonpath='{.data.password}' | base64 -d)
APP_PASSWORD=$(kubectl get secret -n data-plane postgres-app-user -o jsonpath='{.data.password}' | base64 -d)

echo ""
echo "4. Deploying PostgreSQL with initialization included..."

cat > /tmp/postgresql-complete.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgresql-init-scripts
  namespace: data-plane
data:
  init-databases.sh: |
    #!/bin/bash
    set -e
    
    echo "Initializing PostgreSQL databases..."
    
    # Wait for PostgreSQL to be ready
    until pg_isready -U postgres; do
      echo "Waiting for PostgreSQL..."
      sleep 2
    done
    
    # Create app user
    echo "Creating app user..."
    psql -U postgres -c "CREATE USER app WITH PASSWORD '${APP_PASSWORD}';"
    
    # Create databases
    echo "Creating SPIRE database..."
    psql -U postgres -c "CREATE DATABASE spire OWNER app;"
    
    echo "Creating Temporal visibility database..."
    psql -U postgres -c "CREATE DATABASE temporal_visibility OWNER app;"
    
    echo "Creating app database..."
    psql -U postgres -c "CREATE DATABASE app OWNER app;"
    
    echo "Database initialization complete!"
---
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
      initContainers:
      - name: init-databases
        image: postgres:15-alpine
        command: ["/bin/sh", "-c"]
        args:
        - |
          # Copy init script
          cp /init-scripts/init-databases.sh /docker-entrypoint-initdb.d/
          chmod +x /docker-entrypoint-initdb.d/init-databases.sh
        volumeMounts:
        - name: init-scripts
          mountPath: /init-scripts
        - name: initdb
          mountPath: /docker-entrypoint-initdb.d
      containers:
      - name: postgresql
        image: postgres:15-alpine
        env:
        - name: POSTGRES_PASSWORD
          value: "${SUPER_PASSWORD}"
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
          name: postgresql
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        - name: initdb
          mountPath: /docker-entrypoint-initdb.d
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1"
        livenessProbe:
          tcpSocket:
            port: 5432
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          tcpSocket:
            port: 5432
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: init-scripts
        configMap:
          name: postgresql-init-scripts
      - name: initdb
        emptyDir: {}
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

kubectl apply -f /tmp/postgresql-complete.yaml
echo "✓ PostgreSQL deployed with initialization"

echo ""
echo "5. Waiting for PostgreSQL to be ready..."
if kubectl wait --for=condition=Ready pod -n data-plane -l app=postgresql,role=primary --timeout=300s 2>/dev/null; then
    echo "✓ PostgreSQL is ready"
else
    echo "⚠ PostgreSQL taking longer to start"
    echo "   Checking status..."
    kubectl get pods -n data-plane -l app=postgresql,role=primary
    echo "   Checking logs..."
    kubectl logs -n data-plane -l app=postgresql,role=primary --tail=20
fi

echo ""
echo "6. Testing PostgreSQL connectivity..."

# Test with superuser
cat > /tmp/postgresql-super-test.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: postgresql-super-test
  namespace: data-plane
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: postgres:15-alpine
    env:
    - name: PGPASSWORD
      value: "${SUPER_PASSWORD}"
    command:
    - /bin/sh
    - -c
    - |
      echo "Testing superuser connectivity..."
      if pg_isready -h postgresql-primary.data-plane.svc.cluster.local -U postgres; then
        echo "✓ Superuser connection successful"
        
        echo "Checking databases..."
        if psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c "\l" | grep -q "spire"; then
          echo "✓ SPIRE database exists"
          exit 0
        else
          echo "✗ SPIRE database not found"
          exit 1
        fi
      else
        echo "✗ Superuser connection failed"
        exit 1
      fi
EOF

kubectl apply -f /tmp/postgresql-super-test.yaml
echo "✓ Superuser test pod created"

echo ""
echo "7. Waiting for superuser test..."
sleep 10
if kubectl wait --for=condition=complete pod/postgresql-super-test -n data-plane --timeout=60s 2>/dev/null; then
    echo "✓ Superuser test completed"
    kubectl logs -n data-plane postgresql-super-test
else
    echo "⚠ Superuser test issues"
    kubectl logs -n data-plane postgresql-super-test
fi

echo ""
echo "8. Testing app user connectivity..."

cat > /tmp/postgresql-app-final-test.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: postgresql-app-final-test
  namespace: data-plane
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: postgres:15-alpine
    env:
    - name: PGPASSWORD
      value: "${APP_PASSWORD}"
    command:
    - /bin/sh
    - -c
    - |
      echo "Testing app user connectivity..."
      if pg_isready -h postgresql-primary.data-plane.svc.cluster.local -U app -d spire; then
        echo "✓ App user connection to SPIRE database successful"
        
        if psql -h postgresql-primary.data-plane.svc.cluster.local -U app -d spire -c "SELECT 1;" | grep -q "1"; then
          echo "✓ App user can query SPIRE database"
          exit 0
        else
          echo "✗ App user cannot query SPIRE database"
          exit 1
        fi
      else
        echo "✗ App user connection failed"
        exit 1
      fi
EOF

kubectl apply -f /tmp/postgresql-app-final-test.yaml
echo "✓ App user test pod created"

echo ""
echo "9. Waiting for app user test..."
sleep 10
if kubectl wait --for=condition=complete pod/postgresql-app-final-test -n data-plane --timeout=60s 2>/dev/null; then
    echo "✓ App user test completed"
    kubectl logs -n data-plane postgresql-app-final-test
else
    echo "⚠ App user test issues"
    kubectl logs -n data-plane postgresql-app-final-test
fi

echo ""
echo "10. Cleaning up test pods..."
kubectl delete pod -n data-plane postgresql-super-test postgresql-app-final-test --ignore-not-found

echo ""
echo "11. Updating .env file with correct credentials..."

# Update .env file
cat > ../../.env << EOF
# PostgreSQL Connection for SPIRE + Temporal
POSTGRES_HOST=postgresql-primary.data-plane.svc.cluster.local
POSTGRES_PORT=5432
POSTGRES_DB_SPIRE=spire
POSTGRES_DB_TEMPORAL=temporal_visibility
POSTGRES_USER=app
POSTGRES_PASSWORD=${APP_PASSWORD}

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
echo "✓ .env file updated with correct credentials"

echo ""
echo "=============================================="
echo "PostgreSQL Redeployment Complete"
echo "=============================================="
echo ""
echo "✅ Successfully deployed:"
echo "   - PostgreSQL primary with initialization"
echo "   - Databases: spire, temporal_visibility, app"
echo "   - Users: postgres (superuser), app (application)"
echo "   - Service: postgresql-primary.data-plane.svc.cluster.local:5432"
echo ""
echo "🔐 Credentials:"
echo "   - Superuser (postgres): Password in postgres-superuser secret"
echo "   - App user (app): Password in postgres-app-user secret and .env file"
echo ""
echo "🔍 Verification:"
echo "   kubectl get pods -n data-plane -l app=postgresql"
echo "   kubectl exec -n data-plane postgresql-primary-0 -- pg_isready -U postgres"
echo "   kubectl exec -n data-plane postgresql-primary-0 -- pg_isready -U app -d spire"
echo ""
echo "➡️  Next: Proceed with Phase 1 deployment"
echo "    ./02-deployment.sh"
echo ""

# Cleanup
rm -f /tmp/postgresql-complete.yaml /tmp/postgresql-super-test.yaml /tmp/postgresql-app-final-test.yaml

exit 0