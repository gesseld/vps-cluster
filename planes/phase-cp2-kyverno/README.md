# Kyverno Policy Engine (CP-2)

## Objective
Replace OPA with Kyverno for lower overhead and native Kubernetes UX, with API protection.

## Architecture
- **Kyverno v1.11+** with 2 replicas for HA (lightweight)
- **ClusterPolicy** resources for validation and mutation
- **Rate limiting** to prevent ArgoCD sync storms
- **SPIFFE sidecar** automatic injection
- **Metrics export** to vmagent

## Policies Implemented

### 1. Label Enforcement
- `require-plane-labels`: Enforce `plane ∈ {control,data,observability,execution,ai}`
- `require-tenant-labels`: Enforce `tenant` label for RLS

### 2. Resource Constraints
- `require-resource-limits`: Block pods without requests/limits
- `enforce-resource-ratios`: Limits should not exceed 2x requests

### 3. Security Baseline
- `block-privileged-exec`: Deny privileged containers in execution/ai planes
- `enforce-readonly-root-fs`: Immutable container filesystems
- `block-host-path`: Prevent host filesystem access
- `require-non-root-user`: Containers must run as non-root

### 4. Rate Limiting
- `rate-limit-admission`: Limit pod creation bursts (5 pods/minute/namespace)
- `tenant-rate-limit`: Limit resource creation per tenant
- `argocd-sync-protection`: Special protection for ArgoCD namespaces

### 5. Mutation
- `inject-spiffe-sidecar`: Automatically inject SPIFFE sidecars

## Deliverables

### Scripts
1. `pre-deployment.sh` - Checks prerequisites
2. `deploy-kyverno.sh` - Deploys Kyverno and policies
3. `validate-kyverno.sh` - Validates all deliverables

### Configuration Files
- `control-plane/kyverno/kustomization.yaml` - Kustomize configuration
- `control-plane/kyverno/patch-ha.yaml` - HA configuration patch
- `control-plane/kyverno/policies/require-labels.yaml` - Label policies
- `control-plane/kyverno/policies/resource-constraints.yaml` - Resource policies
- `control-plane/kyverno/policies/security-baseline.yaml` - Security policies
- `control-plane/kyverno/policies/rate-limit-admission.yaml` - Rate limiting
- `control-plane/kyverno/metrics-service.yaml` - Metrics configuration

## Deployment

### Prerequisites
- Kubernetes cluster (v1.19+)
- kubectl configured
- Sufficient resources (2 nodes minimum for HA)

### Quick Start
```bash
# 1. Run pre-deployment checks
./pre-deployment.sh

# 2. Deploy Kyverno
./deploy-kyverno.sh

# 3. Validate deployment
./validate-kyverno.sh
```

### Manual Deployment
```bash
# Apply kustomization
kubectl apply -k control-plane/kyverno/

# Verify deployment
kubectl get pods -n kyverno
kubectl get clusterpolicies
```

## Validation Tests

### Policy Enforcement Test
```bash
# Should be rejected with policy message
kubectl run nginx --image=nginx --namespace=default
```

### Rate Limiting Test
```bash
# Create test namespace
kubectl create namespace kyverno-test

# Try to create multiple pods quickly (some will be rate limited)
for i in {1..10}; do
  kubectl run test-$i --image=busybox --namespace=kyverno-test -- sleep 3600
done
```

### Valid Pod Example
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: valid-pod
  namespace: default
  labels:
    plane: control
    tenant: example-tenant
spec:
  containers:
  - name: nginx
    image: nginx:latest
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
    securityContext:
      readOnlyRootFilesystem: true
      runAsNonRoot: true
```

## Monitoring

### Metrics
Kyverno exposes metrics on port 8000:
- Policy evaluation metrics
- Admission latency
- Resource validation counts
- Rate limiting statistics

### Access Metrics
```bash
# Port forward to access metrics
kubectl port-forward -n kyverno svc/kyverno-svc 8000:8000

# View metrics
curl http://localhost:8000/metrics
```

### Integration with vmagent
Metrics are automatically scraped by ServiceMonitor if Prometheus Stack is installed.

## Namespace Exclusions
The following namespaces are excluded from policies:
- `kube-system`
- `kyverno`
- `spire` (for SPIFFE mutation)

## Benefits Over OPA

1. **Native Kubernetes UX** - Uses standard Kubernetes resources (ClusterPolicy)
2. **Lower Overhead** - Single binary vs OPA+Gatekeeper
3. **Built-in Mutations** - No need for external mutation webhooks
4. **Context-Aware Policies** - Can query Kubernetes API during validation
5. **Better Performance** - Optimized for Kubernetes admission control

## Troubleshooting

### Common Issues

1. **Policies not enforcing**
   ```bash
   kubectl get clusterpolicies
   kubectl describe clusterpolicy <policy-name>
   ```

2. **Webhook failures**
   ```bash
   kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations
   kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno
   ```

3. **Rate limiting too aggressive**
   - Adjust limits in `rate-limit-admission.yaml`
   - Modify `recentPods` time window or count

### Logs
```bash
# View Kyverno logs
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno

# View policy violation events
kubectl get events --field-selector involvedObject.kind=ClusterPolicy
```

## Security Considerations

1. **Policy Scope**: Policies apply cluster-wide (use namespace exclusions)
2. **Mutation Order**: SPIFFE injection happens before other mutations
3. **Performance Impact**: Rate limiting prevents admission controller overload
4. **Audit Mode**: Some policies start in audit mode (`validationFailureAction: Audit`)

## References
- [Kyverno Documentation](https://kyverno.io/docs/)
- [Kyverno Policies](https://github.com/kyverno/policies)
- [Kubernetes Admission Control](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)