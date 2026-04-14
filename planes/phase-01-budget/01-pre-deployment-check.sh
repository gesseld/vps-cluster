#!/bin/bash
# BS-2: ResourceQuotas + LimitRanges Pre-Deployment Check
# Validates all prerequisites for namespace resource budgeting implementation

set -euo pipefail

echo "================================================================"
echo "BS-2: RESOURCEQUOTAS + LIMITRANGES PRE-DEPLOYMENT CHECK"
echo "================================================================"
echo "Date: $(date)"
echo "Task: Validate prerequisites for namespace resource budgeting"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

print_pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; PASS=$((PASS + 1)); }
print_fail() { echo -e "${RED}❌ FAIL${NC}: $1"; FAIL=$((FAIL + 1)); }
print_warn() { echo -e "${YELLOW}⚠️  WARN${NC}: $1"; WARN=$((WARN + 1)); }

echo "=== CLUSTER CONNECTIVITY CHECKS ==="
echo ""

# Check kubectl connectivity
if kubectl get nodes &> /dev/null; then
    NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c Ready 2>/dev/null)
    if [ "$READY" -eq "$NODES" ] && [ "$NODES" -gt 0 ]; then
        print_pass "K3s cluster: $NODES nodes, all Ready"
        kubectl get nodes 2>/dev/null || true
    else
        print_fail "K3s cluster: $NODES nodes, $READY Ready"
    fi
else
    print_fail "Cannot connect to K3s cluster"
    exit 1
fi

echo ""
echo "=== KUBERNETES API CHECKS ==="
echo ""

# Check API server version
if kubectl version 2>/dev/null | grep -q "Server Version:"; then
    print_pass "Kubernetes API server is accessible"
else
    print_fail "Cannot access Kubernetes API server"
fi

# Check ResourceQuota API availability
if kubectl api-resources | grep -q "resourcequotas"; then
    print_pass "ResourceQuota API is available"
else
    print_fail "ResourceQuota API not available"
fi

# Check LimitRange API availability
if kubectl api-resources | grep -q "limitranges"; then
    print_pass "LimitRange API is available"
else
    print_fail "LimitRange API not available"
fi

echo ""
echo "=== NAMESPACE CHECKS ==="
echo ""

# Check if foundation namespaces already exist
EXISTING_NAMESPACES=0
for ns in control-plane data-plane observability-plane; do
    if kubectl get namespace "$ns" &> /dev/null; then
        print_warn "Namespace '$ns' already exists (will be reused)"
        ((EXISTING_NAMESPACES++))
    else
        print_pass "Namespace '$ns' does not exist (will be created)"
    fi
done

echo ""
echo "=== RESOURCE AVAILABILITY CHECKS ==="
echo ""

# Check cluster resource capacity
if kubectl describe nodes 2>/dev/null | head -100 | grep -q "Allocatable:"; then
    print_pass "Cluster has allocatable resources"
    
    # Get total allocatable memory and CPU from first node only (to avoid hanging)
    NODE_INFO=$(kubectl describe nodes 2>/dev/null | head -100)
    TOTAL_MEM=$(echo "$NODE_INFO" | grep -A 5 "Allocatable:" | grep "memory" | head -1 | awk '{print $2}' | sed 's/Ki//')
    TOTAL_CPU=$(echo "$NODE_INFO" | grep -A 5 "Allocatable:" | grep "cpu" | head -1 | awk '{print $2}' | sed 's/m//')
    
    if [ -n "$TOTAL_MEM" ] && [[ "$TOTAL_MEM" =~ ^[0-9]+$ ]] && [ "$TOTAL_MEM" -gt 0 ] 2>/dev/null; then
        # Convert to Gi for comparison (Ki to Gi: divide by 1024*1024)
        TOTAL_MEM_GI=$((TOTAL_MEM / 1048576)) || TOTAL_MEM_GI=0
        if [ "$TOTAL_MEM_GI" -ge 8 ] 2>/dev/null; then
            print_pass "Cluster has sufficient memory ($TOTAL_MEM_GI Gi available)"
        else
            print_warn "Cluster memory may be limited ($TOTAL_MEM_GI Gi available)"
        fi
    fi
else
    print_warn "Cannot determine cluster resource capacity"
fi

echo ""
echo "=== YAML FILE CHECKS ==="
echo ""

# Check if required YAML files exist
REQUIRED_FILES=(
    "shared/foundation-namespaces.yaml"
    "shared/resource-quotas.yaml"
    "shared/limit-ranges.yaml"
    "shared/resource-budget.md"
)

MISSING_FILES=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_pass "Required file exists: $file"
    else
        print_fail "Missing required file: $file"
        ((MISSING_FILES++))
    fi
done

echo ""
echo "=== PERMISSION CHECKS ==="
echo ""

# Check if we have permission to create resources
if kubectl auth can-i create namespace 2>/dev/null | grep -q "yes"; then
    print_pass "Has permission to create namespaces"
else
    print_fail "No permission to create namespaces"
fi

if kubectl auth can-i create resourcequota 2>/dev/null | grep -q "yes"; then
    print_pass "Has permission to create ResourceQuotas"
else
    print_fail "No permission to create ResourceQuotas"
fi

if kubectl auth can-i create limitrange 2>/dev/null | grep -q "yes"; then
    print_pass "Has permission to create LimitRanges"
else
    print_fail "No permission to create LimitRanges"
fi

echo ""
echo "=== SUMMARY ==="
echo "================================================================"
echo "Total checks: $((PASS + FAIL + WARN))"
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"
echo -e "${YELLOW}Warnings: $WARN${NC}"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}❌ PRE-DEPLOYMENT CHECK FAILED${NC}"
    echo "Critical failures detected. Please fix issues before proceeding."
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  PRE-DEPLOYMENT CHECK PASSED WITH WARNINGS${NC}"
    echo "Proceed with deployment, but review warnings."
    exit 0
else
    echo -e "${GREEN}✅ PRE-DEPLOYMENT CHECK PASSED${NC}"
    echo "All prerequisites satisfied. Ready for deployment."
    exit 0
fi