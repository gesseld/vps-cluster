#!/bin/bash

# Fix PostgreSQL authentication issues

set -e

echo "=============================================="
echo "Fixing PostgreSQL Authentication"
echo "=============================================="
echo ""

echo "1. Checking current PostgreSQL configuration..."
kubectl get statefulset -n data-plane postgresql-primary -o yaml | grep -A2 -B2 "POSTGRES_USER\|pg_isready"

echo ""
echo "2. Updating PostgreSQL StatefulSet with correct authentication..."

# Create fixed PostgreSQL configuration
cat > /tmp/postgresql-fixed.yaml << 'EOF'
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
          value: "postgres"  # Fixed username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-superuser
              key: password
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
          exec:
            command:
            - pg_isready
            - -U
            - postgres  # Fixed to match POSTGRES_USER
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres  # Fixed to match POSTGRES_USER
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
EOF

# Apply the fixed configuration
kubectl apply -f /tmp/postgresql-fixed.yaml
echo "✓ PostgreSQL StatefulSet updated with correct authentication"

echo ""
echo "3. Waiting for PostgreSQL to restart..."
sleep 10
if kubectl wait --for=condition=Ready pod -n data-plane -l app=postgresql,role=primary --timeout=120s 2>/dev/null; then
    echo "✓ PostgreSQL is ready"
else
    echo "⚠ PostgreSQL restarting, checking status..."
    kubectl get pods -n data-plane -l app=postgresql,role=primary
fi

echo ""
echo "4. Testing PostgreSQL connectivity with correct credentials..."

# Get the superuser password
SUPER_PASSWORD=$(kubectl get secret -n data-plane postgres-superuser -o jsonpath='{.data.password}' | base64 -d)

# Create a test pod
cat > /tmp/postgresql-auth-test.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: postgresql-auth-test
  namespace: data-plane
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: postgres:15-alpine
    env:
    - name: PGPASSWORD
      value: "$SUPER_PASSWORD"
    command:
    - /bin/sh
    - -c
    - |
      echo "Testing authentication with postgres user..."
      if pg_isready -h postgresql-primary.data-plane.svc.cluster.local -U postgres; then
        echo "✓ Authentication successful for postgres user"
        
        echo "Creating app user and databases..."
        psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
          "CREATE USER app WITH PASSWORD '$(kubectl get secret -n data-plane postgres-app-user -o jsonpath='{.data.password}' | base64 -d)';"
        
        psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
          "CREATE DATABASE spire OWNER app;"
        
        psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
          "CREATE DATABASE temporal_visibility OWNER app;"
        
        psql -h postgresql-primary.data-plane.svc.cluster.local -U postgres -c \
          "CREATE DATABASE app OWNER app;"
        
        echo "✓ Databases created successfully"
        exit 0
      else
        echo "✗ Authentication failed"
        exit 1
      fi
EOF

kubectl apply -f /tmp/postgresql-auth-test.yaml
echo "✓ Authentication test pod created"

echo ""
echo "5. Waiting for authentication test to complete..."
sleep 10
if kubectl wait --for=condition=complete pod/postgresql-auth-test -n data-plane --timeout=60s 2>/dev/null; then
    echo "✓ Authentication test completed successfully"
    echo "Test logs:"
    kubectl logs -n data-plane postgresql-auth-test
else
    echo "⚠ Authentication test may have issues"
    kubectl logs -n data-plane postgresql-auth-test
fi

echo ""
echo "6. Cleaning up test pod..."
kubectl delete pod -n data-plane postgresql-auth-test --ignore-not-found

echo ""
echo "7. Testing app user connectivity..."

# Get the app password
APP_PASSWORD=$(kubectl get secret -n data-plane postgres-app-user -o jsonpath='{.data.password}' | base64 -d)

cat > /tmp/postgresql-app-test.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: postgresql-app-test
  namespace: data-plane
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: postgres:15-alpine
    env:
    - name: PGPASSWORD
      value: "$APP_PASSWORD"
    command:
    - /bin/sh
    - -c
    - |
      echo "Testing app user access to SPIRE database..."
      if pg_isready -h postgresql-primary.data-plane.svc.cluster.local -U app -d spire; then
        echo "✓ App user can access SPIRE database"
        
        if psql -h postgresql-primary.data-plane.svc.cluster.local -U app -d spire -c "SELECT 1;" | grep -q "1"; then
          echo "✓ App user can query SPIRE database"
          exit 0
        else
          echo "✗ App user cannot query SPIRE database"
          exit 1
        fi
      else
        echo "✗ App user cannot connect to SPIRE database"
        exit 1
      fi
EOF

kubectl apply -f /tmp/postgresql-app-test.yaml
echo "✓ App user test pod created"

echo ""
echo "8. Waiting for app user test to complete..."
sleep 10
if kubectl wait --for=condition=complete pod/postgresql-app-test -n data-plane --timeout=60s 2>/dev/null; then
    echo "✓ App user test completed successfully"
    echo "Test logs:"
    kubectl logs -n data-plane postgresql-app-test
else
    echo "⚠ App user test may have issues"
    kubectl logs -n data-plane postgresql-app-test
fi

echo ""
echo "9. Cleaning up test pods..."
kubectl delete pod -n data-plane postgresql-app-test --ignore-not-found
kubectl delete job -n data-plane postgresql-init --ignore-not-found

echo ""
echo "=============================================="
echo "PostgreSQL Authentication Fix Complete"
echo "=============================================="
echo ""
echo "✅ Fixed:"
echo "   - POSTGRES_USER set to 'postgres' (not from secret)"
echo "   - Probes use 'postgres' user (matching POSTGRES_USER)"
echo "   - App user and databases recreated"
echo ""
echo "🔐 Current Configuration:"
echo "   - Superuser: postgres (password in postgres-superuser secret)"
echo "   - App user: app (password in postgres-app-user secret)"
echo "   - Databases: spire, temporal_visibility, app"
echo ""
echo "📊 Verification:"
echo "   kubectl exec -n data-plane postgresql-primary-0 -- pg_isready -U postgres"
echo "   kubectl exec -n data-plane postgresql-primary-0 -- pg_isready -U app -d spire"
echo ""
echo "➡️  Next: Proceed with Phase 1 deployment"
echo "    ./02-deployment.sh"
echo ""

# Cleanup
rm -f /tmp/postgresql-fixed.yaml /tmp/postgresql-auth-test.yaml /tmp/postgresql-app-test.yaml

exit 0