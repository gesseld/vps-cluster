#!/bin/bash

# Script to install prerequisites on VPS cluster

set -e

echo "=============================================="
echo "Installing Prerequisites on VPS Cluster"
echo "=============================================="
echo ""

# Configuration
VPS_IP="49.12.37.154"  # Control plane node IP
SSH_KEY="../../hetzner-cli-key"
SSH_USER="root"  # Assuming root access

# Check if SSH key exists
if [ ! -f "$SSH_KEY" ]; then
    echo "✗ ERROR: SSH key not found: $SSH_KEY"
    exit 1
fi

echo "1. Testing SSH connection to VPS cluster ($VPS_IP)..."
if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$VPS_IP" "echo '✓ SSH connection successful'"; then
    echo "✓ SSH connection established"
else
    echo "✗ ERROR: Cannot connect to VPS via SSH"
    exit 1
fi

echo ""
echo "2. Installing required tools on VPS..."
ssh -i "$SSH_KEY" "$SSH_USER@$VPS_IP" << 'EOF'
set -e

echo "Updating package list..."
apt-get update -qq

echo "Installing required tools..."
# Install curl and jq
apt-get install -y curl jq

# Install helm
if ! command -v helm > /dev/null 2>&1; then
    echo "Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
else
    echo "Helm already installed: $(helm version --short)"
fi

# Verify installations
echo ""
echo "Verifying installations:"
command -v curl && echo "✓ curl installed: $(curl --version | head -1)"
command -v jq && echo "✓ jq installed: $(jq --version)"
command -v helm && echo "✓ helm installed: $(helm version --short)"
command -v kubectl && echo "✓ kubectl installed: $(kubectl version --short 2>/dev/null | grep 'Client' | awk '{print $3}' || echo 'Unknown')"

echo ""
echo "Adding Helm repositories..."
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || echo "jetstack repo already added"
helm repo add spiffe https://spiffe.github.io/helm-charts/ 2>/dev/null || echo "spiffe repo already added"
helm repo update

echo "✓ Prerequisites installation complete"
EOF

echo ""
echo "3. Testing tool availability..."
ssh -i "$SSH_KEY" "$SSH_USER@$VPS_IP" << 'EOF'
echo "Testing kubectl..."
kubectl cluster-info

echo ""
echo "Testing Helm..."
helm version --short
helm repo list

echo ""
echo "Testing other tools..."
curl --version | head -1
jq --version
EOF

echo ""
echo "=============================================="
echo "✅ Prerequisites installation completed"
echo "=============================================="
echo ""
echo "Next: Run pre-deployment check:"
echo "  ./run-on-vps.sh"
echo ""

exit 0