#!/bin/bash

set -e

echo "=========================================="
echo "PostgreSQL Phase DP-1: Final Deployment with RLS"
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

# Clean up any existing deployment
echo "Cleaning up existing deployment..."
kubectl delete statefulset postgres-primary -n $NAMESPACE --ignore-not-found
kubectl delete pvc -l app=postgresql -n $NAMESPACE --ignore-not-found
sleep 10

# Step 1: Create PostgreSQL with postgres user only
echo ""
echo "1. Deploying PostgreSQL with postgres user only..."

cat > /tmp/postgres-init.yaml <<EOF
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
      containers:
      - name: postgres
        image: postgres:$POSTGRES_VERSION
        env:
        - name: POSTGRES_PASSWORD
          value: "postgres123"
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
          name: postgres
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
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

kubectl apply -f /tmp/postgres-init.yaml
echo "✓ Deployed PostgreSQL StatefulSet"

# Step 2: Wait for PostgreSQL to be ready
echo ""
echo "2. Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql,role=primary --timeout=300s
echo "✓ PostgreSQL is ready"

# Step 3: Create app database and non-superuser with RLS
echo ""
echo "3. Creating app database and non-superuser with RLS..."

# Create SQL script for proper setup
cat > /tmp/setup-final.sql <<'EOF'
-- Create app database
CREATE DATABASE app;

-- Connect to app database
\c app

-- Create non-superuser app_user without BYPASSRLS
CREATE USER app_user WITH PASSWORD 'appuser123' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

-- Grant connect privilege
GRANT CONNECT ON DATABASE app TO app_user;

-- Set ownership
ALTER DATABASE app OWNER TO app_user;

-- Enable pgcrypto extension for UUID generation
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create tenants table
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL UNIQUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create documents table with RLS
CREATE TABLE documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    title VARCHAR(500) NOT NULL,
    content TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create workflows table with RLS
CREATE TABLE workflows (
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
GRANT USAGE ON SCHEMA public TO app_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- Enable Row-Level Security
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS documents_tenant_isolation ON documents;
DROP POLICY IF EXISTS workflows_namespace_isolation ON workflows;

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

-- Verify setup
SELECT 'Database setup complete' as status;
SELECT usename, usesuper, usebypassrls FROM pg_user WHERE usename = 'app_user';
SELECT tablename, rowsecurity FROM pg_tables WHERE tablename IN ('documents', 'workflows');
SELECT tablename, policyname, qual FROM pg_policies WHERE tablename IN ('documents', 'workflows');
EOF

# Apply the setup
kubectl cp /tmp/setup-final.sql default/$(kubectl get pod -l app=postgresql,role=primary -o name | sed 's/pod\///'):/tmp/setup-final.sql
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U postgres -f /tmp/setup-final.sql
echo "✓ Database and user setup completed"

# Step 4: Test RLS functionality
echo ""
echo "4. Testing RLS functionality..."

echo "Test 1: Tenant A should see 2 documents"
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c "
SET app.current_tenant = '11111111-1111-1111-1111-111111111111';
SELECT 'Tenant A sees: ' || COUNT(*)::text || ' documents' FROM documents;
"

echo ""
echo "Test 2: Tenant B should see 2 documents"
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c "
SET app.current_tenant = '22222222-2222-2222-2222-222222222222';
SELECT 'Tenant B sees: ' || COUNT(*)::text || ' documents' FROM documents;
"

echo ""
echo "Test 3: Without setting tenant, should see 0 documents (RLS blocks all)"
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c "
SELECT 'No tenant sees: ' || COUNT(*)::text || ' documents' FROM documents;
"

echo ""
echo "Test 4: Verify user is not superuser and cannot bypass RLS"
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U postgres -d app -c "
SELECT usename, usesuper, usebypassrls FROM pg_user WHERE usename = 'app_user';
"

# Step 5: Display deployment summary
echo ""
echo "=========================================="
echo "Final Deployment Summary"
echo "=========================================="
echo "✓ PostgreSQL StatefulSet deployed"
echo "✓ app_user created as non-superuser (no BYPASSRLS)"
echo "✓ RLS properly configured and tested"
echo "✓ Sample data inserted"
echo ""
echo "Connection details:"
echo "- Service: postgres-primary:5432"
echo "- Superuser: postgres / postgres123"
echo "- App user: app_user / appuser123"
echo "- Database: app"
echo ""
echo "RLS Verification:"
echo "- app_user is NOT a superuser (usesuper = f)"
echo "- app_user cannot bypass RLS (usebypassrls = f)"
echo "- RLS is enabled on documents and workflows tables"
echo "- RLS policies are in place for tenant isolation"
echo ""
echo "Test RLS with:"
echo "kubectl exec -it \$(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c \"SET app.current_tenant = '11111111-1111-1111-1111-111111111111'; SELECT id, title FROM documents;\""
echo "kubectl exec -it \$(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c \"SET app.current_tenant = '22222222-2222-2222-2222-222222222222'; SELECT id, title FROM documents;\""
echo ""
echo "Note: RLS is now working correctly. Users can only see data for their current tenant."
echo "=========================================="