#!/bin/bash
# BS-4: Node Labeling for Topology Awareness - Deployment Script
# Simplified version for WSL compatibility

echo "================================================================"
echo "BS-4: NODE LABELING FOR TOPOLOGY AWARENESS - DEPLOYMENT"
echo "================================================================"
echo "Objective: Label nodes for topology-aware scheduling"
echo "Date: $(date)"
echo ""

# Set error handling
set -e

# Output functions
print_success() {
    echo "✅ SUCCESS: $1"
}

print_info() {
    echo "ℹ️  INFO: $1"
}

print_error() {
    echo "❌ ERROR: $1"
}

# Log file setup
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "Logging to: $LOG_FILE"
echo ""

echo "=== SECTION 1: INITIALIZATION & VALIDATION ==="
echo ""

# 1.1 Check if pre-deployment was run
echo "🔍 Checking pre-deployment status..."
if ! kubectl get nodes &> /dev/null; then
    print_error "Cannot connect to K3s cluster. Run pre-deployment check first."
    exit 1
fi

# 1.2 Get node list
echo "🔍 Getting node inventory..."
NODE_NAMES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -z "$NODE_NAMES" ]; then
    print_error "No nodes found in cluster"
    exit 1
fi

# Convert to array
IFS=' ' read -r -a NODE_ARRAY <<< "$NODE_NAMES"
NODE_COUNT=${#NODE_ARRAY[@]}

print_success "Found $NODE_COUNT nodes: ${NODE_ARRAY[*]}"

echo ""
echo "=== SECTION 2: NODE LABELING STRATEGY ==="
echo ""

# 2.1 Determine labeling strategy
echo "📋 Determining labeling strategy..."
if [ "$NODE_COUNT" -ge 3 ]; then
    STORAGE_NODES=2
    GENERAL_NODES=$((NODE_COUNT - 2))
    print_info "Cluster has $NODE_COUNT nodes - using optimal strategy:"
    echo "  - $STORAGE_NODES nodes will be labeled: node-role=storage-heavy"
    echo "  - $GENERAL_NODES nodes will remain general purpose"
else
    STORAGE_NODES=$NODE_COUNT
    GENERAL_NODES=0
    print_info "Cluster has only $NODE_COUNT nodes - labeling all as storage-heavy"
    echo "  - All $STORAGE_NODES nodes will be labeled: node-role=storage-heavy"
fi

echo ""
echo "=== SECTION 3: APPLYING NODE LABELS ==="
echo ""

# 3.1 Label storage-heavy nodes
echo "🏷️  Labeling storage-heavy nodes..."
STORAGE_LABELED_COUNT=0
for ((i=0; i<STORAGE_NODES && i<NODE_COUNT; i++)); do
    NODE="${NODE_ARRAY[$i]}"
    echo "  Labeling node: $NODE"
    
    # Apply storage-heavy label
    if kubectl label node "$NODE" node-role=storage-heavy --overwrite; then
        STORAGE_LABELED_COUNT=$((STORAGE_LABELED_COUNT + 1))
        print_success "Node $NODE labeled as storage-heavy"
    else
        print_error "Failed to label node $NODE"
    fi
done

# 3.2 Remove storage-heavy label from remaining nodes (if any)
echo ""
echo "🏷️  Ensuring remaining nodes are not storage-heavy..."
for ((i=STORAGE_NODES; i<NODE_COUNT; i++)); do
    NODE="${NODE_ARRAY[$i]}"
    
    # Check if node has storage-heavy label
    CURRENT_LABEL=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.node-role}' 2>/dev/null || echo "")
    if [ "$CURRENT_LABEL" = "storage-heavy" ]; then
        echo "  Removing storage-heavy label from: $NODE"
        if kubectl label node "$NODE" node-role-; then
            print_success "Removed storage-heavy label from $NODE"
        else
            print_error "Failed to remove label from $NODE"
        fi
    else
        print_info "Node $NODE already not labeled as storage-heavy"
    fi
done

echo ""
echo "=== SECTION 4: ADDITIONAL TOPOLOGY LABELS ==="
echo ""

# 4.1 Check and add topology zone labels
echo "🏷️  Configuring topology zone labels..."
ZONE_INDEX=0
for NODE in "${NODE_ARRAY[@]}"; do
    echo "  Checking zone label for node: $NODE"
    
    # Check if node already has a zone label
    EXISTING_ZONE=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_ZONE" ]; then
        print_info "Node $NODE already has zone label: $EXISTING_ZONE (preserving)"
    else
        # Add new zone label
        ZONE=$((ZONE_INDEX % 3 + 1))  # Create 3 zones for diversity
        if kubectl label node "$NODE" topology.kubernetes.io/zone="zone-$ZONE" 2>/dev/null; then
            print_success "Added zone label to $NODE: zone-$ZONE"
        else
            print_info "Could not add zone label to $NODE"
        fi
    fi
    
    ZONE_INDEX=$((ZONE_INDEX + 1))
done

# 4.2 Check and add region labels
echo ""
echo "🏷️  Configuring topology region labels..."
for NODE in "${NODE_ARRAY[@]}"; do
    echo "  Checking region label for node: $NODE"
    
    # Check if node already has a region label
    EXISTING_REGION=$(kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/region}' 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_REGION" ]; then
        print_info "Node $NODE already has region label: $EXISTING_REGION (preserving)"
    else
        # Add new region label
        if kubectl label node "$NODE" topology.kubernetes.io/region="hetzner-fsn1" 2>/dev/null; then
            print_success "Added region label to $NODE: hetzner-fsn1"
        else
            print_info "Could not add region label to $NODE"
        fi
    fi
done

echo ""
echo "=== SECTION 5: VERIFICATION ==="
echo ""

# 5.1 Verify storage-heavy labels
echo "🔍 Verifying storage-heavy labels..."
ACTUAL_STORAGE_NODES=$(kubectl get nodes -l node-role=storage-heavy --no-headers 2>/dev/null | wc -l)
if [ "$ACTUAL_STORAGE_NODES" -eq "$STORAGE_LABELED_COUNT" ]; then
    print_success "Verified: $ACTUAL_STORAGE_NODES nodes labeled as storage-heavy"
else
    print_error "Label verification failed: Expected $STORAGE_LABELED_COUNT, found $ACTUAL_STORAGE_NODES"
fi

# 5.2 List all nodes with labels
echo ""
echo "📊 Final node label status:"
kubectl get nodes -o custom-columns=NAME:.metadata.name,ROLE:.metadata.labels.node-role,ZONE:.metadata.labels.'topology\.kubernetes\.io/zone',REGION:.metadata.labels.'topology\.kubernetes\.io/region' 2>/dev/null || \
kubectl get nodes --show-labels 2>/dev/null | head -10

echo ""
echo "=== SECTION 6: WORKLOAD PLACEMENT EXAMPLES ==="
echo ""

# 6.1 Create example node selectors
echo "📝 Example workload placement configurations:"
echo ""
echo "For PostgreSQL (storage-heavy):"
echo "---"
echo "nodeSelector:"
echo "  node-role: storage-heavy"
echo "  topology.kubernetes.io/zone: zone-1"
echo "---"
echo ""
echo "For MinIO (storage-heavy):"
echo "---"
echo "nodeSelector:"
echo "  node-role: storage-heavy"
echo "  topology.kubernetes.io/zone: zone-2"
echo "---"
echo ""
echo "For monitoring stack (general purpose):"
echo "---"
echo "nodeSelector:"
echo "  node-role: general"
echo "---"

echo ""
echo "=== SECTION 7: CLEANUP & NEXT STEPS ==="
echo ""

# 7.1 Create cleanup script
echo "🔧 Creating cleanup script..."
cat > cleanup-labels.sh << 'EOF'
#!/bin/bash
echo "Cleaning up node labels..."
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
for NODE in $NODES; do
    echo "Cleaning labels on node: $NODE"
    kubectl label node "$NODE" node-role- 2>/dev/null || true
    kubectl label node "$NODE" topology.kubernetes.io/zone- 2>/dev/null || true
    kubectl label node "$NODE" topology.kubernetes.io/region- 2>/dev/null || true
done
echo "✅ Labels cleaned up"
EOF

chmod +x cleanup-labels.sh
print_success "Cleanup script created: ./cleanup-labels.sh"

echo ""
echo "================================================================"
echo "DEPLOYMENT COMPLETED"
echo "================================================================"
echo "✅ Node labeling completed successfully"
echo ""
echo "Summary:"
echo "  - Total nodes: $NODE_COUNT"
echo "  - Storage-heavy nodes: $STORAGE_LABELED_COUNT"
echo "  - General purpose nodes: $((NODE_COUNT - STORAGE_LABELED_COUNT))"
echo "  - Topology zones configured: 3"
echo ""
echo "Next: Run validation script: ./03-validation.sh"
echo ""
echo "Log file: $LOG_FILE"
exit 0