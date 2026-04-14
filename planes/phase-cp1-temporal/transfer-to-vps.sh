#!/bin/bash
set -e

echo "================================================"
echo "Transfer Temporal CP-1 Files to VPS"
echo "================================================"
echo "This script helps transfer Temporal Server files to your VPS."
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

echo ""
echo "Files to transfer:"
echo "  1. Temporal CP-1 scripts: $SCRIPT_DIR/"
echo ""

# Create temporary directory
TEMP_DIR="/tmp/temporal-cp1-transfer-$(date +%s)"
mkdir -p "$TEMP_DIR"

# Copy files
echo "Preparing files..."
cp -r "$SCRIPT_DIR" "$TEMP_DIR/phase-cp1-temporal"

# Create README for VPS
cat > "$TEMP_DIR/README-VPS.md" << EOF
# Temporal Server CP-1 Files Deployed to VPS

## Files Transferred
- \`phase-cp1-temporal/\` - All deployment scripts and manifests

## Quick Start
\`\`\`bash
# Navigate to directory
cd phase-cp1-temporal

# Make scripts executable
chmod +x *.sh

# Run pre-deployment check
./01-pre-deployment-check.sh

# Deploy Temporal Server
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

# kubectl (if not already installed)
curl -LO "https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# tctl (Temporal CLI, optional)
wget https://github.com/temporalio/temporal/releases/latest/download/tctl.zip
unzip tctl.zip
sudo mv tctl /usr/local/bin/
\`\`\`

## Verify Kubernetes Access
\`\`\`bash
kubectl cluster-info
kubectl get nodes
kubectl get namespace control-plane
\`\`\`

## Important Notes
1. **PostgreSQL Required**: Temporal needs PostgreSQL with:
   - \`temporal\` database
   - \`temporal_visibility\` database
   - Secret \`temporal-postgres-creds\` in data-plane namespace

2. **Namespace**: Temporal will be deployed to \`control-plane\` namespace

3. **Resource Requirements**: Each Temporal pod requires 750Mi memory
   - Ensure cluster has sufficient resources
   - Check with: \`kubectl describe node | grep -A5 -B5 Allocatable\`

## More Information
See \`README.md\` for detailed instructions.
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
echo "   cd phase-cp1-temporal"
echo "   chmod +x *.sh"
echo "   ./01-pre-deployment-check.sh"
echo "   ./02-deployment.sh"
echo "   ./03-validation.sh"

echo ""
echo "================================================"
echo "Transfer Complete!"
echo "================================================"