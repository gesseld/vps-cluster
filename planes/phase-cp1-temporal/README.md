# Task CP-1: Temporal Server Deployment (HA-Enhanced)

## Objective
Deploy Temporal Server with active-active HA and increased resource allocation.

## Architecture
- **Temporal Server**: Monolith mode (frontend+history+matching in one container)
- **Replicas**: 2 with pod anti-affinity for HA
- **Resources**: 750MB request / 1GB limit per replica
- **Persistence**: PostgreSQL in Data Plane (`temporal` and `temporal_visibility` databases)
- **Security**: mTLS on port 7233 (SPIFFE certificates optional)
- **Retention**: 3 days completed workflows, 7 days visibility records
- **Priority**: `foundation-critical` PriorityClass
- **Topology**: Spread across nodes (maxSkew: 1)
- **Availability**: PodDisruptionBudget with minAvailable: 1

## Prerequisites

### Environment Variables
Create `.env` file in project root:
```bash
# Required
NAMESPACE=control-plane
TEMPORAL_VERSION=1.25.0
STORAGE_CLASS=hcloud-volumes
PRIORITY_CLASS=foundation-critical

# PostgreSQL credentials (referenced from Data Plane)
# These should be available in the temporal-postgres-creds secret
```

### System Requirements
1. **Kubernetes Cluster**:
   - At least 2 nodes for HA deployment
   - kubectl access configured
   - Storage class available

2. **Data Plane Dependencies**:
   - PostgreSQL deployed with:
     - `temporal` database
     - `temporal_visibility` database
   - Secret `temporal-postgres-creds` in data-plane namespace

3. **Optional**:
   - SPIRE server for mTLS
   - tctl for cluster health checks

## Deployment Steps

### 1. Pre-deployment Check
```bash
./01-pre-deployment-check.sh
```
Validates cluster access, storage classes, existing resources, and configuration.

### 2. Deployment
```bash
./02-deployment.sh
```
Deploys all components:
- ServiceAccount and RBAC
- ConfigMap with configuration
- Headless and frontend Services
- NetworkPolicy (ingress from execution-plane)
- PodDisruptionBudget (minAvailable: 1)
- StatefulSet with 2 replicas (HA)

### 3. Validation
```bash
./03-validation.sh
```
Validates the deployment:
- Resource status and configuration
- Connectivity and health checks
- HA configuration verification
- Optional tctl health check

## Configuration

### Resource Allocation
- **Memory**: 750Mi request / 1Gi limit per pod
- **CPU**: 500m request / 1000m limit per pod
- **Storage**: 10Gi PVC per pod (optional)

### HA Configuration
- **Replicas**: 2
- **Anti-affinity**: `requiredDuringSchedulingIgnoredDuringExecution` on hostname
- **Topology Spread**: maxSkew: 1 across nodes
- **PDB**: minAvailable: 1

### Network Security
- **Ingress**: Only from execution-plane namespace (ports 7233-7235)
- **Internal**: Pod-to-pod communication (ports 7236-7238)
- **Metrics**: Access from observability-plane (port 9090)

### Retention Policies
- **Workflows**: 3 days (72 hours)
- **Visibility**: 7 days (168 hours)
- **Archival**: Disabled

## Validation Commands

### Quick Health Check
```bash
# Check deployment status
kubectl get statefulset temporal -n control-plane
kubectl get pods -n control-plane -l app=temporal

# Check logs
kubectl logs -n control-plane -l app=temporal --tail=20

# Verify services
kubectl get svc temporal temporal-headless -n control-plane
```

### Connectivity Test
```bash
# Test frontend access
kubectl run -n control-plane --rm -i --restart=Never test-connectivity \
  --image=alpine:latest -- nc -zv temporal.control-plane.svc.cluster.local 7233

# Test metrics endpoint
curl http://temporal.control-plane.svc.cluster.local:9090/metrics | head -5
```

### tctl Health Check (if installed)
```bash
# Port forward and check health
kubectl port-forward -n control-plane svc/temporal 7233:7233 &
tctl --address localhost:7233 cluster health
```

## Components

### 1. Temporal Server StatefulSet (`control-plane/temporal/temporal-server.yaml`)
- 2 replicas with anti-affinity
- Resource limits: 750Mi/1Gi
- All Temporal services in monolith mode
- Health checks on metrics port
- Security context with non-root user

### 2. Services (`control-plane/temporal/service.yaml`)
- **temporal-headless**: Headless service for StatefulSet
- **temporal**: Load-balanced frontend service (port 7233)

### 3. NetworkPolicy (`control-plane/temporal/networkpolicy.yaml`)
- Ingress from execution-plane only
- Internal pod communication
- Metrics access from observability-plane

### 4. PodDisruptionBudget (`control-plane/temporal/pdb.yaml`)
- `minAvailable: 1` for HA

### 5. Configuration (`control-plane/temporal/config/`)
- **config.yaml**: Main Temporal configuration
- **dynamicconfig.yaml**: Retention and HA settings

### 6. RBAC (`control-plane/temporal/rbac.yaml`)
- ServiceAccount for Temporal server
- Role for configmap/secret access

## Troubleshooting

### Pods Not Starting
1. Check PostgreSQL connectivity:
   ```bash
   kubectl get secret temporal-postgres-creds -n data-plane
   kubectl describe pod -n control-plane -l app=temporal
   ```

2. Check resource limits:
   ```bash
   kubectl describe node | grep -A5 -B5 "temporal"
   ```

3. Check storage class:
   ```bash
   kubectl get storageclass
   kubectl get pvc -n control-plane
   ```

### Connection Issues
1. Verify NetworkPolicy:
   ```bash
   kubectl get networkpolicy temporal-ingress -n control-plane -o yaml
   ```

2. Test connectivity from execution-plane:
   ```bash
   kubectl run -n execution-plane --rm -i --restart=Never test \
     --image=alpine:latest -- nc -zv temporal.control-plane.svc.cluster.local 7233
   ```

### High Memory Usage
1. Check current usage:
   ```bash
   kubectl top pods -n control-plane -l app=temporal
   ```

2. Adjust resource limits in StatefulSet if needed

### Metrics Not Available
1. Check Prometheus annotations:
   ```bash
   kubectl describe pod -n control-plane -l app=temporal | grep -i prometheus
   ```

2. Test metrics endpoint:
   ```bash
   kubectl exec -n control-plane -l app=temporal -- curl -s localhost:9090/metrics | head -5
   ```

## Cleanup
```bash
# Delete all Temporal resources
kubectl delete -f control-plane/temporal/
kubectl delete configmap temporal-config -n control-plane
kubectl delete serviceaccount temporal-server -n control-plane
```

## Success Criteria

| Criterion | Validation Method |
|-----------|-------------------|
| **HA Deployment** | 2 pods running on different nodes |
| **Resource Limits** | 750Mi/1Gi per pod |
| **Connectivity** | Frontend accessible from execution-plane |
| **Health Checks** | /health endpoint returns 200 |
| **Retention** | Config shows 72h workflow, 168h visibility |
| **Network Isolation** | Only execution-plane can access port 7233 |
| **Availability** | PDB ensures minAvailable: 1 |
| **Priority** | Pods scheduled with foundation-critical class |

## Deliverables Checklist
- [x] `control-plane/temporal/temporal-server.yaml` (StatefulSet with 2 replicas)
- [x] `control-plane/temporal/pdb.yaml` (PodDisruptionBudget)
- [x] `control-plane/temporal/config/dynamicconfig.yaml` (retention policies)
- [x] `control-plane/temporal/networkpolicy.yaml` (ingress only from execution-plane)
- [x] `control-plane/temporal/service.yaml` (headless + load-balanced frontend)
- [x] `control-plane/temporal/rbac.yaml` (ServiceAccount and RBAC)
- [x] `control-plane/temporal/config/config.yaml` (main configuration)
- [x] Pre-deployment script (`01-pre-deployment-check.sh`)
- [x] Deployment script (`02-deployment.sh`)
- [x] Validation script (`03-validation.sh`)

## Next Steps
1. **Immediate**: Run validation suite to verify deployment
2. **Integration**: Configure execution-plane workflows to use Temporal
3. **Monitoring**: Set up alerts for Temporal metrics
4. **Backup**: Implement PostgreSQL backup strategy
5. **Scaling**: Monitor performance and adjust replicas as needed