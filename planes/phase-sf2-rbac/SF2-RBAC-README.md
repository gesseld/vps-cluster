# SF-2: ServiceAccounts + RBAC Baseline

## Objective
Create least-privilege service accounts before workloads reference them across three planes:
- **Control-plane**: `temporal-server`, `kyverno`, `spire-server`
- **Data-plane**: `postgres`, `nats`, `minio`
- **Observability-plane**: `vmagent`, `fluent-bit`, `loki`

## Deliverables Created
1. `shared/rbac/foundation-sas.yaml` - 9 service accounts across 3 planes
2. `shared/rbac/foundation-roles.yaml` - 10 RBAC roles/rolebindings + 2 cluster roles/bindings
3. `shared/rbac-matrix.md` - RBAC permissions documentation
4. `planes/sf2-rbac-precheck.sh` - Pre-deployment validation script
5. `planes/sf2-rbac-deploy.sh` - Deployment script
6. `planes/sf2-rbac-validate.sh` - Post-deployment validation script

## Key Features
- **Least Privilege**: Each service account has minimal required permissions
- **Plane Isolation**: Service accounts are confined to their respective planes
- **Namespace Exclusions**: `kube-system` and `kyverno` namespaces excluded from policies
- **Validation Ready**: Scripts for pre-check, deployment, and validation
- **Documentation**: Complete RBAC matrix with permission details

## Deployment Workflow

### 1. Pre-deployment Check
```bash
./planes/sf2-rbac-precheck.sh
```
Checks prerequisites:
- Kubernetes cluster connectivity
- Foundation namespaces existence
- Existing service account conflicts
- RBAC API availability
- User permissions

### 2. Deployment
```bash
./planes/sf2-rbac-deploy.sh
```
Deploys:
- 9 service accounts across 3 planes
- 10 RBAC roles and rolebindings
- 2 cluster roles and clusterrolebindings
- Namespace exclusion labels

### 3. Validation
```bash
./planes/sf2-rbac-validate.sh
```
Validates:
- Service account existence
- RBAC binding correctness
- Permission verification with `kubectl auth can-i`
- Namespace exclusion configuration

## Manual Validation Commands
```bash
# Check temporal-server permissions
kubectl auth can-i --list --as=system:serviceaccount:control-plane:temporal-server

# Check kyverno permissions
kubectl auth can-i --list --as=system:serviceaccount:control-plane:kyverno

# Check postgres permissions
kubectl auth can-i --list --as=system:serviceaccount:data-plane:postgres

# Check vmagent permissions
kubectl auth can-i --list --as=system:serviceaccount:observability-plane:vmagent
```

## RBAC Design Principles
1. **Minimal Permissions**: No wildcard (`*`) permissions granted
2. **Namespace Scoping**: Roles are namespace-scoped where possible
3. **Cluster-wide Only When Necessary**: ClusterRoles used only for cross-namespace access
4. **Label-based Management**: All resources labeled with `rbac-tier: foundation`
5. **Exclusion Strategy**: Critical system namespaces excluded from policies

## Service Account Details

### Control-plane
- `temporal-server`: Workflow orchestration (namespace-scoped pods/services access)
- `kyverno`: Policy management (cluster-wide namespace/policy access)
- `spire-server`: Identity management (pod/serviceaccount management)

### Data-plane
- `postgres`: Database operations (statefulset and secret access)
- `nats`: Messaging operations (pod and service access)
- `minio`: Storage operations (PVC and secret access)

### Observability-plane
- `vmagent`: Metrics collection (pod/service/node access)
- `fluent-bit`: Log collection (cluster-wide pod access + metrics)
- `loki`: Log storage (PVC and configmap access)

## Security Notes
- All service accounts follow principle of least privilege
- No access to `kube-system` or `kyverno` namespaces
- Labels applied for easy identification: `plane`, `component`, `rbac-tier`
- Ready for workload deployment with secure baseline RBAC