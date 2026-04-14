# Phase DP-5: Temporal HA Data Plane Installation

## Overview
Deploy Temporal Server with High Availability configuration in the Data Plane, optimized for Hetzner bare metal infrastructure (3-node k3s, 10 vCPU/16GB RAM, €28.70/month budget).

## Architectural Context
- **Corrected Placement**: Temporal belongs in Data Plane (corrected from original Control Plane specification)
- **Dependencies**: Depends on PostgreSQL (DP-1) for persistence
- **Sequence**: Data Plane phase 5, after PostgreSQL, NATS, S3, and Redis

## Prerequisites

### Already Deployed Phases
1. **Phase 0**: Budget scaffolding (PriorityClasses, ResourceQuotas)
2. **Phase DP-1**: PostgreSQL 15 with HA configuration
3. **Phase DP-2**: NATS JetStream cluster
4. **Phase DP-3**: Hetzner S3 storage
5. **Phase DP-4**: Redis cluster

### Cluster Requirements
- **k3s**: Version 1.29+ with Cilium CNI
- **Nodes**: Minimum 3 nodes for HA
- **Storage**: `hcloud-volumes` storage class available
- **Networking**: Traefik ingress controller (already installed with k3s)

## Components Deployed

### 1. PostgreSQL 15 (Bitnami Helm)
- Primary + synchronous replica configuration
- HA-tuned for Temporal's write-heavy workload
- 10Gi PVC per instance

### 2. PgBouncer
- Connection pooling service (critical for Temporal)
- Transaction pooling mode
- 2 replicas with session persistence

### 3. Temporal Server (Helm)
- Version 1.25.0
- Components: Frontend (2), History (2), Matching (1), Worker (1)
- PostgreSQL backend with PgBouncer
- Separate visibility database

## Resource Allocation

### Total Budget: ≤3.5 vCPU / 4.5GB RAM
| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| PostgreSQL | 500m | 1000m | 512Mi | 1024Mi |
| PgBouncer | 100m | 200m | 128Mi | 256Mi |
| Temporal Frontend | 250m | 500m | 512Mi | 768Mi |
| Temporal History | 500m | 1000m | 768Mi | 1024Mi |
| Temporal Matching | 250m | 500m | 512Mi | 768Mi |
| Temporal Worker | 250m | 500m | 512Mi | 768Mi |
| **Total** | **1.85 vCPU** | **3.7 vCPU** | **2.94GB** | **4.61GB** |

**Remaining Capacity**: 6.5 vCPU / 11.5GB for Document Intelligence services

## Manual Configuration Required

### Before Execution
1. **Verify VPS IP Address**:
   ```bash
   # The deployment will use VPS IP: 49.12.37.154
   # To use a different IP, set CLUSTER_DOMAIN environment variable:
   export CLUSTER_DOMAIN="your-vps-ip-address"
   ```

2. **Change Default Passwords**:
   ```bash
   # Generate secure passwords and update:
   nano manifests/postgres-values-hetzner.yaml
   nano manifests/temporal-ha-hetzner-values.yaml
   ```

## Deployment Process

### Three-Step Execution
```bash
cd scripts/

# Step 1: Verify prerequisites
./01-pre-deployment-check.sh

# Step 2: Deploy all components
./02-deployment.sh

# Step 3: Validate installation
./03-validation.sh
```

### Script Details

#### 1. Pre-deployment Check (`01-pre-deployment-check.sh`)
- Verifies k3s cluster health and version
- Checks resource availability (CPU, memory, storage)
- Validates required CLIs are installed (helm, kubectl)
- Tests DNS resolution and network connectivity
- Confirms PostgreSQL dependency is ready
- Validates Traefik ingress controller

#### 2. Deployment (`02-deployment.sh`)
- Creates necessary namespaces and secrets
- Deploys PostgreSQL 15 with HA configuration
- Deploys PgBouncer for connection pooling
- Deploys Temporal Server with optimized configuration
- Configures ingress for gRPC and Web UI access
- Waits for all pods to be ready

#### 3. Validation (`03-validation.sh`)
- Tests pod status and readiness
- Verifies service endpoints
- Tests PostgreSQL connectivity
- Tests Temporal gRPC API
- Tests Temporal Web UI
- Creates comprehensive validation report

## Access Points

### Services
- **Temporal gRPC**: `temporal-frontend.data-plane.svc.cluster.local:7233`
- **Temporal Web UI**: `temporal-web.data-plane.svc.cluster.local:8080`
- **PostgreSQL**: `postgresql.data-plane.svc.cluster.local:5432`
- **PgBouncer**: `pgbouncer.data-plane.svc.cluster.local:6432`

### Ingress (External Access)
- **gRPC API**: `http://49.12.37.154/temporal`
- **Web UI**: `http://49.12.37.154/temporal-ui`

## Verification

### Quick Health Check
```bash
# Check all pods
kubectl get pods -n data-plane -l app.kubernetes.io/name=temporal

# Check services
kubectl get svc -n data-plane -l app.kubernetes.io/name=temporal

# Test gRPC endpoint
kubectl run -n data-plane --rm -i --tty test-temporal --image=curlimages/curl --restart=Never -- curl -v http://temporal-frontend:7233
```

### Comprehensive Validation
Run the full validation script:
```bash
./03-validation.sh
```

## Troubleshooting

### Common Issues

1. **PostgreSQL Connection Failures**:
   ```bash
   # Check PostgreSQL logs
   kubectl logs -n data-plane deployment/postgresql-postgresql-0
   
   # Test PgBouncer connectivity
   kubectl exec -n data-plane deployment/pgbouncer -- pg_isready -h localhost -p 6432
   ```

2. **Temporal Pods Not Ready**:
   ```bash
   # Check pod events
   kubectl describe pod -n data-plane -l app.kubernetes.io/name=temporal
   
   # Check logs
   kubectl logs -n data-plane deployment/temporal-frontend
   ```

3. **Ingress Not Working**:
   ```bash
   # Check Traefik logs
   kubectl logs -n kube-system deployment/traefik
   
   # Check ingress resource
   kubectl get ingress -n data-plane
   ```

### Logs Location
All execution logs are saved to `../logs/` directory with timestamps.

## Maintenance

### Monitoring
- **Metrics**: Prometheus endpoints on port 9090
- **Logs**: Container logs via kubectl or log aggregation
- **Health**: Regular validation script execution

### Backup
- **PostgreSQL**: Scheduled backups via pg_dump or volume snapshots
- **Temporal**: Export workflows via tctl or API

### Updates
1. Check for new Temporal Helm chart versions
2. Test in non-production environment first
3. Follow rolling update strategy with proper backups

## Security Notes

### Credentials
- All passwords are generated as Kubernetes Secrets
- Never commit actual passwords to version control
- Rotate passwords periodically in production

### Network Security
- Services are isolated within the data-plane namespace
- Ingress requires TLS termination
- Internal communication uses service mesh or network policies

### Compliance
- Non-root user execution for all containers
- Read-only root filesystem where possible
- Resource limits prevent DoS attacks

## References

### Documentation
- [Temporal Documentation](https://docs.temporal.io/)
- [PostgreSQL Tuning Guide](https://www.postgresql.org/docs/current/runtime-config.html)
- [PgBouncer Documentation](https://www.pgbouncer.org/)

### Related Phases
- **DP-1**: PostgreSQL deployment
- **DP-2**: NATS deployment  
- **DP-3**: S3 storage configuration
- **DP-4**: Redis deployment

### Architecture
- [Document Intelligence Platform v4.0.4](docs/eng-design/Doc%20con%20obv%20planes.txt)
- Corrected Temporal placement in Data Plane (line 470)