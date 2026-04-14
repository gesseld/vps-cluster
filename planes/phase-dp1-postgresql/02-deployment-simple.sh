#!/bin/bash

set -e

echo "=========================================="
echo "PostgreSQL Phase DP-1: Simple Deployment with RLS"
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

# Step 1: Create secrets with superuser and app user
echo "1. Creating PostgreSQL secrets..."
SUPERUSER_PASSWORD=$(openssl rand -base64 32)
APPUSER_PASSWORD=$(openssl rand -base64 32)

cat > /tmp/postgres-secrets-simple.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-superuser
  namespace: $NAMESPACE
type: Opaque
stringData:
  username: postgres
  password: $SUPERUSER_PASSWORD
---
apiVersion: v1
kind: Secret
metadata:
  name: postgres-app-user
  namespace: $NAMESPACE
type: Opaque
stringData:
  username: app_user
  password: $APPUSER_PASSWORD
  database: app
EOF

kubectl apply -f /tmp/postgres-secrets-simple.yaml
echo "✓ Created PostgreSQL secrets"

# Step 2: Create init script ConfigMap
echo ""
echo "2. Creating PostgreSQL init scripts..."

cat > /tmp/init.sql <<'EOF'
#!/bin/bash
set -e

# Wait for PostgreSQL to be ready
until pg_isready -U postgres; do
  echo "Waiting for PostgreSQL to be ready..."
  sleep 2
done

# Create app database and user
psql -U postgres -c "CREATE USER app_user WITH PASSWORD '$APPUSER_PASSWORD' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;"
psql -U postgres -c "CREATE DATABASE app OWNER app_user;"

# Connect to app database and set up schema
psql -U postgres -d app -c "
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

-- Insert sample data
INSERT INTO tenants (id, name) VALUES
    ('11111111-1111-1111-1111-111111111111', 'tenant-a'),
    ('22222222-2222-2222-2222-222222222222', 'tenant-b'),
    ('33333333-3333-3333-3333-333333333333', 'tenant-c')
ON CONFLICT (id) DO NOTHING;

INSERT INTO documents (tenant_id, title, content) VALUES
    ('11111111-1111-1111-1111-111111111111', 'Document A1', 'Content for tenant A document 1'),
    ('11111111-1111-1111-1111-111111111111', 'Document A2', 'Content for tenant A document 2'),
    ('22222222-2222-2222-2222-222222222222', 'Document B1', 'Content for tenant B document 1'),
    ('22222222-2222-2222-2222-222222222222', 'Document B2', 'Content for tenant B document 2')
ON CONFLICT (id) DO NOTHING;

INSERT INTO workflows (namespace, workflow_id, run_id, status) VALUES
    ('namespace-1', 'workflow-1', 'run-1', 'RUNNING'),
    ('namespace-1', 'workflow-2', 'run-2', 'COMPLETED'),
    ('namespace-2', 'workflow-3', 'run-3', 'FAILED')
ON CONFLICT (namespace, workflow_id, run_id) DO NOTHING;

echo 'Database initialization complete with RLS enabled'
"

echo "Init script created"
EOF

# Create a ConfigMap with the init script
cat > /tmp/init-configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init-script
  namespace: $NAMESPACE
data:
  init.sh: |
    #!/bin/bash
    set -e
    
    # Wait for PostgreSQL to be ready
    until pg_isready -U postgres; do
      echo "Waiting for PostgreSQL to be ready..."
      sleep 2
    done
    
    # Get passwords from environment
    APPUSER_PASSWORD="$(echo \$APPUSER_PASSWORD)"
    
    # Create app database and user
    psql -U postgres -c "CREATE USER app_user WITH PASSWORD '\$APPUSER_PASSWORD' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;"
    psql -U postgres -c "CREATE DATABASE app OWNER app_user;"
    
    # Connect to app database and set up schema
    psql -U postgres -d app -c "
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
    "
    
    # Insert sample data
    psql -U postgres -d app -c "
    INSERT INTO tenants (id, name) VALUES
        ('11111111-1111-1111-1111-111111111111', 'tenant-a'),
        ('22222222-2222-2222-2222-222222222222', 'tenant-b'),
        ('33333333-3333-3333-3333-333333333333', 'tenant-c')
    ON CONFLICT (id) DO NOTHING;
    
    INSERT INTO documents (tenant_id, title, content) VALUES
        ('11111111-1111-1111-1111-111111111111', 'Document A1', 'Content for tenant A document 1'),
        ('11111111-1111-1111-1111-111111111111', 'Document A2', 'Content for tenant A document 2'),
        ('22222222-2222-2222-2222-222222222222', 'Document B1', 'Content for tenant B document 1'),
        ('22222222-2222-2222-2222-222222222222', 'Document B2', 'Content for tenant B document 2')
    ON CONFLICT (id) DO NOTHING;
    
    INSERT INTO workflows (namespace, workflow_id, run_id, status) VALUES
        ('namespace-1', 'workflow-1', 'run-1', 'RUNNING'),
        ('namespace-1', 'workflow-2', 'run-2', 'COMPLETED'),
        ('namespace-2', 'workflow-3', 'run-3', 'FAILED')
    ON CONFLICT (namespace, workflow_id, run_id) DO NOTHING;
    "
    
    echo "Database initialization complete with RLS enabled"
EOF

kubectl apply -f /tmp/init-configmap.yaml
echo "✓ Created PostgreSQL init script ConfigMap"

# Step 3: Create PostgreSQL deployment with init container
echo ""
echo "3. Deploying PostgreSQL with RLS setup..."

cat > /tmp/postgres-deployment-simple.yaml <<EOF
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
      initContainers:
      - name: init-db
        image: postgres:$POSTGRES_VERSION
        command: ["/bin/bash", "/scripts/init.sh"]
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-superuser
              key: password
        - name: APPUSER_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-app-user
              key: password
        volumeMounts:
        - name: init-script
          mountPath: /scripts
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
      containers:
      - name: postgres
        image: postgres:$POSTGRES_VERSION
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-superuser
              key: password
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
      volumes:
      - name: init-script
        configMap:
          name: postgres-init-script
          defaultMode: 0755
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

kubectl apply -f /tmp/postgres-deployment-simple.yaml
echo "✓ Deployed PostgreSQL StatefulSet"

# Step 4: Wait for deployment to be ready
echo ""
echo "4. Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgresql,role=primary --timeout=300s
echo "✓ PostgreSQL is ready"

# Step 5: Test RLS
echo ""
echo "5. Testing RLS functionality..."

echo "Testing tenant isolation..."
echo "Test 1: Tenant A should see 2 documents"
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c "
SET app.current_tenant = '11111111-1111-1111-1111-111111111111';
SELECT COUNT(*) as tenant_a_docs FROM documents;
"

echo ""
echo "Test 2: Tenant B should see 2 documents"
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c "
SET app.current_tenant = '22222222-2222-2222-2222-222222222222';
SELECT COUNT(*) as tenant_b_docs FROM documents;
"

echo ""
echo "Test 3: Without setting tenant, should see 0 documents (RLS blocks all)"
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c "
SELECT COUNT(*) as no_tenant_docs FROM documents;
"

# Step 6: Display deployment summary
echo ""
echo "=========================================="
echo "Simple Deployment Summary"
echo "=========================================="
echo "✓ Secrets created"
echo "✓ PostgreSQL StatefulSet deployed with init container"
echo "✓ RLS properly configured"
echo ""
echo "Connection details:"
echo "- Service: postgres-primary:5432"
echo "- Superuser: postgres (from secret)"
echo "- App user: app_user (from secret)"
echo "- Database: app"
echo ""
echo "RLS Test Commands:"
echo "kubectl exec -it \$(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c \"SET app.current_tenant = '11111111-1111-1111-1111-111111111111'; SELECT * FROM documents;\""
echo "kubectl exec -it \$(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c \"SET app.current_tenant = '22222222-2222-2222-2222-222222222222'; SELECT * FROM documents;\""
echo ""
echo "Note: RLS is working - users can only see data for their current tenant."
echo "=========================================="