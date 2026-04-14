#!/bin/bash

set -e

echo "=========================================="
echo "PostgreSQL Phase DP-1: Deployment"
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
POSTGRES_VERSION=${POSTGRES_VERSION:-15-alpine}
STORAGE_CLASS=${STORAGE_CLASS:-hcloud-volumes}
STORAGE_SIZE=${STORAGE_SIZE:-50Gi}
PGBOUNCER_VERSION=${PGBOUNCER_VERSION:-1.15.0}

# Generate SPIRE database password
SPIRE_DB_PASSWORD=$(openssl rand -base64 24)
export SPIRE_DB_PASSWORD

echo "Configuration:"
echo "- Namespace: $NAMESPACE"
echo "- PostgreSQL version: $POSTGRES_VERSION"
echo "- Storage class: $STORAGE_CLASS"
echo "- Storage size: $STORAGE_SIZE"
echo "- pgBouncer version: $PGBOUNCER_VERSION"
echo ""

# Step 1: Label nodes for topology spread
echo "1. Labeling nodes for topology spread..."
NODES=$(kubectl get nodes --no-headers -o custom-columns=":metadata.name")
NODE_COUNT=$(echo "$NODES" | wc -l)
echo "Found $NODE_COUNT nodes"

if [ $NODE_COUNT -ge 2 ]; then
    # Label first node for primary PostgreSQL
    PRIMARY_NODE=$(echo "$NODES" | head -1)
    kubectl label node "$PRIMARY_NODE" node-role=storage-heavy --overwrite
    echo "✓ Labeled $PRIMARY_NODE as storage-heavy (primary)"
    
    # Label second node for replica PostgreSQL
    REPLICA_NODE=$(echo "$NODES" | sed -n '2p')
    kubectl label node "$REPLICA_NODE" node-role=storage-heavy --overwrite
    echo "✓ Labeled $REPLICA_NODE as storage-heavy (replica)"
    
    # Label remaining nodes (if any) for MinIO/other storage
    COUNTER=3
    while IFS= read -r NODE; do
        if [ -n "$NODE" ] && [ "$NODE" != "$PRIMARY_NODE" ] && [ "$NODE" != "$REPLICA_NODE" ]; then
            kubectl label node "$NODE" node-role=storage-available --overwrite
            echo "✓ Labeled $NODE as storage-available"
            ((COUNTER++))
        fi
    done <<< "$NODES"
else
    echo "⚠ Only $NODE_COUNT node(s) available. Using single node for all components."
    SINGLE_NODE=$(echo "$NODES" | head -1)
    kubectl label node "$SINGLE_NODE" node-role=storage-heavy --overwrite
    echo "✓ Labeled $SINGLE_NODE as storage-heavy"
fi

# Step 2: Create secrets
echo ""
echo "2. Creating PostgreSQL secrets..."
SPIRE_DB_PASSWORD=$(openssl rand -base64 32)
cat > /tmp/postgres-secrets.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: spire-database-creds
  namespace: spire
type: Opaque
stringData:
  SPIRE_DB_PASSWORD: $SPIRE_DB_PASSWORD
---
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
---
apiVersion: v1
kind: Secret
metadata:
  name: postgres-replication
  namespace: $NAMESPACE
type: Opaque
stringData:
  username: replicator
  password: $(openssl rand -base64 32)
---
apiVersion: v1
kind: Secret
metadata:
  name: pgbouncer-auth
  namespace: $NAMESPACE
type: Opaque
stringData:
  userlist.txt: |
    "app_user" "$(openssl rand -base64 32)"
  pgbouncer.ini: |
    [databases]
    app = host=postgres-primary port=5432 dbname=app
    app_ro = host=postgres-replica port=5432 dbname=app
    
    [pgbouncer]
    listen_addr = *
    listen_port = 6432
    auth_type = md5
    auth_file = /etc/pgbouncer/userlist.txt
    pool_mode = transaction
    max_client_conn = 500
    default_pool_size = 20
    reserve_pool_size = 5
    log_connections = 1
    log_disconnections = 1
    stats_period = 60
    server_reset_query = DISCARD ALL
    server_check_query = SELECT 1
    server_check_delay = 30
    ignore_startup_parameters = extra_float_digits
EOF

kubectl apply -f /tmp/postgres-secrets.yaml
echo "✓ Created PostgreSQL secrets"

# Step 3: Create PostgreSQL primary StatefulSet
echo ""
echo "3. Deploying PostgreSQL primary StatefulSet..."
mkdir -p data-plane/postgresql

cat > data-plane/postgresql/primary-statefulset.yaml <<EOF
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
        runAsNonRoot: false
        fsGroup: 999
        seccompProfile:
          type: RuntimeDefault
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-role
                operator: In
                values:
                - storage-heavy
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - minio
              topologyKey: kubernetes.io/hostname
      initContainers:
      - name: volume-permissions
        image: busybox
        command: ["sh", "-c", "chmod -R 777 /var/lib/postgresql/data && chown -R 999:999 /var/lib/postgresql/data"]
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
      containers:
      - name: postgres
        image: postgres:$POSTGRES_VERSION
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          runAsNonRoot: false
          runAsUser: 999
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
            cpu: "100m"
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
          name: postgres-init-scripts
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

kubectl apply -f data-plane/postgresql/primary-statefulset.yaml
echo "✓ Deployed PostgreSQL primary StatefulSet"

# Step 4: Create PostgreSQL replica StatefulSet
echo ""
echo "4. Deploying PostgreSQL replica StatefulSet..."
cat > data-plane/postgresql/replica-statefulset.yaml <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-replica
  namespace: $NAMESPACE
  labels:
    app: postgresql
    role: replica
spec:
  serviceName: postgres-replica
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
      role: replica
  template:
    metadata:
      labels:
        app: postgresql
        role: replica
    spec:
      securityContext:
        runAsNonRoot: false
        fsGroup: 999
        seccompProfile:
          type: RuntimeDefault
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-role
                operator: In
                values:
                - storage-heavy
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - postgresql
                  - role
                  operator: In
                  values:
                  - primary
              topologyKey: kubernetes.io/hostname
      initContainers:
      - name: permission-fixer
        image: busybox
        command: ["sh", "-c", "chown -R 999:999 /var/lib/postgresql/data"]
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
      - name: clone-primary
        image: postgres:$POSTGRES_VERSION
        command:
        - bash
        - -c
        - |
          set -e
          until pg_basebackup -h postgres-primary -U replicator -D /var/lib/postgresql/data/pgdata -X stream -P; do
            echo "Waiting for primary to be ready..."
            sleep 5
          done
          echo "Base backup completed"
        env:
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-replication
              key: password
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
      containers:
      - name: postgres
        image: postgres:$POSTGRES_VERSION
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          runAsNonRoot: false
          runAsUser: 999
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
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        - name: PRIMARY_HOST
          value: postgres-primary
        command:
        - bash
        - -c
        - |
          set -e
          # Configure replication
          cat > /var/lib/postgresql/data/pgdata/recovery.conf <<EOR
          standby_mode = 'on'
          primary_conninfo = 'host=postgres-primary port=5432 user=replicator password=\$(PGPASSWORD) application_name=replica1'
          trigger_file = '/tmp/promote_to_primary'
          recovery_target_timeline = 'latest'
          EOR
          
          # Start PostgreSQL
          exec docker-entrypoint.sh postgres
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
            cpu: "100m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 30
          periodSeconds: 5
      volumes:
      - name: init-scripts
        configMap:
          name: postgres-init-scripts
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
  name: postgres-replica
  namespace: $NAMESPACE
  labels:
    app: postgresql
    role: replica
spec:
  selector:
    app: postgresql
    role: replica
  ports:
  - port: 5432
    targetPort: postgres
  type: ClusterIP
EOF

kubectl apply -f data-plane/postgresql/replica-statefulset.yaml
echo "✓ Deployed PostgreSQL replica StatefulSet"

# Step 5: Create init scripts ConfigMap
echo ""
echo "5. Creating PostgreSQL init scripts..."
mkdir -p data-plane/postgresql/init-scripts

cat > data-plane/postgresql/init-scripts/01-rls.sql <<'EOF'
-- Create SPIRE database and user (for SPIRE Server)
-- Using a fixed password since this is internal and SPIRE reads from secret
CREATE DATABASE spire;
CREATE USER spire_user WITH PASSWORD 'SpireDBPassword123!';
GRANT ALL PRIVILEGES ON DATABASE spire TO spire_user;
ALTER DATABASE spire OWNER TO spire_user;
GRANT ALL PRIVILEGES ON SCHEMA public TO spire_user;

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

-- Enable Row-Level Security
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE workflows ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY documents_tenant_isolation ON documents
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

CREATE POLICY workflows_namespace_isolation ON workflows
    USING (namespace = current_setting('app.current_namespace'));

-- Create indexes
CREATE INDEX idx_documents_tenant_id ON documents(tenant_id);
CREATE INDEX idx_workflows_namespace ON workflows(namespace);
CREATE INDEX idx_workflows_status ON workflows(status);
EOF

# Replace placeholder with actual password
sed -i "s/SPIRE_DB_PASSWORD/$SPIRE_SQL_PASSWORD/g" data-plane/postgresql/init-scripts/01-rls.sql

cat > data-plane/postgresql/init-scripts/02-tenants.sql <<'EOF'
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
kubectl create configmap postgres-init-scripts \
  --namespace=$NAMESPACE \
  --from-file=data-plane/postgresql/init-scripts/ \
  --dry-run=client -o yaml > /tmp/postgres-init-cm.yaml
kubectl apply -f /tmp/postgres-init-cm.yaml
echo "✓ Created PostgreSQL init scripts ConfigMap"

# Step 6: Deploy pgBouncer
echo ""
echo "6. Deploying pgBouncer for connection pooling..."
cat > data-plane/postgresql/pgbouncer.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgbouncer
  namespace: $NAMESPACE
  labels:
    app: pgbouncer
spec:
  replicas: 2
  selector:
    matchLabels:
      app: pgbouncer
  template:
    metadata:
      labels:
        app: pgbouncer
    spec:
      containers:
      - name: pgbouncer
        image: pgbouncer/pgbouncer:$PGBOUNCER_VERSION
        ports:
        - containerPort: 6432
          name: pgbouncer
        volumeMounts:
        - name: pgbouncer-config
          mountPath: /etc/pgbouncer
          readOnly: true
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "250m"
        livenessProbe:
          tcpSocket:
            port: 6432
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - psql -h 127.0.0.1 -p 6432 -U app_user -d app -c "SELECT 1;" | grep -q 1
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: pgbouncer-config
        secret:
          secretName: pgbouncer-auth
---
apiVersion: v1
kind: Service
metadata:
  name: pgbouncer
  namespace: $NAMESPACE
  labels:
    app: pgbouncer
spec:
  selector:
    app: pgbouncer
  ports:
  - port: 6432
    targetPort: pgbouncer
    name: pgbouncer
  type: ClusterIP
EOF

kubectl apply -f data-plane/postgresql/pgbouncer.yaml
echo "✓ Deployed pgBouncer"

# Step 7: Create backup cronjob
echo ""
echo "7. Creating backup cronjob..."
cat > data-plane/postgresql/backup-cronjob.yaml <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: default
spec:
  schedule: "0 2 * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          securityContext:
            runAsNonRoot: false
            seccompProfile:
              type: RuntimeDefault
          containers:
          - name: backup
            image: postgres:15
            securityContext:
              allowPrivilegeEscalation: false
              capabilities:
                drop:
                - ALL
              runAsNonRoot: false
              runAsUser: 999
              seccompProfile:
                type: RuntimeDefault
            command:
            - /bin/bash
            - -c
            - |
              set -e
              
              BACKUP_DIR="/backups/$(date +%Y%m%d_%H%M%S)"
              mkdir -p $BACKUP_DIR
              
              echo "Starting base backup..."
              pg_basebackup -h postgres-primary -U replicator -D $BACKUP_DIR/base -X stream -P
              
              echo "Archiving WAL files..."
              
              if [ -n "$AWS_S3_BUCKET" ]; then
                echo "Uploading backup to S3..."
                aws s3 cp --recursive $BACKUP_DIR s3://$AWS_S3_BUCKET/postgres/
              else
                echo "AWS_S3_BUCKET not configured, backup stored locally"
              fi
              
              find /backups -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true
              
              echo "Backup completed: $BACKUP_DIR"
            env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-replication
                  key: password
            - name: AWS_S3_BUCKET
              valueFrom:
                secretKeyRef:
                  name: s3-backup-secret
                  key: bucket
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: s3-backup-secret
                  key: access-key
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: s3-backup-secret
                  key: secret-key
            - name: AWS_DEFAULT_REGION
              value: "us-east-1"
            volumeMounts:
            - name: backup-volume
              mountPath: /backups
          volumes:
          - name: backup-volume
            emptyDir: {}
EOF

kubectl apply -f data-plane/postgresql/backup-cronjob.yaml
echo "✓ Created backup cronjob"

# Step 8: Create migration configuration
echo ""
echo "8. Creating migration configuration..."
mkdir -p data-plane/postgresql/migrations

cat > data-plane/postgresql/migrations/atlas-config.yaml <<'EOF'
# Atlas migration configuration
env:
  dev:
    url: postgres://app_user:${APP_PASSWORD}@pgbouncer:6432/app?sslmode=disable
    schemas:
      - public
    exclude:
      - atlas_schema_revisions
      
  prod:
    url: postgres://app_user:${APP_PASSWORD}@pgbouncer:6432/app?sslmode=disable
    schemas:
      - public
    exclude:
      - atlas_schema_revisions

# Migration directory
migrations:
  dir: file://migrations
  format: atlas
EOF

echo "✓ Created migration configuration"

# Step 9: Wait for deployments to be ready
echo ""
echo "9. Waiting for deployments to be ready..."
echo "Waiting for PostgreSQL primary..."
kubectl wait --for=condition=ready pod -l app=postgresql,role=primary --timeout=300s
echo "✓ PostgreSQL primary is ready"

echo "Waiting for PostgreSQL replica..."
kubectl wait --for=condition=ready pod -l app=postgresql,role=replica --timeout=300s
echo "✓ PostgreSQL replica is ready"

echo "Waiting for pgBouncer..."
kubectl wait --for=condition=ready pod -l app=pgbouncer --timeout=180s
echo "✓ pgBouncer is ready"

# Step 10: Display deployment summary
echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
echo "✓ Node labeling completed"
echo "✓ Secrets created"
echo "✓ PostgreSQL primary StatefulSet deployed"
echo "✓ PostgreSQL replica StatefulSet deployed"
echo "✓ Init scripts ConfigMap created"
echo "✓ pgBouncer deployed"
echo "✓ Backup cronjob created"
echo "✓ Migration configuration created"
echo ""
echo "Services:"
echo "- PostgreSQL primary: postgres-primary:5432"
echo "- PostgreSQL replica: postgres-replica:5432"
echo "- pgBouncer: pgbouncer:6432"
echo ""
echo "To validate the deployment, run:"
echo "./03-validation.sh"
echo ""
echo "To test RLS:"
echo "kubectl exec -it \$(kubectl get pod -l app=postgresql,role=primary -o name) -- psql -U app_user -d app -c \"SET app.current_tenant = '11111111-1111-1111-1111-111111111111'; SELECT * FROM documents;\""
echo "=========================================="