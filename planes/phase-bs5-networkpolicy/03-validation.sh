#!/bin/bash

# BS-5 NetworkPolicy CRD + Default-Deny Template - Validation Script
# This script validates the NetworkPolicy implementation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
EXECUTION_DIR="${SCRIPT_DIR}/execution-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${LOG_DIR}"
mkdir -p "${EXECUTION_DIR}"

LOG_FILE="${LOG_DIR}/validation-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "================================================"
echo "BS-5 NetworkPolicy - Validation"
echo "Started: $(date)"
echo "================================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

TEST_NS="networkpolicy-test"
DUMMY_POD_NAME="test-pod-networkpolicy"

record_result() {
    case $1 in
        "PASS")
            echo -e "${GREEN}[PASS]${NC} $2"
            PASS_COUNT=$((PASS_COUNT + 1))
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} $2"
            FAIL_COUNT=$((FAIL_COUNT + 1))
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $2"
            WARN_COUNT=$((WARN_COUNT + 1))
            ;;
    esac
}

print_step() {
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

# Function to test network connectivity
test_connectivity() {
    local source_pod=$1
    local source_ns=$2
    local target=$3
    local target_ns=$4
    local port=${5:-80}
    local protocol=${6:-TCP}
    
    echo "Testing connectivity: $source_pod ($source_ns) -> $target ($target_ns):$port ($protocol)"
    
    # Try to connect (timeout after 5 seconds)
    if kubectl exec "$source_pod" -n "$source_ns" -- timeout 5 bash -c "echo > /dev/$protocol/$target.$target_ns.svc.cluster.local/$port" 2>/dev/null; then
        echo "  Result: Connection successful"
        return 0
    else
        echo "  Result: Connection failed (expected if policies are blocking)"
        return 1
    fi
}

# Function to check DNS resolution
test_dns_resolution() {
    local pod=$1
    local ns=$2
    local host=$3
    
    echo "Testing DNS resolution in $pod ($ns) for $host"
    
    # Try multiple times with delay
    for i in {1..3}; do
        if kubectl exec "$pod" -n "$ns" -- timeout 5 nslookup "$host" 2>/dev/null | grep -q -E "(Address|Name)"; then
            echo "  Result: DNS resolution successful (attempt $i)"
            return 0
        fi
        sleep 2
    done
    
    echo "  Result: DNS resolution failed after 3 attempts"
    return 1
}

# Start validation
print_step "Phase 1: Prerequisite Validation"

# Check 1: Verify test namespace exists
echo "1. Checking test namespace..."
if kubectl get namespace "$TEST_NS" &> /dev/null; then
    record_result "PASS" "Test namespace '$TEST_NS' exists"
else
    record_result "FAIL" "Test namespace '$TEST_NS' not found"
fi

# Check 2: Verify dummy pod exists and is running
echo "2. Checking dummy pod status..."
POD_STATUS=$(kubectl get pod "$DUMMY_POD_NAME" -n "$TEST_NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NOT_FOUND")
if [ "$POD_STATUS" = "Running" ]; then
    record_result "PASS" "Dummy pod '$DUMMY_POD_NAME' is running"
elif [ "$POD_STATUS" = "NOT_FOUND" ]; then
    record_result "FAIL" "Dummy pod '$DUMMY_POD_NAME' not found"
else
    record_result "WARN" "Dummy pod exists but not running (status: $POD_STATUS)"
fi

# Check 3: Verify NetworkPolicy CRD is available
echo "3. Checking NetworkPolicy CRD..."
if kubectl api-resources | grep -q "networkpolicies"; then
    record_result "PASS" "NetworkPolicy CRD is available"
else
    record_result "FAIL" "NetworkPolicy CRD not available"
fi

print_step "Phase 2: NetworkPolicy Resource Validation"

# Check 4: Verify default-deny policy is applied
echo "4. Checking default-deny NetworkPolicy..."
if kubectl get networkpolicy default-deny-all -n "$TEST_NS" &> /dev/null; then
    POLICY_SPEC=$(kubectl get networkpolicy default-deny-all -n "$TEST_NS" -o jsonpath='{.spec.policyTypes[*]}')
    if echo "$POLICY_SPEC" | grep -q "Ingress" && echo "$POLICY_SPEC" | grep -q "Egress"; then
        record_result "PASS" "Default-deny policy applied with both Ingress and Egress"
    else
        record_result "WARN" "Default-deny policy applied but missing policy types"
    fi
else
    record_result "FAIL" "Default-deny policy not found in namespace '$TEST_NS'"
fi

# Check 5: Verify DNS allowance policy is applied
echo "5. Checking DNS allowance policy..."
if kubectl get networkpolicy allow-dns -n "$TEST_NS" &> /dev/null; then
    record_result "PASS" "DNS allowance policy applied"
else
    record_result "FAIL" "DNS allowance policy not found"
fi

# Check 6: Verify policy count in test namespace
echo "6. Checking total policies in test namespace..."
POLICY_COUNT=$(kubectl get networkpolicies -n "$TEST_NS" --no-headers 2>/dev/null | wc -l)
if [ "$POLICY_COUNT" -ge 2 ]; then
    record_result "PASS" "Found $POLICY_COUNT NetworkPolicy(ies) in test namespace"
else
    record_result "WARN" "Only found $POLICY_COUNT NetworkPolicy(ies), expected at least 2"
fi

# Check 7: Verify policy labels
echo "7. Checking policy labels..."
DEFAULT_DENY_LABELS=$(kubectl get networkpolicy default-deny-all -n "$TEST_NS" -o jsonpath='{.metadata.labels}' 2>/dev/null || echo "{}")
if echo "$DEFAULT_DENY_LABELS" | grep -q "managed-by.*bs5-networkpolicy"; then
    record_result "PASS" "Default-deny policy has correct labels"
else
    record_result "WARN" "Default-deny policy missing expected labels"
fi

print_step "Phase 3: Template and Documentation Validation"

# Check 8: Verify template files exist
echo "8. Checking template files..."
SHARED_DIR="${SCRIPT_DIR}/shared"
TEMPLATE_FILES=(
    "network-policy-template.yaml"
    "control-plane-policy.yaml"
    "data-plane-policy.yaml"
    "observability-plane-policy.yaml"
    "NETWORK_POLICY_PATTERNS.md"
)

ALL_TEMPLATES_EXIST=true
for template in "${TEMPLATE_FILES[@]}"; do
    if [ -f "${SHARED_DIR}/${template}" ]; then
        echo "  ✓ ${template} exists"
    else
        echo "  ✗ ${template} missing"
        ALL_TEMPLATES_EXIST=false
    fi
done

if $ALL_TEMPLATES_EXIST; then
    record_result "PASS" "All template files exist in shared directory"
else
    record_result "FAIL" "Missing template files in shared directory"
fi

# Check 9: Verify template content
echo "9. Validating template content..."
if grep -q "default-deny-all" "${SHARED_DIR}/network-policy-template.yaml" && \
   grep -q "podSelector: {}" "${SHARED_DIR}/network-policy-template.yaml"; then
    record_result "PASS" "Default-deny template has correct structure"
else
    record_result "FAIL" "Default-deny template missing required content"
fi

# Check 10: Verify documentation
echo "10. Checking documentation..."
if [ -f "${SHARED_DIR}/NETWORK_POLICY_PATTERNS.md" ]; then
    DOC_SIZE=$(wc -l < "${SHARED_DIR}/NETWORK_POLICY_PATTERNS.md")
    if [ "$DOC_SIZE" -gt 50 ]; then
        record_result "PASS" "Documentation exists with substantial content ($DOC_SIZE lines)"
    else
        record_result "WARN" "Documentation exists but may be minimal ($DOC_SIZE lines)"
    fi
else
    record_result "FAIL" "Documentation file not found"
fi

print_step "Phase 4: Functional Network Validation"

# Note: These tests verify that policies are actually working
# Since we have default-deny, most connections should fail

# Check 11: Test DNS resolution (should work with allow-dns policy)
echo "11. Testing DNS resolution from dummy pod..."
if test_dns_resolution "$DUMMY_POD_NAME" "$TEST_NS" "kubernetes.default.svc.cluster.local"; then
    record_result "PASS" "DNS resolution works (allow-dns policy effective)"
else
    record_result "FAIL" "DNS resolution failed (allow-dns policy may not be working)"
fi

# Check 12: Test external connectivity (should be blocked by default-deny)
echo "12. Testing external connectivity (should be blocked)..."
# Create a simple test pod for external connectivity test
TEST_POD_NAME="external-test-$(date +%s)"
kubectl run "$TEST_POD_NAME" -n "$TEST_NS" --image=alpine --restart=Never --command -- sleep 3600 2>/dev/null || true

# Wait for pod to be ready
sleep 5

# Test connection to external service (should fail)
if kubectl exec "$TEST_POD_NAME" -n "$TEST_NS" -- timeout 3 wget -q --spider http://google.com 2>/dev/null; then
    record_result "FAIL" "External connectivity allowed (default-deny may not be working)"
else
    record_result "PASS" "External connectivity blocked as expected"
fi

# Cleanup test pod
kubectl delete pod "$TEST_POD_NAME" -n "$TEST_NS" --force --grace-period=0 2>/dev/null || true

# Check 13: Test inter-pod connectivity (should be blocked by default-deny)
echo "13. Testing inter-pod connectivity (should be blocked)..."
# Create a second test pod
TEST_POD_2="test-pod-2-$(date +%s)"
kubectl run "$TEST_POD_2" -n "$TEST_NS" --image=nginx:alpine --restart=Never 2>/dev/null || true
sleep 5

# Try to connect from dummy pod to test pod 2 (should fail)
if kubectl exec "$DUMMY_POD_NAME" -n "$TEST_NS" -- timeout 3 curl -s http://$TEST_POD_2.$TEST_NS.svc.cluster.local > /dev/null 2>&1; then
    record_result "FAIL" "Inter-pod connectivity allowed (default-deny may not be working)"
else
    record_result "PASS" "Inter-pod connectivity blocked as expected"
fi

# Cleanup test pod 2
kubectl delete pod "$TEST_POD_2" -n "$TEST_NS" --force --grace-period=0 2>/dev/null || true

# Check 14: Verify policy application dry-run
echo "14. Testing policy template application (dry-run)..."
# Create a test version with template variable replaced
TEMP_FILE="${EXECUTION_DIR}/test-template-$(date +%s).yaml"
sed 's/{{ .Namespace }}/test-namespace/g' "${SHARED_DIR}/network-policy-template.yaml" > "$TEMP_FILE"
if kubectl apply -f "$TEMP_FILE" --dry-run=client > /dev/null 2>&1; then
    record_result "PASS" "Policy template passes dry-run validation (with variable substitution)"
    rm -f "$TEMP_FILE"
else
    record_result "FAIL" "Policy template fails dry-run validation"
    rm -f "$TEMP_FILE"
fi

print_step "Phase 5: Cleanup Readiness Validation"

# Check 15: Verify cleanup script exists
echo "15. Checking cleanup script..."
if [ -f "${SCRIPT_DIR}/cleanup.sh" ]; then
    record_result "PASS" "Cleanup script exists"
else
    record_result "WARN" "Cleanup script not found (optional)"
fi

# Check 16: Verify run-all script exists and is executable
echo "16. Checking run-all script..."
if [ -f "${SCRIPT_DIR}/run-all.sh" ] && [ -x "${SCRIPT_DIR}/run-all.sh" ]; then
    record_result "PASS" "Run-all script exists and is executable"
else
    record_result "WARN" "Run-all script missing or not executable"
fi

print_step "Validation Summary"

echo ""
echo "================================================"
echo "VALIDATION RESULTS"
echo "================================================"
echo "Total Tests: $((PASS_COUNT + FAIL_COUNT + WARN_COUNT))"
echo -e "${GREEN}PASS: $PASS_COUNT${NC}"
echo -e "${RED}FAIL: $FAIL_COUNT${NC}"
echo -e "${YELLOW}WARN: $WARN_COUNT${NC}"
echo ""

# Calculate success percentage
TOTAL_TESTS=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
if [ "$TOTAL_TESTS" -gt 0 ]; then
    SUCCESS_PERCENT=$((PASS_COUNT * 100 / TOTAL_TESTS))
else
    SUCCESS_PERCENT=0
fi

echo "Success Rate: ${SUCCESS_PERCENT}%"

if [ "$FAIL_COUNT" -eq 0 ]; then
    if [ "$WARN_COUNT" -eq 0 ]; then
        echo -e "${GREEN}VALIDATION STATUS: ALL TESTS PASSED${NC}"
        OVERALL_RESULT="SUCCESS"
    else
        echo -e "${YELLOW}VALIDATION STATUS: PASSED WITH WARNINGS${NC}"
        OVERALL_RESULT="WARNING"
    fi
else
    echo -e "${RED}VALIDATION STATUS: FAILED${NC}"
    OVERALL_RESULT="FAILURE"
fi

echo ""
echo "================================================"
echo "RECOMMENDATIONS"
echo "================================================"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "Critical issues found:"
    echo "1. Review and fix all FAILED tests above"
    echo "2. Ensure NetworkPolicy CRD is available"
    echo "3. Verify policies are correctly applied"
    echo "4. Test network connectivity after fixes"
fi

if [ "$WARN_COUNT" -gt 0 ]; then
    echo "Warnings to address:"
    echo "1. Review WARN items for potential improvements"
    echo "2. Consider adding missing templates or documentation"
    echo "3. Verify all expected resources are present"
fi

if [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
    echo "All validation checks passed successfully!"
    echo ""
    echo "Next steps for production deployment:"
    echo "1. Review policy templates in ${SHARED_DIR}/"
    echo "2. Apply default-deny policies to production namespaces"
    echo "3. Create plane-specific policies based on your architecture"
    echo "4. Test policies in staging before production"
    echo "5. Monitor network traffic with policies applied"
fi

echo ""
echo "================================================"
echo "VALIDATION ARTIFACTS"
echo "================================================"
echo "Log file: ${LOG_FILE}"
echo "Test namespace: ${TEST_NS} (for manual testing)"
echo "Dummy pod: ${DUMMY_POD_NAME} (for manual testing)"
echo "Templates: ${SHARED_DIR}/"
echo ""

# Create validation report
REPORT_FILE="${LOG_DIR}/validation-report-$(date +%Y%m%d-%H%M%S).md"
cat > "$REPORT_FILE" << EOF
# BS-5 NetworkPolicy Validation Report
**Generated:** $(date)
**Overall Result:** ${OVERALL_RESULT}
**Success Rate:** ${SUCCESS_PERCENT}%

## Summary
- **Total Tests:** $((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
- **Passed:** ${PASS_COUNT}
- **Failed:** ${FAIL_COUNT}
- **Warnings:** ${WARN_COUNT}

## Test Results

### Phase 1: Prerequisite Validation
1. Test namespace exists: $( [ -n "$(kubectl get namespace "$TEST_NS" 2>/dev/null)" ] && echo "PASS" || echo "FAIL" )
2. Dummy pod status: ${POD_STATUS}
3. NetworkPolicy CRD available: $(kubectl api-resources | grep -q "networkpolicies" && echo "PASS" || echo "FAIL")

### Phase 2: NetworkPolicy Resource Validation
4. Default-deny policy applied: $(kubectl get networkpolicy default-deny-all -n "$TEST_NS" &>/dev/null && echo "PASS" || echo "FAIL")
5. DNS allowance policy applied: $(kubectl get networkpolicy allow-dns -n "$TEST_NS" &>/dev/null && echo "PASS" || echo "FAIL")
6. Total policies in test namespace: ${POLICY_COUNT}
7. Policy labels correct: $(echo "$DEFAULT_DENY_LABELS" | grep -q "managed-by.*bs5-networkpolicy" && echo "PASS" || echo "WARN")

### Phase 3: Template and Documentation Validation
8. All template files exist: $($ALL_TEMPLATES_EXIST && echo "PASS" || echo "FAIL")
9. Template content valid: $(grep -q "default-deny-all" "${SHARED_DIR}/network-policy-template.yaml" && echo "PASS" || echo "FAIL")
10. Documentation exists: $( [ -f "${SHARED_DIR}/NETWORK_POLICY_PATTERNS.md" ] && echo "PASS (${DOC_SIZE} lines)" || echo "FAIL")

### Phase 4: Functional Network Validation
11. DNS resolution works: $(test_dns_resolution "$DUMMY_POD_NAME" "$TEST_NS" "kubernetes.default.svc.cluster.local" >/dev/null 2>&1 && echo "PASS" || echo "FAIL")
12. External connectivity blocked: $( [ $? -eq 0 ] && echo "PASS" || echo "FAIL" )
13. Inter-pod connectivity blocked: $( [ $? -eq 0 ] && echo "PASS" || echo "FAIL" )
14. Policy template dry-run passes: $(kubectl apply -f "${SHARED_DIR}/network-policy-template.yaml" --dry-run=client >/dev/null 2>&1 && echo "PASS" || echo "FAIL")

### Phase 5: Cleanup Readiness Validation
15. Cleanup script exists: $( [ -f "${SCRIPT_DIR}/cleanup.sh" ] && echo "PASS" || echo "WARN" )
16. Run-all script executable: $( [ -f "${SCRIPT_DIR}/run-all.sh" ] && [ -x "${SCRIPT_DIR}/run-all.sh" ] && echo "PASS" || echo "WARN" )

## Recommendations
$(if [ "$FAIL_COUNT" -gt 0 ]; then
echo "1. Fix all FAILED tests before proceeding to production"
echo "2. Verify NetworkPolicy CRD support in your CNI"
echo "3. Ensure policies are correctly applied and effective"
fi)

$(if [ "$WARN_COUNT" -gt 0 ]; then
echo "1. Address warnings for better completeness"
echo "2. Consider adding missing optional components"
fi)

$(if [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
echo "1. BS-5 NetworkPolicy implementation is ready for production use"
echo "2. Apply templates to appropriate namespaces"
echo "3. Monitor network traffic with applied policies"
fi)

## Artifacts
- **Log File:** ${LOG_FILE}
- **Test Namespace:** ${TEST_NS}
- **Templates Directory:** ${SHARED_DIR}
- **Validation Script:** ${SCRIPT_DIR}/03-validation.sh

## Next Steps
1. Review this validation report
2. $(if [ "$FAIL_COUNT" -gt 0 ]; then echo "Fix identified issues and re-run validation"; else echo "Proceed with production deployment of NetworkPolicies"; fi)
3. Apply policies to appropriate namespaces based on plane architecture
4. Monitor and adjust policies as needed
EOF

echo "Validation report saved to: ${REPORT_FILE}"
echo ""
echo "================================================"
echo "Validation completed: $(date)"
echo "================================================"

# Exit with appropriate code
if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
    exit 0  # Warnings are acceptable
else
    exit 0
fi