#!/bin/bash
# Transfer Temporal HA deployment to VPS

set -e

echo "================================================"
echo "📤 TRANSFER TEMPORAL HA TO VPS"
echo "================================================"
echo "VPS IP: 49.12.37.154"
echo "Date: $(date)"
echo "================================================"

# Check if SSH key exists
SSH_KEY="$HOME/.ssh/hetzner-cli-key"
if [ ! -f "$SSH_KEY" ]; then
    echo "❌ SSH key not found: $SSH_KEY"
    echo "Please copy the SSH key from Windows to WSL:"
    echo "  cp /mnt/c/Users/Daniel/Documents/k3s\ code\ v2/hetzner-cli-key ~/.ssh/"
    echo "  chmod 600 ~/.ssh/hetzner-cli-key"
    exit 1
fi

# Check SSH key permissions
if [ "$(stat -c %a "$SSH_KEY")" != "600" ]; then
    echo "⚠️  Fixing SSH key permissions..."
    chmod 600 "$SSH_KEY"
fi

# Test SSH connection
echo "Testing SSH connection to VPS..."
if ! ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 root@49.12.37.154 "echo 'SSH connection successful'"; then
    echo "❌ SSH connection failed"
    echo "Please verify:"
    echo "  1. VPS is running (IP: 49.12.37.154)"
    echo "  2. SSH key is authorized on VPS"
    echo "  3. Firewall allows SSH connections"
    exit 1
fi

echo "✅ SSH connection successful"

# Create directory structure on VPS
echo "Creating directory structure on VPS..."
ssh -i "$SSH_KEY" root@49.12.37.154 "mkdir -p /root/vps-cluster/planes/phase-dp5-temporal"

# Transfer files
echo "Transferring files to VPS..."

# Transfer scripts
echo "Transferring scripts..."
scp -i "$SSH_KEY" -r scripts/ root@49.12.37.154:/root/vps-cluster/planes/phase-dp5-temporal/

# Transfer documentation
echo "Transferring documentation..."
scp -i "$SSH_KEY" README.md IMPLEMENTATION_SUMMARY.md VPS_DEPLOYMENT_GUIDE.md EXECUTION_REPORT_TEMPLATE.md root@49.12.37.154:/root/vps-cluster/planes/phase-dp5-temporal/

# Transfer utility scripts
echo "Transferring utility scripts..."
scp -i "$SSH_KEY" run-all.sh test-structure.sh test-vps-deployment.sh transfer-to-vps.sh root@49.12.37.154:/root/vps-cluster/planes/phase-dp5-temporal/

# Set permissions on VPS
echo "Setting permissions on VPS..."
ssh -i "$SSH_KEY" root@49.12.37.154 "chmod +x /root/vps-cluster/planes/phase-dp5-temporal/scripts/*.sh"
ssh -i "$SSH_KEY" root@49.12.37.154 "chmod +x /root/vps-cluster/planes/phase-dp5-temporal/*.sh"

echo ""
echo "================================================"
echo "✅ TRANSFER COMPLETE"
echo "================================================"
echo ""
echo "📁 Files transferred to VPS:"
echo "   Location: /root/vps-cluster/planes/phase-dp5-temporal/"
echo ""
echo "🔧 Next steps on VPS:"
echo "   1. Connect to VPS:"
echo "      ssh -i ~/.ssh/hetzner-cli-key root@49.12.37.154"
echo ""
echo "   2. Navigate to directory:"
echo "      cd /root/vps-cluster/planes/phase-dp5-temporal"
echo ""
echo "   3. Test deployment readiness:"
echo "      ./test-vps-deployment.sh"
echo ""
echo "   4. Run deployment:"
echo "      ./run-all.sh"
echo "      # Or run individually:"
echo "      # cd scripts && ./01-pre-deployment-check.sh"
echo "      # cd scripts && ./02-deployment.sh"
echo "      # cd scripts && ./03-validation.sh"
echo ""
echo "📝 Documentation available:"
echo "   - README.md - Deployment instructions"
echo "   - VPS_DEPLOYMENT_GUIDE.md - Detailed VPS guide"
echo "   - EXECUTION_REPORT_TEMPLATE.md - Report template"
echo ""
echo "⚠️  IMPORTANT:"
echo "   - Change default passwords before production use"
echo "   - Configure TLS for secure access"
echo "   - Monitor resource usage"
echo "================================================"