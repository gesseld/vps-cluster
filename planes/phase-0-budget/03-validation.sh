#!/bin/bash

set -euo pipefail

echo "=== Phase 0 Budget Scaffolding: Validation ==="
echo "Validating PriorityClasses deployment and functionality..."

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
    FAILED=true
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

FAILED=false
VALIDATION_START=$(date +%s)

echo ""
echo "1. Validating Kubernetes cluster connectivity..."
if kubectl cluster-info > /dev/null 2>&1; then
    check_pass "Kubernetes cluster is accessible"
else
    check_fail "Cannot connect to Kubernetes cluster"
    exit 1
fi

echo ""
echo "2. Validating PriorityClasses existence..."
EXPECTED_CLASSES=("foundation-critical" "foundation-high" "foundation-medium")
MISSING_CLASSES=()

for CLASS in "${EXPECTED_CLASSES[@]}"; do
    if kubectl get priorityclass "$CLASS" > /dev/null 2>&1; then
        check_pass "PriorityClass '$CLASS' exists"
    else
        check_fail "PriorityClass '$CLASS' not found"
        MISSING_CLASSES+=("$CLASS")
    fi
done

if [ ${#MISSING_CLASSES[@]} -gt 0 ]; then
    echo "   Missing classes: ${MISSING_CLASSES[*]}"
fi

echo ""
echo "3. Validating PriorityClasses values..."
echo "   Checking value assignments..."

# foundation-critical should be 1000000
CRITICAL_VALUE=$(kubectl get priorityclass foundation-critical -o jsonpath='{.value}' 2>/dev/null || echo "0")
if [ "$CRITICAL_VALUE" = "1000000" ]; then
    check_pass "foundation-critical has correct value (1000000)"
else
    check_fail "foundation-critical has incorrect value ($CRITICAL_VALUE, expected 1000000)"
fi

# foundation-high should be 900000
HIGH_VALUE=$(kubectl get priorityclass foundation-high -o jsonpath='{.value}' 2>/dev/null || echo "0")
if [ "$HIGH_VALUE" = "900000" ]; then
    check_pass "foundation-high has correct value (900000)"
else
    check_fail "foundation-high has incorrect value ($HIGH_VALUE, expected 900000)"
fi

# foundation-medium should be 800000
MEDIUM_VALUE=$(kubectl get priorityclass foundation-medium -o jsonpath='{.value}' 2>/dev/null || echo "0")
if [ "$MEDIUM_VALUE" = "800000" ]; then
    check_pass "foundation-medium has correct value (800000)"
else
    check_fail "foundation-medium has incorrect value ($MEDIUM_VALUE, expected 800000)"
fi

echo ""
echo "4. Validating PreemptionPolicy..."
echo "   Checking preemption policies..."

# Initialize array to track preemption policy status
PREEMPTION_STATUS=()

for CLASS in "${EXPECTED_CLASSES[@]}"; do
    CLASS_PREEMPTION=$(kubectl get priorityclass "$CLASS" -o jsonpath='{.preemptionPolicy}' 2>/dev/null || echo "None")
    if [ "$CLASS_PREEMPTION" = "PreemptLowerPriority" ]; then
        check_pass "'$CLASS' has correct PreemptLowerPriority policy"
        PREEMPTION_STATUS+=("$CLASS:correct")
    else
        check_fail "'$CLASS' has incorrect preemption policy ($CLASS_PREEMPTION, expected PreemptLowerPriority)"
        PREEMPTION_STATUS+=("$CLASS:incorrect")
    fi
done

echo ""
echo "5. Validating PriorityClasses are not global default..."
echo "   Checking globalDefault settings..."

# Initialize array to track global default status
GLOBAL_DEFAULT_STATUS=()

for CLASS in "${EXPECTED_CLASSES[@]}"; do
    # Get globalDefault field, default to empty string if not present
    CLASS_GLOBAL_DEFAULT=$(kubectl get priorityclass "$CLASS" -o jsonpath='{.globalDefault}' 2>/dev/null)
    
    # In Kubernetes, if globalDefault is not set, it defaults to false
    # An empty string means the field is not set, which is equivalent to false
    if [ "$CLASS_GLOBAL_DEFAULT" = "false" ] || [ -z "$CLASS_GLOBAL_DEFAULT" ]; then
        check_pass "'$CLASS' is not global default (correct)"
        GLOBAL_DEFAULT_STATUS+=("$CLASS:false")
    else
        check_fail "'$CLASS' is incorrectly set as global default (value: '$CLASS_GLOBAL_DEFAULT')"
        GLOBAL_DEFAULT_STATUS+=("$CLASS:true")
    fi
done

echo ""
echo "6. Validating PriorityClass descriptions..."
echo "   Checking description fields..."

CRITICAL_DESC=$(kubectl get priorityclass foundation-critical -o jsonpath='{.description}' 2>/dev/null || echo "")
if [[ "$CRITICAL_DESC" == *"Critical foundation"* ]] || [[ "$CRITICAL_DESC" == *"PostgreSQL"* ]]; then
    check_pass "foundation-critical has appropriate description"
else
    check_warn "foundation-critical description may be incomplete: '$CRITICAL_DESC'"
fi

HIGH_DESC=$(kubectl get priorityclass foundation-high -o jsonpath='{.description}' 2>/dev/null || echo "")
if [[ "$HIGH_DESC" == *"High-priority"* ]] || [[ "$HIGH_DESC" == *"Kyverno"* ]]; then
    check_pass "foundation-high has appropriate description"
else
    check_warn "foundation-high description may be incomplete: '$HIGH_DESC'"
fi

MEDIUM_DESC=$(kubectl get priorityclass foundation-medium -o jsonpath='{.description}' 2>/dev/null || echo "")
if [[ "$MEDIUM_DESC" == *"Medium-priority"* ]] || [[ "$MEDIUM_DESC" == *"Observability"* ]]; then
    check_pass "foundation-medium has appropriate description"
else
    check_warn "foundation-medium description may be incomplete: '$MEDIUM_DESC'"
fi

echo ""
echo "7. Testing PriorityClass assignment to pods..."
echo "   Creating test pods with different priority classes..."

# Create test namespace
kubectl create namespace validation-test --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1 || true

# Test pod with foundation-critical
CRITICAL_POD_YAML=$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-critical-pod
  namespace: validation-test
spec:
  priorityClassName: foundation-critical
  containers:
  - name: test
    image: busybox:latest
    command: ["sleep", "30"]
    resources:
      requests:
        memory: "32Mi"
        cpu: "10m"
  restartPolicy: Never
EOF
)

echo "   Creating test pod with foundation-critical priority..."
if echo "$CRITICAL_POD_YAML" | kubectl apply -f - > /dev/null 2>&1; then
    sleep 2
    CRITICAL_ASSIGNED=$(kubectl get pod test-critical-pod -n validation-test -o jsonpath='{.spec.priorityClassName}' 2>/dev/null || echo "")
    if [ "$CRITICAL_ASSIGNED" = "foundation-critical" ]; then
        check_pass "Pod correctly assigned foundation-critical priority"
    else
        check_fail "Pod not assigned foundation-critical priority (got: $CRITICAL_ASSIGNED)"
    fi
    # Clean up
    kubectl delete pod test-critical-pod -n validation-test --grace-period=0 --force > /dev/null 2>&1 || true
else
    check_warn "Could not create test pod (may be resource constraints)"
fi

echo ""
echo "8. Validating hierarchy order..."
echo "   Verifying priority values maintain correct hierarchy..."

if [ "$CRITICAL_VALUE" -gt "$HIGH_VALUE" ] && [ "$HIGH_VALUE" -gt "$MEDIUM_VALUE" ]; then
    check_pass "Priority hierarchy is correct: critical($CRITICAL_VALUE) > high($HIGH_VALUE) > medium($MEDIUM_VALUE)"
else
    check_fail "Priority hierarchy incorrect: critical($CRITICAL_VALUE) vs high($HIGH_VALUE) vs medium($MEDIUM_VALUE)"
fi

echo ""
echo "9. Checking for duplicate or conflicting PriorityClasses..."
echo "   Listing all PriorityClasses in cluster..."

ALL_CLASSES=$(kubectl get priorityclass --no-headers 2>/dev/null | awk '{print $1}' | sort)
DUPLICATES=$(echo "$ALL_CLASSES" | uniq -d)

if [ -z "$DUPLICATES" ]; then
    check_pass "No duplicate PriorityClass names found"
else
    check_fail "Duplicate PriorityClass names found: $DUPLICATES"
fi

echo "   Total PriorityClasses in cluster: $(echo "$ALL_CLASSES" | wc -l)"

echo ""
echo "10. Creating validation report..."
VALIDATION_END=$(date +%s)
DURATION=$((VALIDATION_END - VALIDATION_START))

REPORT_FILE="VALIDATION_REPORT.md"
cat <<EOF > "$REPORT_FILE"
# Phase 0 Budget Scaffolding - Validation Report

## Validation Details
- **Timestamp:** $(date)
- **Duration:** ${DURATION} seconds
- **Phase:** 0 - Budget Scaffolding
- **Task:** BS-1 PriorityClasses Deployment

## Validation Results

### PriorityClasses Status
$(kubectl get priorityclass | grep -E "NAME|foundation")

### Detailed Validation

1. **Cluster Connectivity:** $(if kubectl cluster-info > /dev/null 2>&1; then echo "✓ PASS"; else echo "✗ FAIL"; fi)
2. **PriorityClasses Existence:** $(if [ ${#MISSING_CLASSES[@]} -eq 0 ]; then echo "✓ PASS - All 3 classes present"; else echo "✗ FAIL - Missing: ${MISSING_CLASSES[*]}"; fi)
3. **Value Validation:**
   - foundation-critical: $CRITICAL_VALUE $(if [ "$CRITICAL_VALUE" = "1000000" ]; then echo "✓"; else echo "✗ (expected 1000000)"; fi)
   - foundation-high: $HIGH_VALUE $(if [ "$HIGH_VALUE" = "900000" ]; then echo "✓"; else echo "✗ (expected 900000)"; fi)
   - foundation-medium: $MEDIUM_VALUE $(if [ "$MEDIUM_VALUE" = "800000" ]; then echo "✓"; else echo "✗ (expected 800000)"; fi)
4. **PreemptionPolicy:** $(PREEMPTION_FAIL=false; for status in "${PREEMPTION_STATUS[@]}"; do if [[ "$status" == *":incorrect" ]]; then PREEMPTION_FAIL=true; break; fi; done; if [ "$PREEMPTION_FAIL" = false ]; then echo "✓ PASS - All set to PreemptLowerPriority"; else echo "✗ FAIL - Some classes have incorrect preemption policy"; fi)
5. **Global Default:** $(GLOBAL_DEFAULT_FAIL=false; for status in "${GLOBAL_DEFAULT_STATUS[@]}"; do if [[ "$status" == *":true" ]]; then GLOBAL_DEFAULT_FAIL=true; break; fi; done; if [ "$GLOBAL_DEFAULT_FAIL" = false ]; then echo "✓ PASS - None set as global default"; else echo "✗ FAIL - Some classes incorrectly set as global default"; fi)
6. **Hierarchy Order:** $(if [ "$CRITICAL_VALUE" -gt "$HIGH_VALUE" ] && [ "$HIGH_VALUE" -gt "$MEDIUM_VALUE" ]; then echo "✓ PASS - Correct hierarchy"; else echo "✗ FAIL - Hierarchy incorrect"; fi)

## Summary
$(if [ "$FAILED" = false ]; then echo "**✅ VALIDATION PASSED** - All PriorityClasses deployed correctly"; else echo "**❌ VALIDATION FAILED** - Issues detected"; fi)

## Next Steps
1. $(if [ "$FAILED" = false ]; then echo "Proceed to next phase with resource budget enforcement enabled"; else echo "Fix the issues identified above and re-run validation"; fi)
2. Apply PriorityClasses to foundation workloads using \`priorityClassName\` field
3. Monitor scheduling behavior during resource contention

## Notes
- PriorityClasses enable the scheduler to make informed decisions during resource pressure
- Higher priority pods can preempt lower priority pods when \`PreemptLowerPriority\` is set
- These classes establish the foundation for resource budget enforcement
EOF

echo "Validation report created: $REPORT_FILE"

echo ""
echo "=== Validation Complete ==="
if [ "$FAILED" = false ]; then
    echo -e "${GREEN}✅ VALIDATION PASSED${NC}"
    echo "All PriorityClasses deployed correctly and ready for use."
    echo ""
    echo "Next steps:"
    echo "1. Review validation report: $REPORT_FILE"
    echo "2. Apply PriorityClasses to foundation workloads"
    echo "3. Proceed to next phase with resource budget enforcement enabled"
else
    echo -e "${RED}❌ VALIDATION FAILED${NC}"
    echo "Issues detected with PriorityClasses deployment."
    echo ""
    echo "Check the validation report for details: $REPORT_FILE"
    echo "Fix the issues and re-run validation."
    exit 1
fi

# Clean up test namespace
kubectl delete namespace validation-test --grace-period=0 --force > /dev/null 2>&1 || true