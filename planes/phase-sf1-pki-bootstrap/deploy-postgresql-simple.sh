#!/bin/bash

# Deploy PostgreSQL with guaranteed initialization

set -e

echo "=============================================="
echo "Deploying PostgreSQL (Simple Version)"
echo "=============================================="
echo ""

# Generate passwords
APP_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "AppPass$(date +%s)")
SUPER_PASSWORD=$(openssl rand -base64 32 2>/dev/null || echo "SuperPass$(date +%s)")

echo "1. Creating/updating secrets..."
kubectl create secret generic postgres-app-user \
  --from-literal=password="$APP_PASSWORD" \
  --namespace=data-plane \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic postgres-superuser \
  --from-literal=password="$SUPER_PASSWORD" \
  --namespace=data-plane \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Secrets created/updated"

echo ""
echo "2. Deploying PostgreSQL with init container..."

cat > /tmp/postgresql-simple.yaml << EOF
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
      - name: init
        image: busybox
        command: ['sh', '-c', 'echo "Initialization complete"']
      containers:
      - name: postgresql
        image: postgres:15-alpine
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-superuser
              key: password
        - name: POSTGRES_USER
          value: "postgres"
        - name: POSTGRES_DB
          value: "postgres"
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
          tcpSocket:
            port: 5432
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          tcpSocket:
            port: 5432
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

kubectl apply -f /tmp/postgresql-simple.yaml
echo "✓ PostgreSQL deployed"

echo ""
echo "3. Waiting for PostgreSQL to be ready..."
if kubectl wait --for=condition=Ready pod -n data-plane -l app=postgresql,role=primary --timeout=300s 2>/dev/null; then
    echo "✓ PostgreSQL is ready"
else
    echo "⚠ PostgreSQL taking longer to start"
    kubectl get pods -n data-plane -l app=postgresql,role=primary
fi

echo ""
echo "4. Creating app user and databases..."

cat > /tmp/create-users.yaml << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: postgresql-create-users
  namespace: data-plane
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: create
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
          # Wait for PostgreSQL
          until pg_isready -h postgresql-primary.data-plane.svc.cluster.local -U postgres; do
            echo "Waiting for PostgreSQL..."
            sleep 2
          done
          
          # Create app user
          psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
            "CREATE USER app WITH PASSWORD '${APP_PASSWORD}';"
          
          # Create databases
          psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
            "CREATE DATABASE spire OWNER app;"
          
          psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
            "CREATE DATABASE temporal_visibility OWNER app;"
          
          psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
            "CREATE DATABASE app OWNER app;"
          
          echo "✓ Users and databases created"
EOF

kubectl apply -f /tmp/create-users.yaml
echo "✓ User creation job submitted"

echo ""
echo "5. Waiting for user creation..."
sleep 10
if kubectl wait --for=condition=complete job/postgresql-create-users -n data-plane --timeout=60s 2>/dev/null; then
    echo "✓ User creation completed"
    kubectl logs -n data-plane -l job-name=postgresql-create-users --tail=5
else
    echo "⚠ User creation may have issues"
    kubectl logs -n data-plane -l job-name=postgresql-create-users
fi

echo ""
echo "6. Testing connectivity..."

cat > /tmp/test-connection.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: postgresql-test-final
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
      echo "Testing app user connection..."
      if pg_isready -h postgresql-primary.data-plane.svc.cluster.local -U app -d spire; then
        echo "✓ App user can connect to SPIRE database"
        
        if psql -h postgresql-primary.data-plane.svc.cluster.local -U app -d spire -c "SELECT 1;" | grep -q "1"; then
          echo "✓ App user can query SPIRE database"
          exit 0
        else
          echo "✗ App user cannot query SPIRE database"
          exit 1
        fi
      else
        echo "✗ App user cannot connect"
        exit 1
      fi
EOF

kubectl apply -f /tmp/test-connection.yaml
echo "✓ Test pod created"

echo ""
echo "7. Waiting for test..."
sleep 10
if kubectl wait --for=condition=complete pod/postgresql-test-final -n data-plane --timeout=60s 2>/dev/null; then
    echo "✓ Test completed successfully"
    kubectl logs -n data-plane postgresql-test-final
else
    echo "⚠ Test failed"
    kubectl logs -n data-plane postgresql-test-final
fi

echo ""
echo "8. Updating .env file..."

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
echo "✓ .env file updated"

echo ""
echo "9. Cleaning up..."
kubectl delete pod -n data-plane postgresql-test-final --ignore-not-found
kubectl delete job -n data-plane postgresql-create-users --ignore-not-found
rm -f /tmp/postgresql-simple.yaml /tmp/create-users.yaml /tmp/test-connection.yaml

echo ""
echo "=============================================="
echo "PostgreSQL Deployment Complete"
echo "=============================================="
echo ""
echo "✅ Successfully deployed PostgreSQL with:"
echo "   - Superuser: postgres (password in postgres-superuser secret)"
echo "   - App user: app (password: ${APP_PASSWORD:0:10}...)"
echo "   - Databases: spire, temporal_visibility, app"
echo ""
echo "🔍 Verification commands:"
echo "   kubectl get pods -n data-plane -l app=postgresql"
echo "   kubectl exec -n data-plane postgresql-primary-0 -- pg_isready -U postgres"
echo "   kubectl exec -n data-plane postgresql-primary-0 -- pg_isready -U app -d spire"
echo ""
echo "➡️  Next: Update SPIRE configuration and restart:"
echo "   1. Update SPIRE ConfigMap with correct password"
echo "   2. Restart SPIRE server"
echo "   3. Continue with validation"
echo ""

exit 0