#!/bin/bash

set -e

echo "=== Kyverno Deployment on VPS Cluster ==="
echo "Setting up environment for VPS cluster..."

# Set kubeconfig path
export KUBECONFIG="$(pwd)/../../kubeconfig"

# Verify kubeconfig exists
if [ ! -f "$KUBECONFIG" ]; then
    echo "ERROR: kubeconfig not found at $KUBECONFIG"
    exit 1
fi

echo "Using kubeconfig: $KUBECONFIG"

# Verify cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✓ Connected to VPS cluster"

# Run the scripts
echo ""
echo "1. Running pre-deployment checks..."
./pre-deployment.sh

echo ""
echo "2. Deploying Kyverno..."
./deploy-kyverno.sh

echo ""
echo "3. Validating deployment..."
./validate-kyverno.sh

echo ""
echo "=== Kyverno deployment on VPS cluster completed ==="
echo "All scripts executed successfully."