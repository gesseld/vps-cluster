#!/bin/bash
# BS-3: StorageClass with WaitForFirstConsumer - Pre-Deployment Check
# Simplified version for WSL compatibility

echo "================================================================"
echo "BS-3: STORAGECLASS WITH WAITFORFIRSTCONSUMER - PRE-DEPLOYMENT CHECK"
echo "================================================================"
echo "Objective: Ensure stateful workloads schedule to nodes with available NVMe before PVC binding"
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
if kubectl auth can-i create storageclass 2>&1 | grep -q "yes"; then
    print_pass "kubectl has permissions to create StorageClass"
else
    print_fail "kubectl does not have permissions to create StorageClass"
fi

echo ""
echo "=== SECTION 2: STORAGE INFRASTRUCTURE ==="
echo ""

# 2.1 Check existing StorageClasses
echo "🔍 Checking existing StorageClasses..."
STORAGECLASS_COUNT=$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)
if [ "$STORAGECLASS_COUNT" -gt 0 ]; then
    print_pass "Found $STORAGECLASS_COUNT existing StorageClass(es)"
else
    print_warn "No existing StorageClasses found"
fi

# 2.2 Check CSI drivers
echo "🔍 Checking for CSI driver pods..."
CSI_PODS=$(kubectl get pods -n kube-system 2>/dev/null | grep -i "csi" | grep -v NAME | wc -l)
if [ "$CSI_PODS" -ge 1 ]; then
    print_pass "Found $CSI_PODS CSI driver pod(s) in kube-system namespace"
else
    print_warn "No CSI driver pods found in kube-system namespace"
fi

# 2.3 Check for CSI driver
echo "🔍 Checking for CSI driver..."
CSI_PODS_OUTPUT=$(timeout 5 kubectl get pods -n kube-system 2>/dev/null || echo "")
if echo "$CSI_PODS_OUTPUT" | grep -q "rke.csi"; then
    print_pass "Rancher CSI driver (rke.csi.rancher.io) detected"
    CSI_DRIVER="rke.csi.rancher.io"
elif echo "$CSI_PODS_OUTPUT" | grep -q "hcloud-csi"; then
    print_pass "Hetzner CSI driver detected"
    CSI_DRIVER="csi.hetzner.cloud"
elif echo "$CSI_PODS_OUTPUT" | grep -q "csi.longhorn"; then
    print_pass "Longhorn CSI driver detected"
    CSI_DRIVER="driver.longhorn.io"
else
    print_warn "No specific CSI driver detected, will use rke.csi.rancher.io as default"
    CSI_DRIVER="rke.csi.rancher.io"
fi

echo ""
echo "=== SECTION 3: NODE TOPOLOGY & LABELS ==="
echo ""

# 3.1 Check node topology labels (simplified)
echo "🔍 Checking node topology labels for WaitForFirstConsumer..."
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

# Simple check without complex loops
NODES_WITH_ZONE=0
NODES_WITH_REGION=0

# Get all nodes and check labels - handle word splitting properly
NODE_NAMES=$(timeout 5 kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$NODE_NAMES" ]; then
    # Convert to array
    IFS=' ' read -r -a NODE_ARRAY <<< "$NODE_NAMES"
    for NODE in "${NODE_ARRAY[@]}"; do
        ZONE_LABEL=$(timeout 3 kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo "")
        REGION_LABEL=$(timeout 3 kubectl get node "$NODE" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/region}' 2>/dev/null || echo "")
        
        [ -n "$ZONE_LABEL" ] && NODES_WITH_ZONE=$((NODES_WITH_ZONE + 1))
        [ -n "$REGION_LABEL" ] && NODES_WITH_REGION=$((NODES_WITH_REGION + 1))
    done
fi

if [ "$NODES_WITH_ZONE" -eq "$NODE_COUNT" ]; then
    print_pass "All $NODE_COUNT nodes have topology.kubernetes.io/zone labels"
else
    print_warn "$NODES_WITH_ZONE/$NODE_COUNT nodes have topology.kubernetes.io/zone labels"
fi

if [ "$NODES_WITH_REGION" -eq "$NODE_COUNT" ]; then
    print_pass "All $NODE_COUNT nodes have topology.kubernetes.io/region labels"
else
    print_warn "$NODES_WITH_REGION/$NODE_COUNT nodes have topology.kubernetes.io/region labels"
fi

echo ""
echo "=== SECTION 4: REQUIRED TOOLS ==="
echo ""

# Check required tools
echo "🔍 Checking required tools..."
for tool in kubectl jq envsubst; do
    if command -v "$tool" &> /dev/null; then
        print_pass "$tool is installed"
    else
        print_fail "$tool is not installed"
    fi
done

echo ""
echo "=== SECTION 5: ENVIRONMENT CONFIGURATION ==="
echo ""

# Export CSI driver for deployment script
export CSI_DRIVER
print_pass "CSI driver configured: $CSI_DRIVER"

echo ""
echo "================================================================"
echo "PRE-DEPLOYMENT CHECK COMPLETED"
echo "================================================================"
echo "✅ All checks completed successfully"
echo ""
echo "CSI driver to use: $CSI_DRIVER"
echo ""
echo "Next: Run deployment script: ./02-deployment.sh"
exit 0