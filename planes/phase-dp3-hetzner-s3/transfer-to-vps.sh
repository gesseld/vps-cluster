#!/bin/bash
set -e

echo "================================================"
echo "Transfer Files to VPS"
echo "================================================"
echo "This script helps transfer Task DP-3 files to your VPS."
echo ""

# Check for required parameters
if [ $# -lt 2 ]; then
    echo "Usage: $0 <vps-username> <vps-ip-address> [ssh-port]"
    echo ""
    echo "Example:"
    echo "  $0 ubuntu 192.168.1.100"
    echo "  $0 root 10.0.0.5 2222"
    echo ""
    echo "Make sure you have SSH access to the VPS."
    exit 1
fi

VPS_USER="$1"
VPS_IP="$2"
VPS_PORT="${3:-22}"

echo "VPS Details:"
echo "  Username: $VPS_USER"
echo "  IP Address: $VPS_IP"
echo "  SSH Port: $VPS_PORT"
echo ""

# Check SSH connectivity
echo "Testing SSH connectivity..."
if ! ssh -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "echo 'SSH connection successful'" > /dev/null 2>&1; then
    echo "❌ Cannot connect to VPS via SSH"
    echo "   Check:"
    echo "   1. VPS is running and accessible"
    echo "   2. SSH port $VPS_PORT is open"
    echo "   3. You have the correct credentials"
    echo "   4. SSH key is configured (if using key auth)"
    exit 1
fi
echo "✅ SSH connection successful"

# Get current directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo ""
echo "Files to transfer:"
echo "  1. Task DP-3 scripts: $SCRIPT_DIR/"
echo "  2. Environment file: $PROJECT_ROOT/.env"
echo ""

# Create temporary directory
TEMP_DIR="/tmp/dp3-transfer-$(date +%s)"
mkdir -p "$TEMP_DIR"

# Copy files
echo "Preparing files..."
cp -r "$SCRIPT_DIR" "$TEMP_DIR/phase-dp3-hetzner-s3"
cp "$PROJECT_ROOT/.env" "$TEMP_DIR/" 2>/dev/null || {
    echo "⚠️  .env file not found at $PROJECT_ROOT/.env"
    echo "   Creating sample .env file..."
    cat > "$TEMP_DIR/.env" << EOF
# Hetzner Object Storage Configuration
HETZNER_S3_ENDPOINT=https://fsn1.your-objectstorage.com
HETZNER_S3_ACCESS_KEY=YAGEW4STIWFXRWQUS8L8
HETZNER_S3_SECRET_KEY=1oNMJluHotAFfoBuZhsTf352uWYlOAMiM3GlbHES
HETZNER_S3_REGION=fsn1

# Kubernetes Namespaces
NAMESPACE=data-plane
OBSERVABILITY_NAMESPACE=observability-plane
STORAGE_CLASS=hcloud-volumes
EOF
}

# Create README for VPS
cat > "$TEMP_DIR/README-VPS.md" << EOF
# Task DP-3 Files Deployed to VPS

## Files Transferred
- \`phase-dp3-hetzner-s3/\` - All deployment scripts
- \`.env\` - Environment variables (check credentials)

## Quick Start
\`\`\`bash
# Navigate to directory
cd phase-dp3-hetzner-s3

# Make scripts executable
chmod +x *.sh

# Test credentials (requires mc installed)
./test-credentials.sh

# Run pre-deployment check
./01-pre-deployment-check.sh

# Deploy S3 storage
./02-deployment.sh

# Validate deployment
./03-validation.sh
\`\`\`

## Required Tools on VPS
Install these before running scripts:
\`\`\`bash
# Basic tools
sudo apt-get update
sudo apt-get install -y curl jq

# kubectl
curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# mc (MinIO Client)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/
\`\`\`

## Verify Kubernetes Access
\`\`\`bash
kubectl cluster-info
kubectl get nodes
kubectl get namespace data-plane
\`\`\`

## More Information
See \`VPS_DEPLOYMENT_GUIDE.md\` for detailed instructions.
EOF

echo "Transferring files to VPS..."
scp -P "$VPS_PORT" -r "$TEMP_DIR" "$VPS_USER@$VPS_IP:/home/$VPS_USER/"

echo ""
echo "Files transferred to: /home/$VPS_USER/$(basename "$TEMP_DIR")"
echo ""

# Clean up
rm -rf "$TEMP_DIR"

echo "Next steps on VPS:"
echo "1. SSH into VPS:"
echo "   ssh -p $VPS_PORT $VPS_USER@$VPS_IP"
echo ""
echo "2. Navigate to transferred directory:"
echo "   cd /home/$VPS_USER/$(basename "$TEMP_DIR")"
echo ""
echo "3. Follow instructions in README-VPS.md"
echo ""
echo "4. Or run the deployment scripts directly:"
echo "   cd phase-dp3-hetzner-s3"
echo "   chmod +x *.sh"
echo "   ./01-pre-deployment-check.sh"
echo "   ./02-deployment.sh"
echo "   ./03-validation.sh"

echo ""
echo "================================================"
echo "Transfer Complete!"
echo "================================================"