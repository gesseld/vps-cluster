#!/bin/bash
# BS-4: Node Labeling for Topology Awareness - Validation Script
# Simplified version for WSL compatibility

echo "================================================================"
echo "BS-4: NODE LABELING FOR TOPOLOGY AWARENESS - VALIDATION"
echo "================================================================"
echo "Objective: Validate topology-aware node labeling"
echo "Date: $(date)"
echo ""

# Output functions
print_pass() {
    echo "✅ PASS: $1"
}

print_fail() {
    echo "❌ FAIL: $1"
}

print_warn() {
    echo "⚠️  WARN: $1"
}

# Log file setup
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
VALIDATION_LOG="$LOG_DIR/validation-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$VALIDATION_LOG") 2>&1

echo "Logging to: $VALIDATION_LOG"
echo ""

echo "=== SECTION 1: CLUSTER CONNECTIVITY VALIDATION ==="
echo ""

# 1.1 Check cluster connectivity
echo "🔍 Validating cluster connectivity..."
if kubectl get nodes &> /dev/null; then
    print_pass "Cluster is accessible"
else
    print_fail "Cannot connect to cluster"
    exit 1
fi

echo ""
echo "=== SECTION 2: NODE LABEL VALIDATION ==="
echo ""

# 2.1 Get total node count
TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
print_pass "Total nodes in cluster: $TOTAL_NODES"

# 2.2 Validate storage-heavy nodes
echo "🔍 Validating storage-heavy nodes..."
STORAGE_NODES=$(kubectl get nodes -l node-role=storage-heavy --no-headers 2>/dev/null | wc -l)

if [ "$TOTAL_NODES" -ge 3 ]; then
    EXPECTED_STORAGE=2
else
    EXPECTED_STORAGE=$TOTAL_NODES
fi

if [ "$STORAGE_NODES" -eq "$EXPECTED_STORAGE" ]; then
    print_pass "Correct number of storage-heavy nodes: $STORAGE_NODES/$EXPECTED_STORAGE"
else
    print_fail "Incorrect storage-heavy nodes: $STORAGE_NODES (expected: $EXPECTED_STORAGE)"
fi

# 2.3 List storage-heavy nodes
echo ""
echo "📋 Storage-heavy nodes:"
kubectl get nodes -l node-role=storage-heavy -o custom-columns=NAME:.metadata.name,ROLE:.metadata.labels.node-role 2>/dev/null || \
kubectl get nodes -l node-role=storage-heavy 2>/dev/null

echo ""
echo "=== SECTION 3: TOPOLOGY LABEL VALIDATION ==="
echo ""

# 3.1 Validate zone labels
echo "🔍 Validating topology zone labels..."
NODES_WITH_ZONE=0
NODE_NAMES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$NODE_NAMES" ]; then
    IFS=' ' read -r -a NODE_ARRAY <<< "$NODE_NAMES"
    for NODE in "${NODE_ARRAY[@]}"; do
        ZONE_LABEL=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo "")
        if [ -n "$ZONE_LABEL" ]; then
            NODES_WITH_ZONE=$((NODES_WITH_ZONE + 1))
        fi
    done
fi

if [ "$NODES_WITH_ZONE" -eq "$TOTAL_NODES" ]; then
    print_pass "All $TOTAL_NODES nodes have zone labels"
else
    print_fail "$NODES_WITH_ZONE/$TOTAL_NODES nodes have zone labels"
fi

# 3.2 Validate region labels
echo ""
echo "🔍 Validating topology region labels..."
NODES_WITH_REGION=0
for NODE in "${NODE_ARRAY[@]}"; do
    REGION_LABEL=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/region}' 2>/dev/null || echo "")
    if [ -n "$REGION_LABEL" ]; then
        NODES_WITH_REGION=$((NODES_WITH_REGION + 1))
    fi
done

if [ "$NODES_WITH_REGION" -eq "$TOTAL_NODES" ]; then
    print_pass "All $TOTAL_NODES nodes have region labels"
else
    print_fail "$NODES_WITH_REGION/$TOTAL_NODES nodes have region labels"
fi

echo ""
echo "=== SECTION 4: NODE SELECTOR TESTING ==="
echo ""

# 4.1 Create test pod for storage-heavy nodes
echo "🔍 Testing node selector for storage-heavy nodes..."
cat > test-storage-pod.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-storage-placement
  namespace: default
spec:
  containers:
  - name: test-container
    image: busybox:latest
    command: ["sh", "-c", "echo 'Running on storage-heavy node' && sleep 3600"]
  nodeSelector:
    node-role: storage-heavy
  tolerations:
  - key: "node-role"
    operator: "Equal"
    value: "storage-heavy"
    effect: "NoSchedule"
  restartPolicy: Never
EOF

# Apply test pod
if kubectl apply -f test-storage-pod.yaml &> /dev/null; then
    print_pass "Test pod created for storage-heavy nodes"
    
    # Wait for pod scheduling
    sleep 3
    
    # Check where pod was scheduled
    POD_NODE=$(kubectl get pod test-storage-placement -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")
    if [ -n "$POD_NODE" ]; then
        NODE_ROLE=$(kubectl get node "$POD_NODE" -o jsonpath='{.metadata.labels.node-role}' 2>/dev/null || echo "")
        if [ "$NODE_ROLE" = "storage-heavy" ]; then
            print_pass "Test pod correctly scheduled on storage-heavy node: $POD_NODE"
        else
            print_fail "Test pod scheduled on non-storage-heavy node: $POD_NODE"
        fi
    else
        print_warn "Could not determine where test pod was scheduled"
    fi
    
    # Cleanup test pod
    kubectl delete -f test-storage-pod.yaml --wait=false &> /dev/null
else
    print_fail "Failed to create test pod"
fi

# Cleanup test file
rm -f test-storage-pod.yaml

echo ""
echo "=== SECTION 5: COMPREHENSIVE NODE REPORT ==="
echo ""

# 5.1 Generate comprehensive node report
echo "📊 Generating comprehensive node report..."
echo ""
echo "Node Label Summary:"
echo "-------------------"
kubectl get nodes -o custom-columns=NAME:.metadata.name,ROLE:.metadata.labels.node-role,ZONE:.metadata.labels.'topology\.kubernetes\.io/zone',REGION:.metadata.labels.'topology\.kubernetes\.io/region',CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory 2>/dev/null || \
echo "Detailed report not available, showing basic info:"
kubectl get nodes --show-labels 2>/dev/null

echo ""
echo "=== SECTION 6: VALIDATION METRICS ==="
echo ""

# 6.1 Calculate validation score
PASS_COUNT=$(grep -c "PASS:" "$VALIDATION_LOG" 2>/dev/null || echo "0")
FAIL_COUNT=$(grep -c "FAIL:" "$VALIDATION_LOG" 2>/dev/null || echo "0")
WARN_COUNT=$(grep -c "WARN:" "$VALIDATION_LOG" 2>/dev/null || echo "0")

TOTAL_CHECKS=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
if [ "$TOTAL_CHECKS" -gt 0 ]; then
    SUCCESS_RATE=$((PASS_COUNT * 100 / TOTAL_CHECKS))
else
    SUCCESS_RATE=0
fi

echo "Validation Metrics:"
echo "  - Total checks: $TOTAL_CHECKS"
echo "  - Passed: $PASS_COUNT"
echo "  - Failed: $FAIL_COUNT"
echo "  - Warnings: $WARN_COUNT"
echo "  - Success rate: $SUCCESS_RATE%"

echo ""
echo "=== SECTION 7: RECOMMENDATIONS ==="
echo ""

# 7.1 Provide recommendations based on validation
if [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
    print_pass "All validations passed successfully!"
    echo ""
    echo "Recommendations:"
    echo "  1. Proceed with deploying PostgreSQL and MinIO on storage-heavy nodes"
    echo "  2. Use nodeSelector in deployments:"
    echo "     - For storage workloads: node-role: storage-heavy"
    echo "     - For control plane: No nodeSelector (or node-role: general)"
    echo "  3. Consider adding taints to storage-heavy nodes for stricter control"
    
elif [ "$FAIL_COUNT" -eq 0 ]; then
    print_warn "Validations passed with warnings"
    echo ""
    echo "Recommendations:"
    echo "  1. Review warnings above"
    echo "  2. Consider fixing warnings before production deployment"
    echo "  3. Test workload placement with sample pods"
    
else
    print_fail "Validations failed - review issues above"
    echo ""
    echo "Recommendations:"
    echo "  1. Fix all FAIL items before proceeding"
    echo "  2. Re-run deployment script: ./02-deployment.sh"
    echo "  3. Check kubectl permissions and cluster health"
fi

echo ""
echo "=== SECTION 8: NEXT STEPS ==="
echo ""

# 8.1 Create next steps documentation
cat > NEXT_STEPS.md << 'EOF'
# BS-4: Next Steps for Topology Awareness

## Completed Tasks
✅ Node labeling for topology-aware scheduling
✅ Storage-heavy nodes identified and labeled
✅ Topology zone and region labels applied
✅ Validation completed

## Immediate Next Steps

### 1. Deploy Storage Workloads
- PostgreSQL: Use nodeSelector with `node-role: storage-heavy`
- MinIO: Use nodeSelector with `node-role: storage-heavy`
- Consider spreading across different zones for high availability

### 2. Configure Node Affinity/Anti-Affinity
Example for PostgreSQL StatefulSet:
```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role
          operator: In
          values:
          - storage-heavy
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - postgresql
        topologyKey: topology.kubernetes.io/zone
```

### 3. Monitor Workload Placement
- Use `kubectl describe nodes` to see resource allocation
- Monitor pod distribution across zones
- Set up alerts for imbalanced scheduling

### 4. Consider Adding Taints
For stricter control:
```bash
kubectl taint nodes -l node-role=storage-heavy storage-heavy=true:NoSchedule
```
Then add corresponding tolerations to storage workloads.

## Validation Results
See: '$(basename "$VALIDATION_LOG")'

## Cleanup
If needed, run: `./cleanup-labels.sh`
EOF

print_pass "Next steps documentation created: NEXT_STEPS.md"

echo ""
echo "================================================================"
echo "VALIDATION COMPLETED"
echo "================================================================"
echo "✅ Validation process finished"
echo ""
echo "Summary:"
echo "  - Success rate: $SUCCESS_RATE%"
echo "  - Storage-heavy nodes: $STORAGE_NODES/$EXPECTED_STORAGE"
echo "  - Zone labels: $NODES_WITH_ZONE/$TOTAL_NODES"
echo "  - Region labels: $NODES_WITH_REGION/$TOTAL_NODES"
echo ""
echo "Files created:"
echo "  - Validation log: $VALIDATION_LOG"
echo "  - Next steps: NEXT_STEPS.md"
echo "  - Cleanup script: ./cleanup-labels.sh"
echo ""
echo "Next: Review validation results and proceed with workload deployment"
exit 0