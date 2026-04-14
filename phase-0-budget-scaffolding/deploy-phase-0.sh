#!/bin/bash
set -e

echo "=== Deploying Phase 0: Budget Scaffolding ==="
echo ""

# Create namespaces first
echo "1. Creating namespaces..."
kubectl create namespace control-plane 2>/dev/null || true
kubectl create namespace data-plane 2>/dev/null || true
kubectl create namespace observability-plane 2>/dev/null || true

# Apply PriorityClasses
echo "2. Applying PriorityClasses..."
kubectl apply -f priorityclasses/foundation-priorityclasses.yaml

# Apply ResourceQuotas and LimitRanges
echo "3. Applying ResourceQuotas and LimitRanges..."
kubectl apply -f resourcequotas/control-plane-quota.yaml
kubectl apply -f resourcequotas/data-plane-quota.yaml
kubectl apply -f resourcequotas/observability-plane-quota.yaml

# Apply StorageClass
echo "4. Applying StorageClass..."
kubectl apply -f storageclass/nvme-waitfirst.yaml

# Label nodes
echo "5. Labeling nodes..."
./nodelabels/label-nodes.sh

echo ""
echo "✅ Phase 0 deployed successfully!"
echo ""
echo "Run validation: ./validate-phase-0.sh"
