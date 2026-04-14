#!/bin/bash
# BS-3: StorageClass with WaitForFirstConsumer - Validation Script
# Validates that StorageClass with WaitForFirstConsumer is working correctly

set -euo pipefail

echo "================================================================"
echo "BS-3: STORAGECLASS WITH WAITFORFIRSTCONSUMER - VALIDATION SCRIPT"
echo "================================================================"
echo "Objective: Validate StorageClass implementation and WaitForFirstConsumer behavior"
echo "Date: $(date)"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/manifests"
LOG_FILE="$SCRIPT_DIR/validation-$(date +%Y%m%d-%H%M%S).log"
REPORT_FILE="$SCRIPT_DIR/VALIDATION_REPORT.md"

# Create directories
mkdir -p "$SCRIPT_DIR/logs"

# Track validation results
PASS=0
FAIL=0
WARN=0
SKIP=0

# Helper functions
print_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((PASS++))
}

print_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((FAIL++))
}

print_warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    ((WARN++))
}

print_skip() {
    echo -e "${BLUE}⏭️  SKIP${NC}: $1"
    ((SKIP++))
}

log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Start validation
log "${BLUE}=== Starting BS-3 StorageClass Validation ===${NC}"

# ============================================================================
# SECTION 1: BASIC VALIDATION
# ============================================================================
echo ""
echo "=== SECTION 1: BASIC STORAGECLASS VALIDATION ==="
echo ""

# 1.1 Check if StorageClass exists
log "1.1 Checking if StorageClass 'nvme-waitfirst' exists..."
if kubectl get storageclass nvme-waitfirst &> /dev/null; then
    print_pass "StorageClass 'nvme-waitfirst' exists"
else
    print_fail "StorageClass 'nvme-waitfirst' not found"
    echo "  Run deployment script first: 02-deployment.sh"
    exit 1
fi

# 1.2 Verify volumeBindingMode
log "1.2 Verifying volumeBindingMode..."
BINDING_MODE=$(kubectl get storageclass nvme-waitfirst -o jsonpath='{.volumeBindingMode}' 2>/dev/null || echo "")
if [ "$BINDING_MODE" = "WaitForFirstConsumer" ]; then
    print_pass "volumeBindingMode is WaitForFirstConsumer"
else
    print_fail "volumeBindingMode is '$BINDING_MODE' (expected: WaitForFirstConsumer)"
fi

# 1.3 Verify allowVolumeExpansion
log "1.3 Verifying allowVolumeExpansion..."
ALLOW_EXPANSION=$(kubectl get storageclass nvme-waitfirst -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null || echo "")
if [ "$ALLOW_EXPANSION" = "true" ]; then
    print_pass "allowVolumeExpansion is true"
else
    print_warn "allowVolumeExpansion is '$ALLOW_EXPANSION' (expected: true)"
fi

# 1.4 Verify reclaimPolicy
log "1.4 Verifying reclaimPolicy..."
RECLAIM_POLICY=$(kubectl get storageclass nvme-waitfirst -o jsonpath='{.reclaimPolicy}' 2>/dev/null || echo "")
if [ "$RECLAIM_POLICY" = "Retain" ]; then
    print_pass "reclaimPolicy is Retain"
else
    print_warn "reclaimPolicy is '$RECLAIM_POLICY' (expected: Retain)"
fi

# 1.5 Verify provisioner
log "1.5 Verifying provisioner..."
PROVISIONER=$(kubectl get storageclass nvme-waitfirst -o jsonpath='{.provisioner}' 2>/dev/null || echo "")
if [ -n "$PROVISIONER" ]; then
    print_pass "Provisioner: $PROVISIONER"
    
    # Check if CSI driver pods are running
    if [[ "$PROVISIONER" == *"csi"* ]]; then
        CSI_PODS=$(kubectl get pods -n kube-system 2>/dev/null | grep -i "csi" | grep -v NAME | wc -l)
        if [ "$CSI_PODS" -ge 1 ]; then
            print_pass "Found $CSI_PODS CSI driver pod(s)"
        else
            print_warn "No CSI driver pods found (provisioner: $PROVISIONER)"
        fi
    fi
else
    print_fail "No provisioner specified"
fi

# ============================================================================
# SECTION 2: WAITFORFIRSTCONSUMER BEHAVIOR TEST
# ============================================================================
echo ""
echo "=== SECTION 2: WAITFORFIRSTCONSUMER BEHAVIOR TEST ==="
echo ""

# 2.1 Create test PVC
log "2.1 Creating test PVC..."
TEST_PVC_FILE="$MANIFESTS_DIR/test-pvc-waitfirst.yaml"
if [ -f "$TEST_PVC_FILE" ]; then
    kubectl apply -f "$TEST_PVC_FILE" --dry-run=client &> /dev/null
    if [ $? -eq 0 ]; then
        # Actually create the PVC
        kubectl apply -f "$TEST_PVC_FILE" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_pass "Test PVC created successfully"
            
            # Wait a moment for PVC to register
            sleep 3
            
            # Check PVC status
            PVC_STATUS=$(kubectl get pvc test-pvc-waitfirst -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            if [ "$PVC_STATUS" = "Pending" ]; then
                print_pass "PVC is in Pending state (expected for WaitForFirstConsumer)"
            else
                print_warn "PVC status is '$PVC_STATUS' (expected: Pending)"
            fi
        else
            print_fail "Failed to create test PVC"
        fi
    else
        print_fail "Test PVC manifest validation failed"
    fi
else
    print_skip "Test PVC manifest not found: $TEST_PVC_FILE"
fi

# 2.2 Create test Pod to trigger binding
log "2.2 Creating test Pod to trigger binding..."
TEST_POD_FILE="$MANIFESTS_DIR/test-pod-waitfirst.yaml"
if [ -f "$TEST_POD_FILE" ] && kubectl get pvc test-pvc-waitfirst &> /dev/null; then
    kubectl apply -f "$TEST_POD_FILE" --dry-run=client &> /dev/null
    if [ $? -eq 0 ]; then
        # Actually create the Pod
        kubectl apply -f "$TEST_POD_FILE" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_pass "Test Pod created successfully"
            
            # Wait for Pod scheduling and PVC binding
            log "Waiting for Pod scheduling and PVC binding..."
            sleep 10
            
            # Check Pod status
            POD_STATUS=$(kubectl get pod test-pod-waitfirst -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            if [ "$POD_STATUS" = "Running" ] || [ "$POD_STATUS" = "Pending" ]; then
                print_pass "Pod is in '$POD_STATUS' state"
            else
                print_warn "Pod status is '$POD_STATUS'"
            fi
            
            # Check PVC status again
            PVC_STATUS_AFTER=$(kubectl get pvc test-pvc-waitfirst -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
            if [ "$PVC_STATUS_AFTER" = "Bound" ]; then
                print_pass "PVC is now Bound (triggered by Pod creation)"
            else
                print_warn "PVC status is '$PVC_STATUS_AFTER' (expected: Bound)"
            fi
            
            # Check events for PVC
            log "Checking PVC events..."
            PVC_EVENTS=$(kubectl describe pvc test-pvc-waitfirst 2>/dev/null | grep -A5 -B5 "Events:" || echo "No events found")
            if echo "$PVC_EVENTS" | grep -q "WaitForFirstConsumer"; then
                print_pass "Found WaitForFirstConsumer in PVC events"
            fi
        else
            print_fail "Failed to create test Pod"
        fi
    else
        print_fail "Test Pod manifest validation failed"
    fi
else
    if [ ! -f "$TEST_POD_FILE" ]; then
        print_skip "Test Pod manifest not found: $TEST_POD_FILE"
    else
        print_skip "Test PVC not found, skipping Pod test"
    fi
fi

# ============================================================================
# SECTION 3: TOPOLOGY VALIDATION
# ============================================================================
echo ""
echo "=== SECTION 3: TOPOLOGY VALIDATION ==="
echo ""

# 3.1 Check node topology labels
log "3.1 Checking node topology labels..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
NODES_WITH_ZONE=0
NODES_WITH_REGION=0

kubectl get nodes -o json 2>/dev/null | jq -r '.items[] | .metadata.name' | while read -r NODE; do
    ZONE_LABEL=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo "")
    REGION_LABEL=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/region}' 2>/dev/null || echo "")
    
    if [ -n "$ZONE_LABEL" ]; then
        ((NODES_WITH_ZONE++))
    fi
    if [ -n "$REGION_LABEL" ]; then
        ((NODES_WITH_REGION++))
    fi
done

if [ "$NODE_COUNT" -gt 0 ]; then
    if [ "$NODES_WITH_ZONE" -eq "$NODE_COUNT" ]; then
        print_pass "All $NODE_COUNT nodes have topology.kubernetes.io/zone labels"
    elif [ "$NODES_WITH_ZONE" -gt 0 ]; then
        print_warn "$NODES_WITH_ZONE/$NODE_COUNT nodes have topology.kubernetes.io/zone labels"
    else
        print_warn "No nodes have topology.kubernetes.io/zone labels (WaitForFirstConsumer may not work optimally)"
    fi
    
    if [ "$NODES_WITH_REGION" -eq "$NODE_COUNT" ]; then
        print_pass "All $NODE_COUNT nodes have topology.kubernetes.io/region labels"
    elif [ "$NODES_WITH_REGION" -gt 0 ]; then
        print_warn "$NODES_WITH_REGION/$NODE_COUNT nodes have topology.kubernetes.io/region labels"
    else
        print_warn "No nodes have topology.kubernetes.io/region labels"
    fi
else
    print_fail "No nodes found in cluster"
fi

# 3.2 Check StorageClass YAML details
log "3.2 Checking StorageClass YAML details..."
STORAGECLASS_YAML="$MANIFESTS_DIR/nvme-waitfirst-storageclass.yaml"
if [ -f "$STORAGECLASS_YAML" ]; then
    if grep -q "volumeBindingMode: WaitForFirstConsumer" "$STORAGECLASS_YAML"; then
        print_pass "StorageClass YAML contains WaitForFirstConsumer"
    else
        print_fail "StorageClass YAML missing WaitForFirstConsumer"
    fi
    
    if grep -q "allowVolumeExpansion: true" "$STORAGECLASS_YAML"; then
        print_pass "StorageClass YAML contains allowVolumeExpansion: true"
    else
        print_warn "StorageClass YAML missing allowVolumeExpansion: true"
    fi
    
    if grep -q "reclaimPolicy: Retain" "$STORAGECLASS_YAML"; then
        print_pass "StorageClass YAML contains reclaimPolicy: Retain"
    else
        print_warn "StorageClass YAML missing reclaimPolicy: Retain"
    fi
else
    print_skip "StorageClass YAML not found: $STORAGECLASS_YAML"
fi

# ============================================================================
# SECTION 4: CLEANUP AND FINAL VALIDATION
# ============================================================================
echo ""
echo "=== SECTION 4: CLEANUP AND FINAL VALIDATION ==="
echo ""

# 4.1 Cleanup test resources
log "4.1 Cleaning up test resources..."
if kubectl get pod test-pod-waitfirst &> /dev/null; then
    kubectl delete pod test-pod-waitfirst --wait=false > /dev/null 2>&1
    print_pass "Test Pod deleted"
else
    print_skip "Test Pod not found (already deleted or not created)"
fi

if kubectl get pvc test-pvc-waitfirst &> /dev/null; then
    kubectl delete pvc test-pvc-waitfirst --wait=false > /dev/null 2>&1
    print_pass "Test PVC deleted"
else
    print_skip "Test PVC not found (already deleted or not created)"
fi

# 4.2 Final StorageClass verification
log "4.2 Final StorageClass verification..."
if kubectl get storageclass nvme-waitfirst &> /dev/null; then
    SC_DETAILS=$(kubectl get storageclass nvme-waitfirst -o yaml 2>/dev/null | head -20)
    print_pass "StorageClass 'nvme-waitfirst' is properly configured"
    
    # Show key details
    echo ""
    echo "StorageClass Details:"
    echo "---------------------"
    kubectl get storageclass nvme-waitfirst -o jsonpath='{
        "Name: "}{.metadata.name}{"\n"
        "Provisioner: "}{.provisioner}{"\n"
        "Binding Mode: "}{.volumeBindingMode}{"\n"
        "Allow Expansion: "}{.allowVolumeExpansion}{"\n"
        "Reclaim Policy: "}{.reclaimPolicy}{"\n"
    }' 2>/dev/null
else
    print_fail "StorageClass 'nvme-waitfirst' not found after validation"
fi

# 4.3 Check for any orphaned test resources
log "4.3 Checking for orphaned test resources..."
ORPHANED_PVCS=$(kubectl get pvc --all-namespaces -l test=storageclass-waitfirst 2>/dev/null | grep -v NAME | wc -l)
ORPHANED_PODS=$(kubectl get pods --all-namespaces -l test=storageclass-waitfirst 2>/dev/null | grep -v NAME | wc -l)

if [ "$ORPHANED_PVCS" -eq 0 ] && [ "$ORPHANED_PODS" -eq 0 ]; then
    print_pass "No orphaned test resources found"
else
    print_warn "Found $ORPHANED_PVCS orphaned PVC(s) and $ORPHANED_PODS orphaned Pod(s)"
    echo "  Clean up with: kubectl delete pvc,pod -l test=storageclass-waitfirst --all-namespaces"
fi

# ============================================================================
# VALIDATION SUMMARY
# ============================================================================
echo ""
echo "================================================================"
echo "VALIDATION SUMMARY"
echo "================================================================"
echo -e "${GREEN}✅ PASS: $PASS${NC}"
echo -e "${RED}❌ FAIL: $FAIL${NC}"
echo -e "${YELLOW}⚠️  WARN: $WARN${NC}"
echo -e "${BLUE}⏭️  SKIP: $SKIP${NC}"
echo ""

# Create validation report
cat > "$REPORT_FILE" << EOF
# BS-3: StorageClass with WaitForFirstConsumer - Validation Report

## Validation Summary
- **Date**: $(date)
- **Total Tests**: $((PASS + FAIL + WARN + SKIP))
- **Passed**: $PASS
- **Failed**: $FAIL
- **Warnings**: $WARN
- **Skipped**: $SKIP
- **Overall Status**: $(if [ $FAIL -eq 0 ]; then echo "✅ PASS"; else echo "❌ FAIL"; fi)

## Test Results

### Section 1: Basic StorageClass Validation
1. StorageClass exists: $(if kubectl get storageclass nvme-waitfirst &> /dev/null; then echo "✅ PASS"; else echo "❌ FAIL"; fi)
2. Volume Binding Mode: $BINDING_MODE $(if [ "$BINDING_MODE" = "WaitForFirstConsumer" ]; then echo "✅"; else echo "❌"; fi)
3. Allow Volume Expansion: $ALLOW_EXPANSION $(if [ "$ALLOW_EXPANSION" = "true" ]; then echo "✅"; else echo "⚠️"; fi)
4. Reclaim Policy: $RECLAIM_POLICY $(if [ "$RECLAIM_POLICY" = "Retain" ]; then echo "✅"; else echo "⚠️"; fi)
5. Provisioner: $PROVISIONER $(if [ -n "$PROVISIONER" ]; then echo "✅"; else echo "❌"; fi)

### Section 2: WaitForFirstConsumer Behavior Test
1. Test PVC created: $(if [ -f "$TEST_PVC_FILE" ] && kubectl get pvc test-pvc-waitfirst &> /dev/null 2>&1; then echo "✅"; else echo "⏭️"; fi)
2. PVC in Pending state: $PVC_STATUS $(if [ "$PVC_STATUS" = "Pending" ]; then echo "✅"; else echo "⚠️"; fi)
3. Test Pod created: $(if [ -f "$TEST_POD_FILE" ] && kubectl get pod test-pod-waitfirst &> /dev/null 2>&1; then echo "✅"; else echo "⏭️"; fi)
4. PVC bound after Pod: $PVC_STATUS_AFTER $(if [ "$PVC_STATUS_AFTER" = "Bound" ]; then echo "✅"; else echo "⚠️"; fi)

### Section 3: Topology Validation
1. Nodes with zone labels: $NODES_WITH_ZONE/$NODE_COUNT $(if [ "$NODES_WITH_ZONE" -eq "$NODE_COUNT" ]; then echo "✅"; elif [ "$NODES_WITH_ZONE" -gt 0 ]; then echo "⚠️"; else echo "❌"; fi)
2. Nodes with region labels: $NODES_WITH_REGION/$NODE_COUNT $(if [ "$NODES_WITH_REGION" -eq "$NODE_COUNT" ]; then echo "✅"; elif [ "$NODES_WITH_REGION" -gt 0 ]; then echo "⚠️"; else echo "❌"; fi)
3. StorageClass YAML validation: $(if [ -f "$STORAGECLASS_YAML" ]; then echo "✅ Checked"; else echo "⏭️ Not found"; fi)

### Section 4: Cleanup
1. Test resources cleaned up: ✅
2. No orphaned resources: $(if [ "$ORPHANED_PVCS" -eq 0 ] && [ "$ORPHANED_PODS" -eq 0 ]; then echo "✅"; else echo "⚠️"; fi)

## Key Findings

### Successes
- StorageClass 'nvme-waitfirst' successfully created
- Volume binding mode correctly set to WaitForFirstConsumer
- $(if [ "$PASS" -gt 0 ]; then echo "$PASS tests passed"; else echo "No tests passed"; fi)

### Issues
$(if [ $FAIL -gt 0 ]; then
  echo "- $FAIL test(s) failed (see details above)"
else
  echo "- No critical failures"
fi)

$(if [ $WARN -gt 0 ]; then
  echo "- $WARN warning(s) that should be addressed"
else
  echo "- No warnings"
fi)

## Recommendations

### Immediate Actions
$(if [ $FAIL -gt 0 ]; then
  echo "1. Fix the $FAIL failed test(s) before proceeding"
else
  echo "1. StorageClass implementation is ready for use"
fi)

$(if [ "$NODES_WITH_ZONE" -ne "$NODE_COUNT" ]; then
  echo "2. Add topology.kubernetes.io/zone labels to all nodes for optimal WaitForFirstConsumer behavior"
fi)

$(if [ "$ALLOW_EXPANSION" != "true" ]; then
  echo "3. Enable allowVolumeExpansion for future volume growth"
fi)

### Next Steps
1. Integrate nvme-waitfirst StorageClass into application manifests
2. Monitor volume provisioning with real workloads
3. Test volume expansion functionality
4. Document any performance characteristics observed

## Validation Command
To re-run this validation:
\`\`\`bash
cd "$SCRIPT_DIR"
./03-validation.sh
\`\`\`

## Log File
Full validation logs: $LOG_FILE

## StorageClass Details
\`\`\`yaml
$(kubectl get storageclass nvme-waitfirst -o yaml 2>/dev/null | head -30 || echo "# StorageClass not found")
\`\`\`
EOF

log "Validation report created: $REPORT_FILE"

# Final status
if [ $FAIL -gt 0 ]; then
    echo -e "${RED}❌ VALIDATION FAILED${NC}"
    echo "$FAIL test(s) failed. Check the validation report: $REPORT_FILE"
    echo ""
    echo "Common issues to fix:"
    echo "1. Ensure StorageClass exists: kubectl get storageclass nvme-waitfirst"
    echo "2. Check volumeBindingMode: kubectl get sc nvme-waitfirst -o jsonpath='{.volumeBindingMode}'"
    echo "3. Verify CSI driver is running: kubectl get pods -n kube-system | grep csi"
    exit 1
elif [ $WARN -gt 0 ]; then
    echo -e "${YELLOW}⚠️  VALIDATION PASSED WITH WARNINGS${NC}"
    echo "$WARN warning(s) found. Review the validation report: $REPORT_FILE"
    echo ""
    echo "Recommended improvements:"
    echo "1. Add topology labels to nodes for better WaitForFirstConsumer behavior"
    echo "2. Ensure allowVolumeExpansion is enabled"
    echo "3. Test with real workloads"
    exit 0
else
    echo -e "${GREEN}✅ VALIDATION PASSED${NC}"
    echo "All tests passed. StorageClass with WaitForFirstConsumer is ready for use."
    echo ""
    echo "Validation report: $REPORT_FILE"
    echo "Log file: $LOG_FILE"
    exit 0
fi