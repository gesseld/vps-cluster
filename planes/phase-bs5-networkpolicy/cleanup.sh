#!/bin/bash

# BS-5 NetworkPolicy - Cleanup Script
# Removes test resources created during deployment and validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/cleanup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "================================================"
echo "BS-5 NetworkPolicy - Cleanup"
echo "Started: $(date)"
echo "================================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEST_NS="networkpolicy-test"
DUMMY_POD_NAME="test-pod-networkpolicy"

print_step() {
    echo -e "${BLUE}[CLEANUP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Step 1: Delete test namespace (this will cascade delete all resources)
print_step "1. Deleting test namespace '$TEST_NS'..."
if kubectl get namespace "$TEST_NS" &> /dev/null; then
    kubectl delete namespace "$TEST_NS" --wait=false
    print_success "Initiated deletion of namespace '$TEST_NS'"
    
    # Wait for namespace deletion
    echo "Waiting for namespace deletion to complete..."
    for i in {1..30}; do
        if ! kubectl get namespace "$TEST_NS" &> /dev/null; then
            print_success "Namespace '$TEST_NS' deleted successfully"
            break
        fi
        sleep 2
        echo "  Waiting... ($((i*2)) seconds)"
    done
    
    if kubectl get namespace "$TEST_NS" &> /dev/null; then
        print_warning "Namespace '$TEST_NS' still exists after 60 seconds"
        print_warning "You may need to delete it manually: kubectl delete namespace $TEST_NS --force --grace-period=0"
    fi
else
    print_success "Test namespace '$TEST_NS' not found (already cleaned up)"
fi

# Step 2: Delete any leftover pods with networkpolicy-test label
print_step "2. Cleaning up any leftover test pods..."
LEFTOVER_PODS=$(kubectl get pods --all-namespaces -l "purpose=networkpolicy-test" -o name 2>/dev/null || true)
if [ -n "$LEFTOVER_PODS" ]; then
    echo "Found leftover pods:"
    echo "$LEFTOVER_PODS"
    kubectl delete $LEFTOVER_PODS --force --grace-period=0 2>/dev/null || true
    print_success "Deleted leftover test pods"
else
    print_success "No leftover test pods found"
fi

# Step 3: Delete any NetworkPolicies with bs5-networkpolicy label
print_step "3. Cleaning up NetworkPolicies with bs5-networkpolicy label..."
NETWORK_POLICIES=$(kubectl get networkpolicies --all-namespaces -l "managed-by=bs5-networkpolicy" -o name 2>/dev/null || true)
if [ -n "$NETWORK_POLICIES" ]; then
    echo "Found NetworkPolicies to clean up:"
    echo "$NETWORK_POLICIES"
    kubectl delete $NETWORK_POLICIES 2>/dev/null || true
    print_success "Deleted NetworkPolicies with bs5-networkpolicy label"
else
    print_success "No NetworkPolicies with bs5-networkpolicy label found"
fi

# Step 4: Clean up execution directories (keep only last 3)
print_step "4. Cleaning up old execution directories..."
EXECUTION_DIRS=($(find "${SCRIPT_DIR}" -maxdepth 1 -type d -name "execution-*" | sort -r))
if [ ${#EXECUTION_DIRS[@]} -gt 3 ]; then
    for dir in "${EXECUTION_DIRS[@]:3}"; do
        echo "  Removing: $(basename "$dir")"
        rm -rf "$dir"
    done
    print_success "Removed old execution directories (kept last 3)"
else
    print_success "No old execution directories to clean up"
fi

# Step 5: Clean up old log files (keep only last 10)
print_step "5. Cleaning up old log files..."
LOG_FILES=($(find "${LOG_DIR}" -maxdepth 1 -type f -name "*.log" | sort -r))
if [ ${#LOG_FILES[@]} -gt 10 ]; then
    for file in "${LOG_FILES[@]:10}"; do
        echo "  Removing: $(basename "$file")"
        rm -f "$file"
    done
    print_success "Removed old log files (kept last 10)"
else
    print_success "No old log files to clean up"
fi

# Step 6: Verify cleanup
print_step "6. Verifying cleanup..."
echo "Checking for remaining test resources..."

# Check for test namespace
if kubectl get namespace "$TEST_NS" &> /dev/null; then
    print_warning "Test namespace '$TEST_NS' still exists"
else
    print_success "Test namespace '$TEST_NS' removed"
fi

# Check for test pods
TEST_PODS=$(kubectl get pods --all-namespaces -l "purpose=networkpolicy-test" --no-headers 2>/dev/null | wc -l)
if [ "$TEST_PODS" -gt 0 ]; then
    print_warning "Found $TEST_PODS test pod(s) still running"
else
    print_success "All test pods removed"
fi

# Check for NetworkPolicies with our label
REMAINING_POLICIES=$(kubectl get networkpolicies --all-namespaces -l "managed-by=bs5-networkpolicy" --no-headers 2>/dev/null | wc -l)
if [ "$REMAINING_POLICIES" -gt 0 ]; then
    print_warning "Found $REMAINING_POLICIES NetworkPolicy(ies) with bs5-networkpolicy label"
else
    print_success "All bs5-networkpolicy NetworkPolicies removed"
fi

# Final summary
echo ""
echo "================================================"
echo "Cleanup Summary"
echo "================================================"
echo "✓ Test namespace deletion initiated"
echo "✓ Leftover test pods cleaned up"
echo "✓ NetworkPolicies with bs5-networkpolicy label removed"
echo "✓ Old execution directories cleaned up"
echo "✓ Old log files cleaned up"
echo ""
echo "Note: Template files in ${SCRIPT_DIR}/shared/ were NOT removed."
echo "      These are intended to be kept for future use."
echo ""
echo "To completely remove all BS-5 resources (including templates):"
echo "  rm -rf ${SCRIPT_DIR}/shared/"
echo ""
echo "Log file: ${LOG_FILE}"
echo "================================================"
echo "Cleanup completed: $(date)"
echo "================================================"

# Create cleanup report
CLEANUP_REPORT="${LOG_DIR}/cleanup-report-$(date +%Y%m%d-%H%M%S).md"
cat > "$CLEANUP_REPORT" << EOF
# BS-5 NetworkPolicy Cleanup Report
**Generated:** $(date)

## Actions Performed
1. Deleted test namespace: $TEST_NS
2. Cleaned up leftover test pods: $( [ -n "$LEFTOVER_PODS" ] && echo "Yes" || echo "None found" )
3. Removed NetworkPolicies with bs5-networkpolicy label: $( [ -n "$NETWORK_POLICIES" ] && echo "Yes" || echo "None found" )
4. Cleaned up old execution directories: $( [ ${#EXECUTION_DIRS[@]} -gt 3 ] && echo "Yes (kept last 3)" || echo "None to clean" )
5. Cleaned up old log files: $( [ ${#LOG_FILES[@]} -gt 10 ] && echo "Yes (kept last 10)" || echo "None to clean" )

## Remaining Resources
- Test namespace: $(kubectl get namespace "$TEST_NS" &>/dev/null && echo "Exists" || echo "Removed")
- Test pods: $TEST_PODS remaining
- NetworkPolicies with bs5 label: $REMAINING_POLICIES remaining

## Preserved Resources
The following resources were NOT removed:
- Template files in \`${SCRIPT_DIR}/shared/\`
- Script files in \`${SCRIPT_DIR}/\`
- Last 3 execution directories
- Last 10 log files

## Next Steps
1. If any resources remain, clean them up manually
2. Templates are preserved for future use
3. To start fresh, run the deployment script again

**Log file:** ${LOG_FILE}
EOF

echo "Cleanup report saved to: ${CLEANUP_REPORT}"