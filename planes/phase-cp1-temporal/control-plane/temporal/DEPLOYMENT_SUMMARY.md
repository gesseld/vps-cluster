# Temporal Server Deployment (HA-Enhanced) - CP-1

## Objective
Deploy Temporal Server with active-active HA and increased resource allocation.

## Deliverables Completed

### 1. `control-plane/temporal/temporal-server.yaml`
- StatefulSet with 2 replicas
- Resource spec: 750MB request / 1GB limit
- PodAntiAffinity: `requiredDuringSchedulingIgnoredDuringExecution`
- Topology spread: `maxSkew: 1`, `whenUnsatisfiable: DoNotSchedule`
- PriorityClass: `foundation-critical`
- mTLS enabled on port 7233 using SPIFFE certificates
- Monolith mode (frontend+history+matching in one container)
- Health checks with liveness and readiness probes

### 2. `control-plane/temporal/pdb.yaml`
- PodDisruptionBudget with `minAvailable: 1`

### 3. `control-plane/temporal/config/dynamicconfig.yaml`
- Retention: 3 days completed workflows (72h)
- Retention: 7 days visibility records (168h)
- mTLS configuration for frontend
- HA cluster settings

### 4. `control-plane/temporal/networkpolicy.yaml`
- Ingress only from execution-plane namespace
- Ports: 7233 (frontend), 7234 (history), 7235 (matching)
- Internal communication ports: 7236-7238
- Metrics port 9090 for observability-plane

### 5. `control-plane/temporal/service.yaml`
- Headless service: `temporal-headless` for StatefulSet
- Load-balanced service: `temporal` for frontend access
- All required ports exposed

### 6. Secret Templates
- `temporal-postgres-creds.yaml`: PostgreSQL credentials for Data Plane
- `temporal-tls-certs.yaml`: SPIFFE certificates for mTLS

## Configuration Details

### High Availability
- **Replicas**: 2
- **Anti-affinity**: Pods scheduled on different nodes
- **Topology spread**: Even distribution across nodes
- **PDB**: Minimum 1 pod always available
- **Resource limits**: 1GB memory to prevent OOM during bursts

### Security
- **mTLS**: Enabled on port 7233
- **SPIFFE certificates**: Mounted from secret
- **Network policy**: Restricted ingress from execution-plane only
- **Security context**: Non-root user, read-only root filesystem

### Database Configuration
- **PostgreSQL**: Connection to Data Plane
- **Database**: `temporal_visibility`
- **Connection pooling**: Configured in dynamicconfig

### Resource Allocation
- **Memory**: 750Mi request, 1Gi limit
- **CPU**: 500m request, 1000m limit
- **Storage**: 10Gi PVC template (hcloud-volumes)

## Validation Commands

```bash
# Apply all configurations
kubectl apply -f planes/phase-cp1-temporal/control-plane/temporal/ -n control-plane

# Check pod status
kubectl get pods -n control-plane -l app=temporal

# Verify 2/2 pods running
kubectl get pods -n control-plane -l app=temporal -o jsonpath='{.items[*].status.phase}' | tr ' ' '\n' | grep -c Running

# Check services
kubectl get svc -n control-plane -l app=temporal

# Test health endpoint
kubectl exec -n control-plane -it $(kubectl get pod -n control-plane -l app=temporal -o jsonpath='{.items[0].metadata.name}') -- curl http://localhost:9090/health
```

## Notes
1. PostgreSQL schemas need to be created in Data Plane (`temporal_visibility` DB)
2. SPIFFE certificates need to be generated and placed in the `temporal-tls-certs` secret
3. PostgreSQL credentials should be updated in `temporal-postgres-creds` secret
4. The `hcloud-volumes` storage class should be available in the cluster

## Files Created/Updated
- ✅ `temporal-server.yaml` (updated with mTLS)
- ✅ `pdb.yaml` (verified)
- ✅ `config/dynamicconfig.yaml` (updated with mTLS config)
- ✅ `networkpolicy.yaml` (verified)
- ✅ `service.yaml` (verified)
- ✅ `temporal-postgres-creds.yaml` (new)
- ✅ `temporal-tls-certs.yaml` (new)
- ✅ `validate-deployment.sh` (new)
- ✅ `DEPLOYMENT_SUMMARY.md` (this file)