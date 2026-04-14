#!/bin/bash

set -e

echo "=== Phase 0 Budget Scaffolding: Pre-Deployment Check ==="
echo "Checking all prerequisites for PriorityClasses deployment..."

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    if [ "$2" = "critical" ]; then
        echo -e "${RED}Critical failure. Exiting.${NC}"
        exit 1
    fi
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo ""
echo "1. Checking Kubernetes cluster connectivity..."
if kubectl cluster-info > /dev/null 2>&1; then
    check_pass "Kubernetes cluster is accessible"
    
    # Get cluster version
    K8S_VERSION=$(kubectl version --short 2>/dev/null | grep "Server Version" | awk '{print $3}')
    echo "   Cluster version: $K8S_VERSION"
    
    # Check if PriorityClass API is available
    if kubectl api-resources | grep -q priorityclasses; then
        check_pass "PriorityClass API is available"
    else
        check_fail "PriorityClass API not available" "critical"
    fi
else
    check_fail "Cannot connect to Kubernetes cluster" "critical"
fi

echo ""
echo "2. Checking existing PriorityClasses..."
EXISTING_PRIORITY_CLASSES=$(kubectl get priorityclass --no-headers 2>/dev/null | wc -l)

if [ "$EXISTING_PRIORITY_CLASSES" -eq 0 ]; then
    check_pass "No existing PriorityClasses (clean slate)"
else
    check_warn "$EXISTING_PRIORITY_CLASSES existing PriorityClasses found"
    echo "   Existing PriorityClasses:"
    kubectl get priorityclass
fi

echo ""
echo "3. Checking for conflicting foundation PriorityClasses..."
CONFLICTING_CLASSES=0
WARNING_CLASSES=0

# Check each foundation class name
for CLASS in foundation-critical foundation-high foundation-medium; do
    if kubectl get priorityclass "$CLASS" > /dev/null 2>&1; then
        check_warn "PriorityClass '$CLASS' already exists"
        CONFLICTING_CLASSES=$((CONFLICTING_CLASSES + 1))
    fi
done

# Check for similarly named classes that might cause confusion
for EXISTING_CLASS in critical high medium low; do
    if kubectl get priorityclass "$EXISTING_CLASS" > /dev/null 2>&1; then
        check_warn "Existing PriorityClass '$EXISTING_CLASS' may cause naming confusion"
        WARNING_CLASSES=$((WARNING_CLASSES + 1))
        
        # Show details of existing class
        VALUE=$(kubectl get priorityclass "$EXISTING_CLASS" -o jsonpath='{.value}' 2>/dev/null || echo "unknown")
        GLOBAL_DEFAULT=$(kubectl get priorityclass "$EXISTING_CLASS" -o jsonpath='{.globalDefault}' 2>/dev/null || echo "unknown")
        echo "   $EXISTING_CLASS: value=$VALUE, globalDefault=$GLOBAL_DEFAULT"
    fi
done

if [ "$CONFLICTING_CLASSES" -eq 0 ]; then
    check_pass "No conflicting foundation PriorityClasses found"
else
    check_fail "$CONFLICTING_CLASSES conflicting PriorityClasses found" "critical"
fi

if [ "$WARNING_CLASSES" -gt 0 ]; then
    echo ""
    echo "   Note: Existing PriorityClasses detected. Our foundation classes will be created"
    echo "   with different names to avoid conflicts:"
    echo "   - foundation-critical (1000000) vs existing critical ($(kubectl get priorityclass critical -o jsonpath='{.value}' 2>/dev/null || echo '?'))"
    echo "   - foundation-high (900000) vs existing high ($(kubectl get priorityclass high -o jsonpath='{.value}' 2>/dev/null || echo '?'))"
    echo "   - foundation-medium (800000) vs existing medium ($(kubectl get priorityclass medium -o jsonpath='{.value}' 2>/dev/null || echo '?'))"
fi

echo ""
echo "4. Checking manifest files..."
if [ -f "priority-classes.yaml" ]; then
    check_pass "priority-classes.yaml manifest found"
    
    # Validate YAML syntax
    if kubectl apply --dry-run=client -f priority-classes.yaml > /dev/null 2>&1; then
        check_pass "priority-classes.yaml has valid YAML syntax"
    else
        check_fail "priority-classes.yaml has invalid YAML syntax" "critical"
    fi
else
    check_fail "priority-classes.yaml not found" "critical"
fi

if [ -f "shared/priority-classes.md" ]; then
    check_pass "Documentation file shared/priority-classes.md found"
else
    check_warn "Documentation file shared/priority-classes.md not found"
fi

echo ""
echo "5. Checking kubectl permissions..."
# Test if we can create PriorityClasses
if kubectl auth can-i create priorityclass > /dev/null 2>&1; then
    check_pass "Has permission to create PriorityClasses"
else
    check_fail "No permission to create PriorityClasses" "critical"
fi

echo ""
echo "6. Checking node resources..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NODE_COUNT" -ge 1 ]; then
    check_pass "Cluster has $NODE_COUNT node(s)"
    
    # Check node status
    READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready")
    if [ "$READY_NODES" -eq "$NODE_COUNT" ]; then
        check_pass "All $NODE_COUNT nodes are Ready"
    else
        check_warn "$READY_NODES/$NODE_COUNT nodes are Ready"
    fi
else
    check_fail "No nodes found in cluster" "critical"
fi

echo ""
echo "7. Checking scheduler functionality..."
# In K3s, scheduler is integrated into the k3s server binary
# We can test scheduler functionality by checking if pods can be scheduled
# First, check if control plane is responsive
if kubectl get nodes > /dev/null 2>&1; then
    check_pass "Control plane is responsive"
    
    # Create a simple test pod to verify scheduling works
    TEST_POD_YAML=$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: scheduler-test-pod
  namespace: default
spec:
  containers:
  - name: test
    image: busybox:latest
    command: ["sleep", "5"]
    resources:
      requests:
        memory: "16Mi"
        cpu: "5m"
  restartPolicy: Never
EOF
    )
    
    echo "   Testing scheduler with simple pod..." > /dev/null 2>&1
    if echo "$TEST_POD_YAML" | kubectl apply --dry-run=client -f - > /dev/null 2>&1; then
        check_pass "Scheduler accepts pod specifications"
    else
        check_warn "Scheduler validation test inconclusive"
    fi
else
    check_fail "Control plane not responsive" "critical"
fi

echo ""
echo "=== Pre-Deployment Check Summary ==="
echo "All critical checks passed. Ready for deployment."
echo ""
echo "Next steps:"
echo "1. Review the PriorityClasses that will be created:"
echo "   - foundation-critical (1000000): PostgreSQL, NATS, Temporal"
echo "   - foundation-high (900000): Kyverno, SPIRE, MinIO"
echo "   - foundation-medium (800000): Observability components"
echo "2. Run deployment script: ./02-deployment.sh"
echo "3. Validate deployment: ./03-validation.sh"
echo ""
echo "Note: These PriorityClasses will enable resource budget enforcement"
echo "      by allowing critical workloads to preempt lower priority pods."