# BS-5: NetworkPolicy CRD + Default-Deny Template

## Objective
Ensure network isolation primitives are available before workloads deploy by implementing Kubernetes NetworkPolicy resources with a default-deny security model.

## Prerequisites
- Kubernetes cluster with CNI supporting NetworkPolicies (Cilium recommended)
- `kubectl` configured with cluster access
- Cluster admin permissions for creating NetworkPolicies

## Scripts Overview

### 1. `01-pre-deployment-check.sh`
**Purpose**: Validates all prerequisites before deployment
**Checks**:
- kubectl installation and configuration
- Cluster connectivity
- NetworkPolicy CRD availability
- CNI NetworkPolicy support
- Resource availability

### 2. `02-deployment.sh`
**Purpose**: Implements NetworkPolicy resources
**Creates**:
- Default-deny NetworkPolicy template
- Plane-specific policy templates (Control, Data, Observability)
- Test namespace with dummy pod
- Applied policies for testing
- Comprehensive documentation

### 3. `03-validation.sh`
**Purpose**: Validates the implementation
**Tests**:
- Resource existence and correctness
- NetworkPolicy functionality
- DNS resolution with policies
- Connectivity blocking/allowance
- Template validation

### 4. `run-all.sh`
**Purpose**: Runs all three scripts in sequence
**Flow**: Pre-deployment → Deployment → Validation

### 5. `cleanup.sh`
**Purpose**: Removes test resources
**Removes**: Test namespace, pods, policies (preserves templates)

## Deliverables

### Template Files (`shared/` directory)
1. `network-policy-template.yaml` - Default deny all traffic
2. `control-plane-policy.yaml` - Control plane isolation
3. `data-plane-policy.yaml` - Data plane isolation
4. `observability-plane-policy.yaml` - Observability plane isolation
5. `NETWORK_POLICY_PATTERNS.md` - Usage guide and patterns

### Default-Deny Template
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: {{ .Namespace }}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  # No rules = deny all by default
```

## Usage

### Quick Start
```bash
# Make scripts executable
chmod +x *.sh

# Run complete implementation
./run-all.sh
```

### Step-by-Step Execution
```bash
# 1. Check prerequisites
./01-pre-deployment-check.sh

# 2. Deploy resources
./02-deployment.sh

# 3. Validate implementation
./03-validation.sh

# 4. Clean up test resources (optional)
./cleanup.sh
```

### Manual Testing
After deployment, test resources are available in the `networkpolicy-test` namespace:
```bash
# Check applied policies
kubectl get networkpolicies -n networkpolicy-test

# Test pod connectivity
kubectl exec test-pod-networkpolicy -n networkpolicy-test -- nslookup kubernetes.default.svc.cluster.local

# Describe policies
kubectl describe networkpolicy default-deny-all -n networkpolicy-test
```

## Validation Commands
```bash
# Verify NetworkPolicy CRD is installed
kubectl api-resources | grep networkpolicies

# Test template application
kubectl apply -f shared/network-policy-template.yaml --dry-run=client
```

## Network Policy Patterns

### 1. Default Deny + Specific Allow
Start with default-deny, then add specific allowance policies for required traffic.

### 2. Plane-Specific Isolation
- **Control Plane**: Isolate kube-system, allow API server traffic
- **Data Plane**: Isolate applications, allow ingress traffic
- **Observability Plane**: Allow metrics collection from all namespaces

### 3. Tiered Application Isolation
Separate frontend, backend, and database tiers with specific policies.

## Testing Methodology

1. **Baseline Test**: Apply default-deny, verify no traffic passes
2. **Incremental Allowance**: Add specific policies, verify traffic flows
3. **Negative Testing**: Verify unwanted traffic is blocked
4. **DNS Validation**: Ensure DNS resolution works with policies

## Troubleshooting

### Common Issues

1. **NetworkPolicy CRD Not Available**
   ```
   Error: the server doesn't have a resource type "networkpolicies"
   ```
   **Solution**: Ensure CNI (Cilium/Calico) is installed and supports NetworkPolicies.

2. **DNS Not Working**
   **Solution**: Apply DNS allowance policy or ensure default-deny doesn't block port 53.

3. **Policies Not Taking Effect**
   **Solution**: Verify pod labels match policy selectors and CNI is functioning.

### Debug Commands
```bash
# Check CNI status
kubectl get pods -n kube-system -l k8s-app=cilium

# Check policy status
kubectl describe networkpolicy <name> -n <namespace>

# Test connectivity
kubectl exec <pod> -n <namespace> -- curl <service>.<namespace>.svc.cluster.local
```

## Directory Structure
```
phase-bs5-networkpolicy/
├── 01-pre-deployment-check.sh    # Prerequisite validation
├── 02-deployment.sh              # Resource deployment
├── 03-validation.sh              # Implementation validation
├── run-all.sh                    # Complete workflow
├── cleanup.sh                    # Test resource cleanup
├── README.md                     # This file
├── logs/                         # Execution logs
├── shared/                       # Template files
│   ├── network-policy-template.yaml
│   ├── control-plane-policy.yaml
│   ├── data-plane-policy.yaml
│   ├── observability-plane-policy.yaml
│   └── NETWORK_POLICY_PATTERNS.md
└── execution-YYYYMMDD-HHMMSS/    # Execution artifacts
```

## Next Steps After Implementation

1. **Review Templates**: Customize plane-specific policies for your architecture
2. **Apply to Production**: Start with non-critical namespaces
3. **Monitor**: Watch for blocked traffic that should be allowed
4. **Iterate**: Refine policies based on actual traffic patterns
5. **Document**: Update policies as application requirements change

## References
- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Cilium NetworkPolicy Guide](https://docs.cilium.io/en/stable/network/kubernetes/policy/)
- [Calico NetworkPolicy](https://docs.projectcalico.org/security/network-policy)

## Logs and Reports
- Logs are stored in `logs/` directory with timestamps
- Validation reports are generated after each run
- Execution directories preserve applied manifests

## Support
For issues with the scripts or implementation, check the logs in the `logs/` directory and review the validation reports.