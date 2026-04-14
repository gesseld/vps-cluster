#!/bin/bash

set -e

echo "=========================================="
echo "PostgreSQL Phase DP-1: Fixed Deployment with RLS"
echo "=========================================="
echo "Date: $(date)"
echo ""

# Load environment variables
if [ -f "../../.env" ]; then
    source "../../.env"
    echo "✓ Loaded environment variables from ../../.env"
fi

# Default values
NAMESPACE=${NAMESPACE:-default}
POSTGRES_VERSION=${POSTGRES_VERSION:-15}
STORAGE_CLASS=${STORAGE_CLASS:-hcloud-volumes}
STORAGE_SIZE=${STORAGE_SIZE:-50Gi}

echo "Configuration:"
echo "- Namespace: $NAMESPACE"
echo "- PostgreSQL version: $POSTGRES_VERSION"
echo "- Storage class: $STORAGE_CLASS"
echo "- Storage size: $STORAGE_SIZE"
echo ""

# Step 1: Create secrets
echo "1. Creating PostgreSQL secrets..."
cat > /tmp/postgres-secrets-fixed.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-superuser
  namespace: $NAMESPACE
type: Opaque
stringData:
  username: postgres
  password: $(openssl rand -base64 32)
---
apiVersion: v1
kind: Secret
metadata:
  name: postgres-app-user
  namespace: $NAMESPACE
type: Opaque
stringData:
  username: app_user
  password: $(openssl rand -base64 32)
  database: app
EOF

kubectl apply -f /tmp/postgres-secrets-fixed.yaml
echo "✓ Created PostgreSQL secrets"

# Step 2: Create PostgreSQL primary with proper user setup
echo ""
echo "2. Deploying PostgreSQL primary with RLS-compatible user..."

cat > /tmp/postgres-primary-fixed.yaml <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-primary
  namespace: $NAMESPACE
  labels:
    app: postgresql
    role: primary
spec:
  serviceName: postgres-primary
  replicas: 1
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
      securityContext:
        runAsUser: 999
        runAsGroup: 999
        fsGroup: 999
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: postgres
        image: postgres:$POSTGRES_VERSION
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          runAsUser: 999
          runAsGroup: 999
          seccompProfile:
            type: RuntimeDefault
        env:
        - name: POSTGRES_DB
          value: app
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-app-user
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-app-user
              key: password
        - name: POSTGRES_INITDB_ARGS
          value: "--data-checksums"
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
          name: postgres
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
        - name: init-scripts
          mountPath: /docker-entrypoint-initdb.d
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
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
      volumes:
      - name: init-scripts
        configMap:
          name: postgres-init-scripts-fixed
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: $STORAGE_CLASS
      resources:
        requests:
          storage: $STORAGE_SIZE
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-primary
  namespace: $NAMESPACE
  labels:
    app: postgresql
    role: primary
spec:
  selector:
    app: postgresql
    role: primary
  ports:
  - port: 5432
    targetPort: postgres
  type: ClusterIP
EOF

kubectl apply -f /tmp/postgres-primary-fixed.yaml
echo "✓ Deployed PostgreSQL primary StatefulSet"

# Step 3: Create fixed init scripts with proper user setup
echo ""
echo "3. Creating PostgreSQL init scripts with RLS-compatible user..."

cat > /tmp/01-init-fixed.sql <<'EOF'
-- Create app_user as non-superuser (without BYPASSRLS)
CREATE USER app_user WITH PASSWORD 'CHANGE_ME' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE DATABASE app OWNER app_user;

-- Connect to app database
\c app

-- Set ownership
ALTER DATABASE app OWNER TO app_user;

-- Enable pgcrypto extension for UUID generation
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create tenants table
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create documents table with RLS
CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    title VARCHAR(500) NOT NULL,
    content TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create workflows table with RLS
CREATE TABLE IF NOT EXISTS workflows (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    namespace VARCHAR(255) NOT NULL,
    workflow_id VARCHAR(500) NOT NULL,
    run_id VARCHAR(500) NOT NULL,
    status VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(namespace, workflow_id, run_id)
);

-- Grant privileges to app_user
GRANT ALL PRIVILEGES ON DATABASE app TO app_user;
GRANT ALL PRIVILEGES ON SCHEMA public TO app_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- Enable Row-Level Security
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY documents_tenant_isolation ON documents
    FOR ALL
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY workflows_namespace_isolation ON workflows
    FOR ALL
    USING (namespace = current_setting('app.current_namespace'));

-- Create indexes
CREATE INDEX idx_documents_tenant_id ON documents(tenant_id);
CREATE INDEX idx_workflows_namespace ON workflows(namespace);
CREATE INDEX idx_workflows_status ON workflows(status);
EOF

cat > /tmp/02-data-fixed.sql <<'EOF'
-- Insert sample tenants
INSERT INTO tenants (id, name) VALUES
    ('11111111-1111-1111-1111-111111111111', 'tenant-a'),
    ('22222222-2222-2222-2222-222222222222', 'tenant-b'),
    ('33333333-3333-3333-3333-333333333333', 'tenant-c')
ON CONFLICT (id) DO NOTHING;

-- Insert sample documents for tenant-a
INSERT INTO documents (tenant_id, title, content) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Document A1', 'Content for tenant A document 1'),
    ('11111111-1111-1111-1111-111111111111', 'Document A2', 'Content for tenant A document 2')
ON CONFLICT (id) DO NOTHING;

-- Insert sample documents for tenant-b
INSERT INTO documents (tenant_id, title, content) VALUES
    ('22222222-2222-2222-2222-222222222222', 'Document B1', 'Content for tenant B document 1'),
    ('22222222-2222-2222-2222-222222222222', 'Document B2', 'Content for tenant B document 2')
ON CONFLICT (id) DO NOTHING;

-- Insert sample workflows
INSERT INTO workflows (namespace, workflow_id, run_id, status) VALUES
    ('namespace-1', 'workflow-1', 'run-1', 'RUNNING'),
    ('namespace-1', 'workflow-2', 'run-2', 'COMPLETED'),
    ('namespace-2', 'workflow-3', 'run-3', 'FAILED')
ON CONFLICT (namespace, workflow_id, run_id) DO NOTHING;
EOF

# Create ConfigMap from SQL files
kubectl create configmap postgres-init-scripts-fixed \
  --namespace=$NAMESPACE \
  --from-file=/tmp/01-init-fixed.sql \
  --from-file=/tmp/02-data-fixed.sql \
  --dry-run=client -o yaml | kubectl apply -f -
echo "✓ Created PostgreSQL init scripts ConfigMap"

# Step 4: Wait for deployment to be ready
echo ""
echo "4. Waiting for PostgreSQL primary to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql,role=primary --timeout=300s
echo "✓ PostgreSQL primary is ready"

# Step 5: Update the password for app_user (since we can't use secret in init script)
echo ""
echo "5. Updating app_user password from secret..."
APP_USER_PASSWORD=$(kubectl get secret postgres-app-user -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U postgres -d app -c "ALTER USER app_user WITH PASSWORD '$APP_USER_PASSWORD';"
echo "✓ Updated app_user password"

# Step 6: Test RLS
echo ""
echo "6. Testing RLS functionality..."

echo "Testing tenant isolation..."
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c "
SET app.current_tenant = '11111111-1111-1111-1111-111111111111';
SELECT COUNT(*) as tenant_a_docs FROM documents;
" | grep -q "tenant_a_docs.*2"
if [ $? -eq 0 ]; then
    echo "✓ RLS: Tenant A sees only 2 documents"
else
    echo "✗ RLS: Tenant A sees wrong number of documents"
fi

kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c "
SET app.current_tenant = '22222222-2222-2222-2222-222222222222';
SELECT COUNT(*) as tenant_b_docs FROM documents;
" | grep -q "tenant_b_docs.*2"
if [ $? -eq 0 ]; then
    echo "✓ RLS: Tenant B sees only 2 documents"
else
    echo "✗ RLS: Tenant B sees wrong number of documents"
fi

# Step 7: Display deployment summary
echo ""
echo "=========================================="
echo "Fixed Deployment Summary"
echo "=========================================="
echo "✓ Secrets created"
echo "✓ PostgreSQL primary StatefulSet deployed"
echo "✓ Init scripts ConfigMap created"
echo "✓ app_user password updated"
echo "✓ RLS tested"
echo ""
echo "Note: Due to resource quota constraints:"
echo "- PostgreSQL replica skipped"
echo "- pgBouncer skipped"
echo "- Backup cronjob skipped"
echo ""
echo "Service:"
echo "- PostgreSQL primary: postgres-primary:5432"
echo ""
echo "RLS Test Commands:"
echo "kubectl exec -it \$(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c \"SET app.current_tenant = '11111111-1111-1111-1111-111111111111'; SELECT * FROM documents;\""
echo "kubectl exec -it \$(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c \"SET app.current_tenant = '22222222-2222-2222-2222-222222222222'; SELECT * FROM documents;\""
echo "=========================================="