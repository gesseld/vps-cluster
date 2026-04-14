#!/bin/bash

# BS-5 NetworkPolicy CRD + Default-Deny Template - Pre-deployment Check Script
# This script verifies all prerequisites before deploying NetworkPolicy resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/pre-deployment-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "================================================"
echo "BS-5 NetworkPolicy - Pre-deployment Check"
echo "Started: $(date)"
echo "================================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} $2"
    else
        echo -e "${RED}[FAIL]${NC} $2"
        exit 1
    fi
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check 1: Verify kubectl is installed and configured
echo "1. Checking kubectl installation..."
if command -v kubectl &> /dev/null; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | head -n1)
    print_status 0 "kubectl found: $KUBECTL_VERSION"
else
    print_status 1 "kubectl not found in PATH"
fi

# Check 2: Verify kubeconfig exists and is accessible
echo "2. Checking kubeconfig..."
if [ -f "$HOME/.kube/config" ] || [ -n "$KUBECONFIG" ]; then
    print_status 0 "kubeconfig found"
else
    print_warning "No kubeconfig found. Checking for cluster-access files..."
    if [ -f "${SCRIPT_DIR}/../cluster-access" ]; then
        print_status 0 "cluster-access file found"
    else
        print_status 1 "No kubeconfig or cluster-access file found"
    fi
fi

# Check 3: Verify cluster connectivity
echo "3. Testing cluster connectivity..."
if kubectl cluster-info &> /dev/null; then
    CLUSTER_INFO=$(kubectl cluster-info | head -n1)
    print_status 0 "Cluster accessible: $CLUSTER_INFO"
else
    print_status 1 "Cannot connect to cluster"
fi

# Check 4: Verify NetworkPolicy CRD is available
echo "4. Checking NetworkPolicy CRD availability..."
if kubectl api-resources | grep -q "networkpolicies"; then
    NETWORKPOLICY_CRD=$(kubectl api-resources | grep networkpolicies)
    print_status 0 "NetworkPolicy CRD available: $NETWORKPOLICY_CRD"
else
    print_status 1 "NetworkPolicy CRD not available. Ensure CNI (Cilium) supports NetworkPolicies"
fi

# Check 5: Verify CNI supports NetworkPolicies
echo "5. Checking CNI NetworkPolicy support..."
CNI_PODS=$(kubectl get pods -n kube-system -l k8s-app=cilium 2>/dev/null || true)
if [ -n "$CNI_PODS" ] && echo "$CNI_PODS" | grep -q "cilium"; then
    print_status 0 "Cilium CNI detected (supports NetworkPolicies)"
else
    print_warning "Cilium not detected. Checking for other CNI..."
    ALL_PODS=$(kubectl get pods -n kube-system 2>/dev/null | grep -E "(cilium|calico|flannel|weave)" || true)
    if [ -n "$ALL_PODS" ]; then
        print_status 0 "CNI detected: $(echo "$ALL_PODS" | head -n1 | awk '{print $1}')"
    else
        print_status 1 "No CNI detected that supports NetworkPolicies"
    fi
fi

# Check 6: Verify namespace for testing exists
echo "6. Checking test namespace..."
TEST_NS="networkpolicy-test"
if kubectl get namespace "$TEST_NS" &> /dev/null; then
    print_status 0 "Test namespace '$TEST_NS' exists"
else
    print_warning "Test namespace '$TEST_NS' doesn't exist (will be created during deployment)"
fi

# Check 7: Check for existing NetworkPolicies
echo "7. Checking existing NetworkPolicies..."
EXISTING_POLICIES=$(kubectl get networkpolicies --all-namespaces 2>/dev/null | wc -l)
if [ "$EXISTING_POLICIES" -gt 1 ]; then
    print_status 0 "Found $((EXISTING_POLICIES-1)) existing NetworkPolicy(ies)"
else
    print_status 0 "No existing NetworkPolicies found (clean slate)"
fi

# Check 8: Verify template directory exists
echo "8. Checking template directory..."
SHARED_DIR="${SCRIPT_DIR}/shared"
if [ -d "$SHARED_DIR" ]; then
    print_status 0 "Shared directory exists: $SHARED_DIR"
else
    print_warning "Shared directory doesn't exist (will be created during deployment)"
fi

# Check 9: Verify we have write permissions
echo "9. Checking write permissions..."
TEMP_FILE="${SCRIPT_DIR}/.write_test"
if touch "$TEMP_FILE" 2>/dev/null && rm "$TEMP_FILE" 2>/dev/null; then
    print_status 0 "Write permissions confirmed"
else
    print_status 1 "Cannot write to script directory"
fi

# Check 10: Check available cluster resources
echo "10. Checking cluster resources..."
NODES=$(kubectl get nodes 2>/dev/null | grep -v NAME | wc -l)
if [ "$NODES" -gt 0 ]; then
    print_status 0 "Cluster has $NODES node(s) available"
    
    # Check node readiness
    READY_NODES=$(kubectl get nodes 2>/dev/null | grep -c "Ready")
    if [ "$READY_NODES" -eq "$NODES" ]; then
        print_status 0 "All nodes are Ready"
    else
        print_warning "$((NODES - READY_NODES)) node(s) not Ready"
    fi
else
    print_status 1 "No nodes found in cluster"
fi

# Summary
echo ""
echo "================================================"
echo "Pre-deployment Check Summary"
echo "================================================"
echo "✓ kubectl installation verified"
echo "✓ Cluster connectivity confirmed"
echo "✓ NetworkPolicy CRD available"
echo "✓ CNI with NetworkPolicy support detected"
echo "✓ Write permissions confirmed"
echo "✓ Cluster resources available"
echo ""
echo "All prerequisites satisfied for BS-5 NetworkPolicy deployment."
echo ""
echo "Next steps:"
echo "1. Run 02-deployment.sh to implement NetworkPolicy resources"
echo "2. Run 03-validation.sh to verify implementation"
echo ""
echo "Log file: ${LOG_FILE}"
echo "================================================"
echo "Pre-deployment check completed: $(date)"
echo "================================================"