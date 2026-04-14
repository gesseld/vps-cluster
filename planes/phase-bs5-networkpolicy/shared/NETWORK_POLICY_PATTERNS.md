# BS-5 NetworkPolicy Patterns and Usage Guide

## Overview
This document describes the NetworkPolicy patterns implemented for BS-5 network isolation.

## Policy Templates

### 1. Default Deny All (`network-policy-template.yaml`)
**Purpose**: Baseline security policy that denies all traffic by default.

**Usage**:
```yaml
# Apply to any namespace requiring strict isolation
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: <target-namespace>
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

**Behavior**:
- Denies all incoming traffic to all pods in the namespace
- Denies all outgoing traffic from all pods in the namespace
- Must be combined with specific allowance policies

### 2. Plane-Specific Isolation Policies

#### Control Plane (`control-plane-policy.yaml`)
**Target**: kube-system, monitoring namespaces
**Purpose**: Isolate control plane components
**Key allowances**:
- Ingress from API server
- Egress to API server, etcd, DNS

#### Data Plane (`data-plane-policy.yaml`)
**Target**: Application namespaces
**Purpose**: Isolate application workloads
**Key allowances**:
- Ingress from ingress controllers
- Egress to DNS and external web services

#### Observability Plane (`observability-plane-policy.yaml`)
**Target**: Monitoring, logging namespaces
**Purpose**: Allow metrics collection while maintaining isolation
**Key allowances**:
- Ingress from all namespaces (metrics scraping)
- Egress to all pods (metrics collection)

## Implementation Patterns

### Pattern 1: Default Deny + Specific Allow
```yaml
# 1. Apply default deny
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: my-app
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]

# 2. Allow specific traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-access
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      app: api
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - port: 8080
```

### Pattern 2: Tiered Application Isolation
```yaml
# Frontend tier
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-isolation
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      tier: frontend
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: backend

# Backend tier
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-isolation
  namespace: my-app
spec:
  podSelector:
    matchLabels:
      tier: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
```

## Testing Methodology

1. **Baseline Test**: Apply default-deny, verify no traffic passes
2. **Incremental Allowance**: Add specific policies, verify traffic flows
3. **Negative Testing**: Verify unwanted traffic is blocked
4. **DNS Validation**: Ensure DNS resolution works with policies

## Troubleshooting

### Common Issues

1. **DNS Not Working**
   - Ensure DNS allowance policy is applied
   - Check kube-dns/core-dns pod labels
   - Verify egress policies allow port 53 TCP/UDP

2. **Pods Can't Communicate**
   - Check if default-deny policy is blocking traffic
   - Verify podSelector matches correct labels
   - Check namespaceSelector references

3. **Policy Not Taking Effect**
   - Verify CNI supports NetworkPolicies (Cilium/Calico)
   - Check policy is applied to correct namespace
   - Verify pod labels match policy selectors

### Debug Commands
```bash
# Check applied policies
kubectl get networkpolicies --all-namespaces

# Describe specific policy
kubectl describe networkpolicy <name> -n <namespace>

# Check pod network status
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A5 -B5 networkPolicy

# Test connectivity between pods
kubectl exec <source-pod> -n <namespace> -- curl <target-pod>.<namespace>.svc.cluster.local
```

## Best Practices

1. **Start with Default Deny**: Always begin with default-deny policy
2. **Use Labels Consistently**: Maintain consistent labeling strategy
3. **Test Incrementally**: Add policies one at a time and test
4. **Document Policies**: Keep policy documentation updated
5. **Monitor Policy Count**: Too many policies can impact performance
6. **Regular Audits**: Review and update policies regularly

## References
- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Cilium NetworkPolicy Guide](https://docs.cilium.io/en/stable/network/kubernetes/policy/)
- [Calico NetworkPolicy](https://docs.projectcalico.org/security/network-policy)
