# PostgreSQL Phase DP-1: Tenant-Isolated Database with RLS, Pooling & Read Replica

## Objective
Deploy a PostgreSQL 15 database with Row-Level Security (RLS), connection pooling via pgBouncer, async read replica, and automated backups for a multi-tenant application.

## Architecture
- **PostgreSQL Primary**: StatefulSet with 50GB PVC, RLS enabled, `volumeBindingMode: WaitForFirstConsumer`
- **PostgreSQL Replica**: Async read replica on separate node, 50GB PVC
- **pgBouncer**: Connection pooling with transaction mode, `max_client_conn=500`, `default_pool_size=20`
- **RLS Policies**: Tenant isolation for documents, namespace isolation for workflows
- **Backups**: Daily base backup + WAL archiving to MinIO
- **Topology**: Anti-affinity rules to separate primary/replica and avoid colocation with MinIO

## Prerequisites
1. Kubernetes cluster with at least 2 nodes
2. Storage class `hcloud-volumes` (or configure `STORAGE_CLASS` in scripts)
3. MinIO deployed for backups (optional but recommended)
4. `kubectl` configured with cluster access

## Deployment Steps

### 1. Pre-deployment Check
```bash
./01-pre-deployment-check.sh
```
Checks cluster access, node labels, storage classes, and existing resources.

### 2. Deployment
```bash
./02-deployment.sh
```
Deploys all components:
- Labels nodes with `node-role=storage-heavy`
- Creates PostgreSQL secrets
- Deploys PostgreSQL primary and replica StatefulSets
- Creates RLS policies and sample data
- Deploys pgBouncer with connection pooling
- Sets up backup cronjob
- Creates migration configuration

### 3. Validation
```bash
./03-validation.sh
```
Validates the deployment:
- Pod and service status
- PostgreSQL connections
- RLS functionality
- Replication status
- pgcrypto extension
- Topology spread

## Configuration

### Environment Variables
Create `.env` file in project root or set variables:
```bash
export NAMESPACE=default
export POSTGRES_VERSION=15
export STORAGE_CLASS=hcloud-volumes
export STORAGE_SIZE=50Gi
export PGBOUNCER_VERSION=1.21
```

### Secrets Created
- `postgres-superuser`: PostgreSQL superuser credentials
- `postgres-app-user`: Application user credentials
- `postgres-replication`: Replication user credentials
- `pgbouncer-auth`: pgBouncer configuration and auth

## Components

### 1. PostgreSQL Primary (`data-plane/postgresql/primary-statefulset.yaml`)
- PostgreSQL 15 with `pgcrypto` extension
- 50GB PVC with `WaitForFirstConsumer`
- RLS policies for tenant isolation
- Resource limits: 4GB RAM, 2 CPU
- Anti-affinity with MinIO pods

### 2. PostgreSQL Replica (`data-plane/postgresql/replica-statefulset.yaml`)
- Async streaming replication from primary
- On separate node (anti-affinity with primary)
- Automatic base backup on startup
- Read-only mode

### 3. pgBouncer (`data-plane/postgresql/pgbouncer.yaml`)
- Transaction pooling mode
- `max_client_conn=500`, `default_pool_size=20`
- 2 replicas for high availability
- Read/write routing via database definitions

### 4. RLS Policies (`data-plane/postgresql/init-scripts/`)
- **01-rls.sql**: Creates tables and enables RLS
  - `documents`: Tenant isolation via `app.current_tenant` GUC
  - `workflows`: Namespace isolation via `app.current_namespace` GUC
- **02-tenants.sql**: Sample data for testing

### 5. Backups (`data-plane/postgresql/backup-cronjob.yaml`)
- Daily backups at 2 AM
- Base backup + WAL archiving
- Upload to MinIO `backups/postgres` bucket
- 7-day retention

### 6. Migrations (`data-plane/postgresql/migrations/atlas-config.yaml`)
- Atlas configuration for schema migrations
- Supports dev/prod environments
- Integration with pgBouncer

## Validation Tests

### RLS Test
```bash
# Test tenant isolation
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- \
  psql -U app_user -d app -c "SET app.current_tenant = '11111111-1111-1111-1111-111111111111'; SELECT * FROM documents;"
# Should return only tenant A documents
```

### Replication Test
```bash
# Check replication status
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- \
  psql -U postgres -d app -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
```

### Connection Pool Test
```bash
# Test pgBouncer connection
kubectl exec -it $(kubectl get pod -l app=pgbouncer -o name | head -1) -- \
  psql -h 127.0.0.1 -p 6432 -U app_user -d app -c "SELECT 1;"
```

## Troubleshooting

### Pods Not Starting
1. Check PVC binding: `kubectl get pvc`
2. Check node labels: `kubectl get nodes --show-labels`
3. Check resource availability: `kubectl describe nodes`

### Replication Issues
1. Check primary logs: `kubectl logs -l app=postgresql,role=primary`
2. Check replica logs: `kubectl logs -l app=postgresql,role=replica`
3. Verify secrets: `kubectl get secrets`

### Connection Issues
1. Check pgBouncer logs: `kubectl logs -l app=pgbouncer`
2. Test direct connections to primary/replica
3. Verify network policies

## Cleanup
```bash
# Delete all resources
kubectl delete -f data-plane/postgresql/ --recursive
kubectl delete secret postgres-superuser postgres-app-user postgres-replication pgbouncer-auth
kubectl delete configmap postgres-init-scripts
kubectl label nodes -l node-role=storage-heavy node-role-
```

## Deliverables Checklist
- [x] `data-plane/postgresql/primary-statefulset.yaml`
- [x] `data-plane/postgresql/replica-statefulset.yaml`
- [x] `data-plane/postgresql/pgbouncer.yaml`
- [x] `data-plane/postgresql/init-scripts/01-rls.sql`
- [x] `data-plane/postgresql/init-scripts/02-tenants.sql`
- [x] `data-plane/postgresql/migrations/atlas-config.yaml`
- [x] `data-plane/postgresql/backup-cronjob.yaml`
- [x] Secret `postgres-superuser`, `postgres-app-user`
- [x] Pre-deployment script (`01-pre-deployment-check.sh`)
- [x] Deployment script (`02-deployment.sh`)
- [x] Validation script (`03-validation.sh`)