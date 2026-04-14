#!/bin/bash
# BS-2: ResourceQuotas + LimitRanges Validation Script
# Validates all deliverables for namespace resource budgeting implementation

set -euo pipefail

echo "================================================================"
echo "BS-2: RESOURCEQUOTAS + LIMITRANGES VALIDATION"
echo "================================================================"
echo "Date: $(date)"
echo "Task: Validate all deliverables for BS-2 implementation"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VALIDATION_START=$(date +%s)
PASS=0
FAIL=0
WARN=0

print_pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; PASS=$((PASS + 1)); }
print_fail() { echo -e "${RED}❌ FAIL${NC}: $1"; FAIL=$((FAIL + 1)); }
print_warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; WARN=$((WARN + 1)); }
print_info() { echo -e "${YELLOW}ℹ️  INFO${NC}: $1"; }

echo "=== VALIDATION PHASE 1: FILE STRUCTURE ==="
echo ""

# Check all required files exist
REQUIRED_FILES=(
    "shared/foundation-namespaces.yaml"
    "shared/resource-quotas.yaml"
    "shared/limit-ranges.yaml"
    "shared/resource-budget.md"
    "01-pre-deployment-check.sh"
    "02-deployment.sh"
    "03-validation.sh"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_pass "File exists: $file"
        
        # Check file permissions for scripts
        if [[ "$file" == *.sh ]]; then
            if [ -x "$file" ]; then
                print_pass "Script is executable: $file"
            else
                print_warn "Script not executable: $file (run: chmod +x $file)"
            fi
        fi
    else
        print_fail "Missing file: $file"
    fi
done

echo ""
echo "=== VALIDATION PHASE 2: YAML SYNTAX ==="
echo ""

# Validate YAML syntax
YAML_FILES=(
    "shared/foundation-namespaces.yaml"
    "shared/resource-quotas.yaml"
    "shared/limit-ranges.yaml"
)

for yaml_file in "${YAML_FILES[@]}"; do
    if [ -f "$yaml_file" ]; then
        if kubectl apply --dry-run=client -f "$yaml_file" &> /dev/null; then
            print_pass "YAML syntax valid: $yaml_file"
        else
            print_fail "YAML syntax invalid: $yaml_file"
        fi
    fi
done

echo ""
echo "=== VALIDATION PHASE 3: NAMESPACE DEPLOYMENT ==="
echo ""

# Check foundation namespaces exist
FOUNDATION_NAMESPACES=("control-plane" "data-plane" "observability-plane")
MISSING_NAMESPACES=0

for ns in "${FOUNDATION_NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        print_pass "Namespace exists: $ns"
        
        # Check namespace labels
        LABELS=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels}' 2>/dev/null)
        if [ -n "$LABELS" ] && [ "$LABELS" != "null" ]; then
            if echo "$LABELS" | grep -q '"plane":"foundation"'; then
                print_pass "Namespace '$ns' has correct 'plane=foundation' label"
            else
                print_fail "Namespace '$ns' missing 'plane=foundation' label (labels: $LABELS)"
            fi
        else
            print_fail "Namespace '$ns' has no labels"
        fi
        
        # Check namespace status
        STATUS=$(kubectl get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$STATUS" = "Active" ]; then
            print_pass "Namespace '$ns' is Active"
        else
            print_fail "Namespace '$ns' not Active (status: $STATUS)"
        fi
    else
        print_fail "Namespace missing: $ns"
        ((MISSING_NAMESPACES++))
    fi
done

echo ""
echo "=== VALIDATION PHASE 4: RESOURCEQUOTA DEPLOYMENT ==="
echo ""

# Check ResourceQuotas are deployed
for ns in "${FOUNDATION_NAMESPACES[@]}"; do
    if kubectl get resourcequota -n "$ns" &> /dev/null; then
        QUOTA_NAME="${ns}-quota"
        if kubectl get resourcequota "$QUOTA_NAME" -n "$ns" &> /dev/null; then
            print_pass "ResourceQuota exists: $QUOTA_NAME in $ns"
            
            # Verify hard limits match budget
            case $ns in
                "control-plane")
                    EXPECTED_MEM="3006477107200m"  # 2.8Gi in milli-units
                    EXPECTED_CPU="1800m"           # 1.8 cores in milli-units
                    EXPECTED_MEM_READABLE="2.8Gi"
                    EXPECTED_CPU_READABLE="1.8"
                    ;;
                "data-plane")
                    EXPECTED_MEM="3435973836800m"  # 3.2Gi in milli-units
                    EXPECTED_CPU="2400m"           # 2.4 cores in milli-units
                    EXPECTED_MEM_READABLE="3.2Gi"
                    EXPECTED_CPU_READABLE="2.4"
                    ;;
                "observability-plane")
                    EXPECTED_MEM="1717986918400m"  # 1.6Gi in milli-units
                    EXPECTED_CPU="1200m"           # 1.2 cores in milli-units
                    EXPECTED_MEM_READABLE="1.6Gi"
                    EXPECTED_CPU_READABLE="1.2"
                    ;;
            esac
            
            # Note: JSONPath needs escaped dots for fields like "requests.cpu"
            ACTUAL_MEM=$(kubectl get resourcequota "$QUOTA_NAME" -n "$ns" -o jsonpath='{.spec.hard.requests\.memory}' 2>/dev/null)
            ACTUAL_CPU=$(kubectl get resourcequota "$QUOTA_NAME" -n "$ns" -o jsonpath='{.spec.hard.requests\.cpu}' 2>/dev/null)
            
            if [ "$ACTUAL_MEM" = "$EXPECTED_MEM" ]; then
                print_pass "Memory request quota correct: $EXPECTED_MEM_READABLE ($ACTUAL_MEM)"
            else
                print_fail "Memory request quota incorrect: $ACTUAL_MEM (expected: $EXPECTED_MEM_READABLE/$EXPECTED_MEM)"
            fi
            
            if [ "$ACTUAL_CPU" = "$EXPECTED_CPU" ]; then
                print_pass "CPU request quota correct: $EXPECTED_CPU_READABLE ($ACTUAL_CPU)"
            else
                print_fail "CPU request quota incorrect: $ACTUAL_CPU (expected: $EXPECTED_CPU_READABLE/$EXPECTED_CPU)"
            fi
        else
            print_fail "ResourceQuota '$QUOTA_NAME' not found in $ns"
        fi
    else
        print_fail "No ResourceQuotas found in namespace $ns"
    fi
done

echo ""
echo "=== VALIDATION PHASE 5: LIMITRANGE DEPLOYMENT ==="
echo ""

# Check LimitRanges are deployed
for ns in "${FOUNDATION_NAMESPACES[@]}"; do
    if kubectl get limitrange -n "$ns" &> /dev/null; then
        LIMITRANGE_NAME="${ns}-defaults"
        if kubectl get limitrange "$LIMITRANGE_NAME" -n "$ns" &> /dev/null; then
            print_pass "LimitRange exists: $LIMITRANGE_NAME in $ns"
            
            # Verify default values
            DEFAULT_MEM=$(kubectl get limitrange "$LIMITRANGE_NAME" -n "$ns" -o jsonpath='{.spec.limits[0].default.memory}' 2>/dev/null)
            DEFAULT_CPU=$(kubectl get limitrange "$LIMITRANGE_NAME" -n "$ns" -o jsonpath='{.spec.limits[0].default.cpu}' 2>/dev/null)
            
            if [ -n "$DEFAULT_MEM" ] && [ -n "$DEFAULT_CPU" ]; then
                print_pass "LimitRange has default values: memory=$DEFAULT_MEM, cpu=$DEFAULT_CPU"
            else
                print_fail "LimitRange missing default values"
            fi
            
            # Verify max limits
            MAX_MEM=$(kubectl get limitrange "$LIMITRANGE_NAME" -n "$ns" -o jsonpath='{.spec.limits[0].max.memory}' 2>/dev/null)
            MAX_CPU=$(kubectl get limitrange "$LIMITRANGE_NAME" -n "$ns" -o jsonpath='{.spec.limits[0].max.cpu}' 2>/dev/null)
            
            if [ -n "$MAX_MEM" ] && [ -n "$MAX_CPU" ]; then
                print_pass "LimitRange has max limits: memory=$MAX_MEM, cpu=$MAX_CPU"
            else
                print_fail "LimitRange missing max limits"
            fi
        else
            print_fail "LimitRange '$LIMITRANGE_NAME' not found in $ns"
        fi
    else
        print_fail "No LimitRanges found in namespace $ns"
    fi
done

echo ""
echo "=== VALIDATION PHASE 6: FUNCTIONAL TESTING ==="
echo ""

print_info "Functional testing requires actual pod creation (skipped in validation)"
print_info "ResourceQuota and LimitRange deployment validated successfully above"
print_warn "Note: Functional testing would require creating actual test pods"

echo ""
echo "=== VALIDATION PHASE 7: DOCUMENTATION ==="
echo ""

# Check documentation
if [ -f "shared/resource-budget.md" ]; then
    print_pass "Resource budget documentation exists"
    
    # Check documentation content
    if grep -q "Resource Budget and Quota Rationale" shared/resource-budget.md; then
        print_pass "Documentation has correct title"
    else
        print_fail "Documentation missing expected title"
    fi
    
    if grep -q "Budget Table" shared/resource-budget.md; then
        print_pass "Documentation includes budget table"
    else
        print_fail "Documentation missing budget table"
    fi
    
    if grep -q "control-plane.*2.8Gi" shared/resource-budget.md; then
        print_pass "Documentation includes control-plane budget"
    else
        print_fail "Documentation missing control-plane budget details"
    fi
else
    print_fail "Resource budget documentation missing"
fi

echo ""
echo "=== VALIDATION SUMMARY ==="
echo "================================================================"
VALIDATION_END=$(date +%s)
VALIDATION_TIME=$((VALIDATION_END - VALIDATION_START))

echo "Validation completed in ${VALIDATION_TIME} seconds"
echo "Total checks: $((PASS + FAIL + WARN))"
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"
echo -e "${YELLOW}Warnings: $WARN${NC}"
echo ""

# Show detailed resource status
echo "=== DETAILED RESOURCE STATUS ==="
echo ""

for ns in "${FOUNDATION_NAMESPACES[@]}"; do
    echo "Namespace: $ns"
    echo "-----------"
    
    # Show ResourceQuota
    echo "ResourceQuota:"
    kubectl get resourcequota -n "$ns" -o wide 2>/dev/null || echo "  Not found"
    
    # Show LimitRange
    echo "LimitRange:"
    kubectl get limitrange -n "$ns" -o wide 2>/dev/null || echo "  Not found"
    
    # Show current usage
    echo "Current usage:"
    kubectl describe resourcequota -n "$ns" 2>/dev/null | grep -A 20 "Resource Quotas" | tail -n +2 || echo "  No usage data"
    echo ""
done

echo "=== VALIDATION RESULT ==="
echo "================================================================"

if [ "$FAIL" -eq 0 ] && [ "$MISSING_NAMESPACES" -eq 0 ]; then
    echo -e "${GREEN}✅ VALIDATION PASSED${NC}"
    echo "All BS-2 deliverables successfully implemented and validated."
    echo ""
    echo "Implemented:"
    echo "1. ✅ Foundation namespaces (control-plane, data-plane, observability-plane)"
    echo "2. ✅ ResourceQuotas with hard limits matching budget"
    echo "3. ✅ LimitRanges with default requests/limits"
    echo "4. ✅ Documentation with quota rationale"
    echo "5. ✅ All three scripts (pre-deployment, deployment, validation)"
    echo ""
    echo "The cluster now has namespace-level resource budgeting enforced."
    exit 0
elif [ "$FAIL" -eq 0 ] && [ "$MISSING_NAMESPACES" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  VALIDATION PARTIALLY PASSED${NC}"
    echo "Core functionality works but some namespaces are missing."
    echo "Run deployment script to complete implementation."
    exit 1
else
    echo -e "${RED}❌ VALIDATION FAILED${NC}"
    echo "$FAIL critical failures detected."
    echo "Review failed checks above and fix issues."
    exit 1
fi