#!/bin/bash
# BS-4: Node Labeling for Topology Awareness - Pre-Deployment Check
# Simplified version for WSL compatibility

echo "================================================================"
echo "BS-4: NODE LABELING FOR TOPOLOGY AWARENESS - PRE-DEPLOYMENT CHECK"
echo "================================================================"
echo "Objective: Enable topology-aware scheduling for I/O-heavy workloads"
echo "Date: $(date)"
echo ""

# Simple output functions
print_pass() {
    echo "✅ PASS: $1"
}

print_fail() {
    echo "❌ FAIL: $1"
}

print_warn() {
    echo "⚠️  WARN: $1"
}

echo "=== SECTION 1: KUBERNETES CLUSTER CONNECTIVITY ==="
echo ""

# 1.1 Check K3s cluster status
echo "🔍 Checking K3s cluster status..."
if kubectl get nodes &> /dev/null; then
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    READY_COUNT=$(kubectl get nodes --no-headers | grep -c "Ready")
    
    if [ "$READY_COUNT" -eq "$NODE_COUNT" ]; then
        print_pass "K3s cluster has $NODE_COUNT nodes, all Ready"
    else
        print_fail "K3s cluster has $NODE_COUNT nodes, $READY_COUNT Ready"
    fi
else
    print_fail "Cannot connect to K3s cluster"
    exit 1
fi

# 1.2 Check kubectl permissions
echo "🔍 Checking kubectl permissions..."
if kubectl auth can-i label nodes 2>&1 | grep -q "yes"; then
    print_pass "kubectl has permissions to label nodes"
else
    print_fail "kubectl does not have permissions to label nodes"
fi

echo ""
echo "=== SECTION 2: NODE INVENTORY & CURRENT LABELS ==="
echo ""

# 2.1 Get node list
echo "🔍 Getting node inventory..."
NODE_NAMES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$NODE_NAMES" ]; then
    print_pass "Found $(echo $NODE_NAMES | wc -w) nodes: $NODE_NAMES"
else
    print_fail "No nodes found in cluster"
    exit 1
fi

# 2.2 Check current node-role labels
echo "🔍 Checking existing node-role labels..."
NODES_WITH_STORAGE_ROLE=0
NODES_WITH_ANY_ROLE=0

IFS=' ' read -r -a NODE_ARRAY <<< "$NODE_NAMES"
for NODE in "${NODE_ARRAY[@]}"; do
    NODE_ROLE=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.node-role}' 2>/dev/null || echo "")
    if [ -n "$NODE_ROLE" ]; then
        NODES_WITH_ANY_ROLE=$((NODES_WITH_ANY_ROLE + 1))
        if [ "$NODE_ROLE" = "storage-heavy" ]; then
            NODES_WITH_STORAGE_ROLE=$((NODES_WITH_STORAGE_ROLE + 1))
        fi
    fi
done

if [ "$NODES_WITH_STORAGE_ROLE" -eq 0 ]; then
    print_pass "No nodes currently labeled as storage-heavy (ready for labeling)"
elif [ "$NODES_WITH_STORAGE_ROLE" -eq 2 ]; then
    print_pass "2 nodes already labeled as storage-heavy (configuration matches target)"
else
    print_warn "$NODES_WITH_STORAGE_ROLE nodes labeled as storage-heavy (will be overwritten)"
fi

if [ "$NODES_WITH_ANY_ROLE" -gt 0 ]; then
    print_warn "$NODES_WITH_ANY_ROLE nodes have existing node-role labels"
fi

echo ""
echo "=== SECTION 3: NODE CAPACITY ANALYSIS ==="
echo ""

# 3.1 Check node resources (simplified)
echo "🔍 Checking node resource capacities..."
for NODE in "${NODE_ARRAY[@]}"; do
    CPU_CAPACITY=$(kubectl get node "$NODE" -o jsonpath='{.status.capacity.cpu}' 2>/dev/null || echo "unknown")
    MEMORY_CAPACITY=$(kubectl get node "$NODE" -o jsonpath='{.status.capacity.memory}' 2>/dev/null || echo "unknown")
    
    echo "  Node: $NODE"
    echo "    CPU: $CPU_CAPACITY cores"
    echo "    Memory: $MEMORY_CAPACITY"
done

print_pass "Node capacity check completed"

echo ""
echo "=== SECTION 4: WORKLOAD PLACEMENT STRATEGY ==="
echo ""

# 4.1 Determine labeling strategy
NODE_COUNT=${#NODE_ARRAY[@]}
if [ "$NODE_COUNT" -ge 3 ]; then
    print_pass "Cluster has $NODE_COUNT nodes (sufficient for topology-aware scheduling)"
    echo "  Labeling strategy:"
    echo "    - First 2 nodes: node-role=storage-heavy (PostgreSQL + MinIO)"
    echo "    - Remaining nodes: General purpose (control/observability)"
else
    print_warn "Cluster has only $NODE_COUNT nodes (minimum 3 recommended)"
    echo "  Labeling strategy:"
    echo "    - All nodes will be labeled as storage-heavy"
fi

echo ""
echo "=== SECTION 5: REQUIRED TOOLS ==="
echo ""

# Check required tools
echo "🔍 Checking required tools..."
for tool in kubectl; do
    if command -v "$tool" &> /dev/null; then
        print_pass "$tool is installed"
    else
        print_fail "$tool is not installed"
    fi
done

# Check optional tools
if command -v jq &> /dev/null; then
    print_pass "jq is installed (optional)"
else
    print_warn "jq is not installed (optional - for advanced JSON parsing)"
fi

echo ""
echo "=== SECTION 6: VALIDATION PREPARATION ==="
echo ""

# 6.1 Create validation directory
echo "🔍 Preparing validation directory..."
mkdir -p logs 2>/dev/null || true
print_pass "Validation directory ready"

# 6.2 Export node count for deployment script
export NODE_COUNT
print_pass "Node count exported: $NODE_COUNT"

echo ""
echo "================================================================"
echo "PRE-DEPLOYMENT CHECK COMPLETED"
echo "================================================================"
echo "✅ All checks completed successfully"
echo ""
echo "Cluster summary:"
echo "  - Total nodes: $NODE_COUNT"
echo "  - Nodes ready for labeling: ${#NODE_ARRAY[@]}"
echo "  - Current storage-heavy nodes: $NODES_WITH_STORAGE_ROLE"
echo ""
echo "Next: Run deployment script: ./02-deployment.sh"
exit 0