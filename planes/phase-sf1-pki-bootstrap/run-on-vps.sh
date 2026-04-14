#!/bin/bash

# Script to run pre-deployment check on VPS cluster
# This script copies the check script to the VPS and runs it

set -e

echo "=============================================="
echo "Running Phase SF-1 Pre-deployment on VPS Cluster"
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
    echo "   Check:"
    echo "   1. VPS IP address: $VPS_IP"
    echo "   2. SSH key permissions: chmod 600 $SSH_KEY"
    echo "   3. Network connectivity"
    exit 1
fi

echo ""
echo "2. Checking VPS environment..."
ssh -i "$SSH_KEY" "$SSH_USER@$VPS_IP" << 'EOF'
echo "Hostname: $(hostname)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"
echo ""
EOF

echo ""
echo "3. Copying pre-deployment check script to VPS..."
# Create a temporary directory on VPS
TEMP_DIR=$(ssh -i "$SSH_KEY" "$SSH_USER@$VPS_IP" "mktemp -d")
echo "   Temporary directory on VPS: $TEMP_DIR"

# Copy the script
scp -i "$SSH_KEY" "01-pre-deployment-check-vps.sh" "$SSH_USER@$VPS_IP:$TEMP_DIR/"
echo "✓ Script copied to VPS"

echo ""
echo "4. Making script executable on VPS..."
ssh -i "$SSH_KEY" "$SSH_USER@$VPS_IP" "chmod +x $TEMP_DIR/01-pre-deployment-check-vps.sh"

echo ""
echo "5. Running pre-deployment check on VPS..."
echo "=============================================="
ssh -i "$SSH_KEY" "$SSH_USER@$VPS_IP" "cd $TEMP_DIR && ./01-pre-deployment-check-vps.sh"
EXIT_CODE=$?
echo "=============================================="

echo ""
echo "6. Cleaning up..."
ssh -i "$SSH_KEY" "$SSH_USER@$VPS_IP" "rm -rf $TEMP_DIR"
echo "✓ Cleaned up temporary files"

echo ""
echo "=============================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Pre-deployment check completed successfully"
    echo ""
    echo "Next steps:"
    echo "  1. Review the check results above"
    echo "  2. Address any warnings or errors"
    echo "  3. Run deployment script on VPS"
else
    echo "❌ Pre-deployment check failed with exit code: $EXIT_CODE"
    echo ""
    echo "Please address the issues shown above before proceeding."
fi
echo "=============================================="

exit $EXIT_CODE