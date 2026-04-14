# RBAC Matrix - Foundation Service Accounts

## Overview
Least-privilege RBAC configuration for foundation service accounts across three planes:
- **Control-plane**: Kubernetes control components
- **Data-plane**: Application data processing
- **Observability-plane**: Monitoring, logging, and tracing

## Excluded Namespaces
The following namespaces are excluded from RBAC policies:
- `kube-system` (Kubernetes system components)
- `kyverno` (Policy engine namespace)

## Service Account Permissions Matrix

### Control-plane Service Accounts

| Service Account | Namespace | Role Type | Permissions | Purpose |
|----------------|-----------|-----------|-------------|---------|
| `temporal-server` | control-plane | Role | `pods/services/endpoints/configmaps: get,list,watch`<br>`deployments/statefulsets: get,list,watch` | Workflow orchestration |
| `kyverno` | control-plane | ClusterRole | `namespaces/pods/services: get,list,watch`<br>`clusterpolicies/policies: get,list,watch,create,update,delete` | Policy management |
| `spire-server` | control-plane | Role | `pods/serviceaccounts: get,list,watch,create,update`<br>`spiffeids: get,list,watch,create,update,delete` | Identity management |

### Data-plane Service Accounts

| Service Account | Namespace | Role Type | Permissions | Purpose |
|----------------|-----------|-----------|-------------|---------|
| `postgres` | data-plane | Role | `pods/services/endpoints/secrets/configmaps: get,list,watch`<br>`statefulsets: get,list,watch` | Database operations |
| `nats` | data-plane | Role | `pods/services/endpoints: get,list,watch`<br>`statefulsets: get,list,watch` | Messaging operations |
| `minio` | data-plane | Role | `pods/services/persistentvolumeclaims/secrets: get,list,watch`<br>`statefulsets: get,list,watch` | Storage operations |

### Observability-plane Service Accounts

| Service Account | Namespace | Role Type | Permissions | Purpose |
|----------------|-----------|-----------|-------------|---------|
| `vmagent` | observability-plane | Role | `pods/services/endpoints/nodes: get,list,watch` | Metrics collection |
| `fluent-bit` | observability-plane | ClusterRole | `namespaces/pods: get,list,watch`<br>`/metrics: get` | Log collection |
| `loki` | observability-plane | Role | `pods/services/persistentvolumeclaims/configmaps: get,list,watch`<br>`statefulsets: get,list,watch` | Log storage |

## Validation Commands

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

## Deployment Order
1. Ensure foundation namespaces exist (`control-plane`, `data-plane`, `observability-plane`)
2. Apply `foundation-sas.yaml` to create service accounts
3. Apply `foundation-roles.yaml` to create RBAC roles and bindings
4. Validate permissions using validation commands

## Security Considerations
- All roles follow principle of least privilege
- No wildcard permissions (`*`) granted
- ClusterRoles are used only when cross-namespace access is required
- Service accounts are isolated to their respective planes
- Labels applied for easy identification and management