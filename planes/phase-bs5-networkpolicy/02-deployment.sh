#!/bin/bash

# BS-5 NetworkPolicy CRD + Default-Deny Template - Deployment Script
# This script implements NetworkPolicy resources including default-deny template

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/deployment-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "================================================"
echo "BS-5 NetworkPolicy - Deployment"
echo "Started: $(date)"
echo "================================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Create shared directory for templates
SHARED_DIR="${SCRIPT_DIR}/shared"
mkdir -p "${SHARED_DIR}"

# Create execution directory for this run
EXECUTION_DIR="${SCRIPT_DIR}/execution-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${EXECUTION_DIR}"

# Step 1: Create default-deny NetworkPolicy template
print_step "1. Creating default-deny NetworkPolicy template..."

cat > "${SHARED_DIR}/network-policy-template.yaml" << 'EOF'
# BS-5 NetworkPolicy Template: Default Deny All
# This template provides a baseline network isolation policy
# Usage: Apply to namespaces that require strict network isolation
# Variables:
#   {{ .Namespace }} - Target namespace (required)

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: {{ .Namespace }}
  labels:
    policy-type: baseline
    managed-by: bs5-networkpolicy
    created: "{{ .Timestamp }}"  # Use format: YYYYMMDD-HHMMSS
spec:
  # Empty podSelector matches all pods in the namespace
  podSelector: {}
  
  # Apply to both ingress and egress traffic
  policyTypes:
  - Ingress
  - Egress
  
  # No rules specified = deny all traffic by default
  # Note: This is a baseline policy. Additional policies should be created
  #       to allow specific traffic patterns as needed.
EOF

print_success "Created default-deny template at ${SHARED_DIR}/network-policy-template.yaml"

# Step 2: Create plane-specific policy templates
print_step "2. Creating plane-specific NetworkPolicy templates..."

# Control Plane Policy
cat > "${SHARED_DIR}/control-plane-policy.yaml" << 'EOF'
# BS-5 NetworkPolicy: Control Plane Isolation
# This policy isolates control plane components and allows only necessary traffic
# Apply to: kube-system, monitoring, logging namespaces

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: control-plane-isolation
  namespace: {{ .Namespace }}
  labels:
    policy-type: plane-isolation
    plane: control
    managed-by: bs5-networkpolicy
spec:
  podSelector:
    matchLabels:
      # This should match your control plane component labels
      # Adjust based on your actual labeling strategy
      plane: control
  
  policyTypes:
  - Ingress
  - Egress
  
  # Ingress rules: Allow traffic from:
  # - API server (for all components)
  # - Other control plane components
  # - Monitoring agents
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    - podSelector:
        matchLabels:
          component: kube-apiserver
  
  # Egress rules: Allow traffic to:
  # - API server
  # - etcd
  # - DNS services
  # - Monitoring endpoints
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 6443  # API server
    - protocol: TCP
      port: 2379  # etcd client
    - protocol: TCP
      port: 2380  # etcd peer
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
EOF

# Data Plane Policy
cat > "${SHARED_DIR}/data-plane-policy.yaml" << 'EOF'
# BS-5 NetworkPolicy: Data Plane Isolation
# This policy isolates data plane components (applications, services)
# Apply to: application namespaces

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: data-plane-isolation
  namespace: {{ .Namespace }}
  labels:
    policy-type: plane-isolation
    plane: data
    managed-by: bs5-networkpolicy
spec:
  podSelector:
    matchLabels:
      # This should match your data plane component labels
      plane: data
  
  policyTypes:
  - Ingress
  - Egress
  
  # Ingress rules: Allow traffic from:
  # - Ingress controllers
  # - Other data plane services in same namespace
  # - Monitoring agents
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx  # Adjust to your ingress namespace
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
  - from:
    - namespaceSelector:
        matchLabels:
          name: {{ .Namespace }}
  
  # Egress rules: Allow traffic to:
  # - DNS services
  # - Database services (if applicable)
  # - External services (restrict to specific IP ranges if needed)
  egress:
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    # Restrict to common web ports
    ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
EOF

# Observability Plane Policy
cat > "${SHARED_DIR}/observability-plane-policy.yaml" << 'EOF'
# BS-5 NetworkPolicy: Observability Plane Isolation
# This policy isolates monitoring, logging, and tracing components
# Apply to: monitoring, logging, tracing namespaces

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: observability-plane-isolation
  namespace: {{ .Namespace }}
  labels:
    policy-type: plane-isolation
    plane: observability
    managed-by: bs5-networkpolicy
spec:
  podSelector:
    matchLabels:
      # This should match your observability component labels
      plane: observability
  
  policyTypes:
  - Ingress
  - Egress
  
  # Ingress rules: Allow traffic from:
  # - All namespaces (for metrics collection)
  # - API server
  ingress:
  - from:
    - namespaceSelector: {}  # Allow from all namespaces
    ports:
    - protocol: TCP
      port: 9090  # Prometheus
    - protocol: TCP
      port: 3000  # Grafana
    - protocol: TCP
      port: 3100  # Loki
  
  # Egress rules: Allow traffic to:
  # - All pods for scraping metrics
  # - External storage (S3, etc.)
  egress:
  - to:
    - namespaceSelector: {}  # Allow to all namespaces
    ports:
    - protocol: TCP
      port: 9100  # node-exporter
    - protocol: TCP
      port: 8080  # application metrics
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    ports:
    - protocol: TCP
      port: 443  # External APIs
EOF

print_success "Created plane-specific policy templates"

# Step 3: Create test namespace and resources
print_step "3. Creating test namespace and resources..."

TEST_NS="networkpolicy-test"
DUMMY_POD_NAME="test-pod-networkpolicy"

# Create test namespace
kubectl create namespace "$TEST_NS" --dry-run=client -o yaml > "${EXECUTION_DIR}/test-namespace.yaml"
kubectl apply -f "${EXECUTION_DIR}/test-namespace.yaml"
print_success "Created test namespace: $TEST_NS"

# Create dummy pod for testing
cat > "${EXECUTION_DIR}/dummy-pod.yaml" << EOF
apiVersion: v1
kind: Pod
metadata:
  name: $DUMMY_POD_NAME
  namespace: $TEST_NS
  labels:
    app: test-pod
    purpose: networkpolicy-test
    managed-by: bs5-networkpolicy
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 80
    resources:
      requests:
        memory: "64Mi"
        cpu: "50m"
      limits:
        memory: "128Mi"
        cpu: "100m"
  restartPolicy: Always
EOF

kubectl apply -f "${EXECUTION_DIR}/dummy-pod.yaml"
print_success "Created dummy pod: $DUMMY_POD_NAME"

# Wait for pod to be ready
print_step "Waiting for dummy pod to be ready..."
sleep 10
if kubectl get pod "$DUMMY_POD_NAME" -n "$TEST_NS" | grep -q "Running"; then
    print_success "Dummy pod is running"
else
    print_warning "Dummy pod not yet running, continuing anyway..."
fi

# Step 4: Apply default-deny policy to test namespace
print_step "4. Applying default-deny NetworkPolicy to test namespace..."

# Create a processed version of the template with actual values
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
cat > "${EXECUTION_DIR}/default-deny-applied.yaml" << EOF
# Applied default-deny NetworkPolicy for $TEST_NS
# Generated from template at $(date)

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: $TEST_NS
  labels:
    policy-type: baseline
    managed-by: bs5-networkpolicy
    created: "$TIMESTAMP"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

kubectl apply -f "${EXECUTION_DIR}/default-deny-applied.yaml"
print_success "Applied default-deny NetworkPolicy to namespace: $TEST_NS"

# Step 5: Create and apply allow-dns policy (to allow DNS resolution)
print_step "5. Creating DNS allowance policy..."

cat > "${EXECUTION_DIR}/allow-dns-policy.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: $TEST_NS
  labels:
    policy-type: dns-allowance
    managed-by: bs5-networkpolicy
spec:
  podSelector:
    matchLabels:
      app: test-pod
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: core-dns
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
EOF

kubectl apply -f "${EXECUTION_DIR}/allow-dns-policy.yaml"
print_success "Applied DNS allowance policy"

# Step 6: Create documentation
print_step "6. Creating implementation documentation..."

cat > "${SHARED_DIR}/NETWORK_POLICY_PATTERNS.md" << 'EOF'
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
EOF

print_success "Created NetworkPolicy patterns documentation"

# Step 7: Create run-all script
print_step "7. Creating comprehensive run script..."

cat > "${SCRIPT_DIR}/run-all.sh" << 'EOF'
#!/bin/bash

# BS-5 NetworkPolicy - Comprehensive Run Script
# Runs pre-deployment check, deployment, and validation in sequence

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"

MAIN_LOG="${LOG_DIR}/bs5-full-run-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${MAIN_LOG}") 2>&1

echo "================================================"
echo "BS-5 NetworkPolicy - Full Implementation Run"
echo "Started: $(date)"
echo "================================================"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

run_step() {
    echo -e "${BLUE}[RUNNING]${NC} $1..."
    if bash "$2"; then
        echo -e "${GREEN}[COMPLETED]${NC} $1"
        return 0
    else
        echo -e "${RED}[FAILED]${NC} $1"
        return 1
    fi
}

# Step 1: Pre-deployment check
run_step "Pre-deployment check" "${SCRIPT_DIR}/01-pre-deployment-check.sh"
if [ $? -ne 0 ]; then
    echo "Pre-deployment check failed. Aborting."
    exit 1
fi

echo ""
echo "Pre-deployment check passed. Proceeding with deployment..."
echo ""

# Step 2: Deployment
run_step "Deployment" "${SCRIPT_DIR}/02-deployment.sh"
if [ $? -ne 0 ]; then
    echo "Deployment failed. Check logs for details."
    exit 1
fi

echo ""
echo "Deployment completed. Proceeding with validation..."
echo ""

# Step 3: Validation
run_step "Validation" "${SCRIPT_DIR}/03-validation.sh"
if [ $? -ne 0 ]; then
    echo "Validation failed. Some checks did not pass."
    exit 1
fi

echo ""
echo "================================================"
echo "BS-5 NetworkPolicy - Full Implementation Complete"
echo "================================================"
echo ""
echo "All steps completed successfully!"
echo ""
echo "Summary:"
echo "1. ✓ Pre-deployment checks passed"
echo "2. ✓ NetworkPolicy resources deployed"
echo "3. ✓ Validation tests passed"
echo ""
echo "Created resources:"
echo "  - Default-deny NetworkPolicy template"
echo "  - Plane-specific policy templates"
echo "  - Test namespace with dummy pod"
echo "  - Applied policies for testing"
echo "  - Comprehensive documentation"
echo ""
echo "Next steps:"
echo "1. Review the policies in ${SCRIPT_DIR}/shared/"
echo "2. Apply policies to your production namespaces"
echo "3. Monitor network traffic with the applied policies"
echo ""
echo "Main log file: ${MAIN_LOG}"
echo "================================================"
echo "Completed: $(date)"
echo "================================================"
EOF

chmod +x "${SCRIPT_DIR}/run-all.sh"
print_success "Created comprehensive run script: ${SCRIPT_DIR}/run-all.sh"

# Final summary
echo ""
echo "================================================"
echo "BS-5 NetworkPolicy - Deployment Complete"
echo "================================================"
echo ""
echo "Successfully deployed NetworkPolicy resources:"
echo ""
echo "1. Templates created in ${SHARED_DIR}/:"
echo "   - network-policy-template.yaml (default deny)"
echo "   - control-plane-policy.yaml"
echo "   - data-plane-policy.yaml"
echo "   - observability-plane-policy.yaml"
echo "   - NETWORK_POLICY_PATTERNS.md"
echo ""
echo "2. Test resources deployed:"
echo "   - Namespace: ${TEST_NS}"
echo "   - Dummy pod: ${DUMMY_POD_NAME}"
echo "   - Applied policies: default-deny-all, allow-dns"
echo ""
echo "3. Execution artifacts:"
echo "   - Log file: ${LOG_FILE}"
echo "   - Execution directory: ${EXECUTION_DIR}"
echo "   - Run-all script: ${SCRIPT_DIR}/run-all.sh"
echo ""
echo "Next steps:"
echo "1. Run 03-validation.sh to verify the implementation"
echo "2. Review the policy patterns documentation"
echo "3. Apply policies to your production namespaces"
echo ""
echo "================================================"
echo "Deployment completed: $(date)"
echo "================================================"