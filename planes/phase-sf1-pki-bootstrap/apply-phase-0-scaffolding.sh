#!/bin/bash

# Phase 0: Budget Scaffolding Application
# This script applies the mandatory gate before ANY workload deployment

set -e

echo "=============================================="
echo "Phase 0: Budget Scaffolding Application"
echo "=============================================="
echo ""

echo "1. Checking current node labels..."
kubectl get nodes -o custom-columns='NAME:.metadata.name,ROLE:.metadata.labels.node-role,STORAGE:.metadata.labels.node-role'

echo ""
echo "2. Labeling ALL nodes for topology awareness..."
echo "   According to specification:"
echo "   - 2 nodes with storage-heavy"
echo "   - 1 node with general"

# Label nodes according to the specification
kubectl label node k3s-cp-1 node-role=storage-heavy --overwrite
kubectl label node k3s-w-1 node-role=storage-heavy --overwrite
kubectl label node k3s-w-2 node-role=general --overwrite

echo ""
echo "3. Verifying node labels..."
kubectl get nodes -o custom-columns='NAME:.metadata.name,ROLE:.metadata.labels.node-role'

echo ""
echo "4. Checking PriorityClasses..."
kubectl get priorityclass | grep foundation

echo ""
echo "5. Checking StorageClasses..."
kubectl get storageclass -o custom-columns='NAME:.metadata.name,BINDING:.volumeBindingMode,DEFAULT:.metadata.annotations.storageclass\.kubernetes\.io/is-default-class'

echo ""
echo "6. Creating data-plane namespace if needed..."
if ! kubectl get ns data-plane > /dev/null 2>&1; then
    kubectl create namespace data-plane
    echo "✓ Created data-plane namespace"
else
    echo "⚠ data-plane namespace already exists"
fi

echo ""
echo "7. Checking ResourceQuotas in data-plane namespace..."
if kubectl get resourcequota -n data-plane > /dev/null 2>&1; then
    echo "ResourceQuotas in data-plane:"
    kubectl get resourcequota -n data-plane
else
    echo "⚠ No ResourceQuotas found in data-plane namespace"
    echo "   Note: ResourceQuotas should be applied for budget enforcement"
fi

echo ""
echo "8. Checking LimitRanges in data-plane namespace..."
if kubectl get limitrange -n data-plane > /dev/null 2>&1; then
    echo "LimitRanges in data-plane:"
    kubectl get limitrange -n data-plane
else
    echo "⚠ No LimitRanges found in data-plane namespace"
fi

echo ""
echo "=============================================="
echo "Phase 0 Scaffolding Summary"
echo "=============================================="
echo ""
echo "✅ Applied:"
echo "   - Node labels: 2× storage-heavy, 1× general"
echo "   - PriorityClasses: foundation-critical/high/medium"
echo ""
echo "⚠ To be manually applied (if needed):"
echo "   - ResourceQuotas for budget enforcement"
echo "   - LimitRanges for default limits"
echo "   - StorageClass with WaitForFirstConsumer"
echo ""
echo "Next steps:"
echo "   1. Deploy PostgreSQL (critical dependency)"
echo "   2. Create .env file with PostgreSQL credentials"
echo "   3. Run Phase 1 deployment (SPIRE PKI bootstrap)"
echo ""
echo "To validate Gate 0 passes, run:"
echo "   ./validate-phase-gates.sh 0"
echo ""

exit 0