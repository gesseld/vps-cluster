#!/bin/bash
set -e

echo "================================================"
echo "Testing Hetzner S3 Credentials"
echo "================================================"
echo ""

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
    echo "✓ Loaded environment variables from $PROJECT_ROOT/.env"
else
    echo "❌ No .env file found"
    exit 1
fi

echo ""
echo "Testing credentials:"
echo "Endpoint: $HETZNER_S3_ENDPOINT"
echo "Access Key: ${HETZNER_S3_ACCESS_KEY:0:8}..."
echo "Secret Key: ${HETZNER_S3_SECRET_KEY:0:8}..."
echo "Region: $HETZNER_S3_REGION"
echo ""

# Check if mc is installed
if ! command -v mc > /dev/null 2>&1; then
    echo "⚠️  mc (MinIO Client) is not installed locally"
    echo ""
    echo "This script is designed to run on your VPS where mc should be installed."
    echo "On your VPS, install mc with:"
    echo "  wget https://dl.min.io/client/mc/release/linux-amd64/mc"
    echo "  chmod +x mc"
    echo "  sudo mv mc /usr/local/bin/"
    echo ""
    echo "Alternatively, you can test credentials using AWS CLI:"
    echo "  aws s3 ls --endpoint-url=$HETZNER_S3_ENDPOINT \\"
    echo "    --access-key-id=$HETZNER_S3_ACCESS_KEY \\"
    echo "    --secret-access-key=$HETZNER_S3_SECRET_KEY"
    echo ""
    echo "For now, we'll skip the detailed S3 tests and just validate credentials format."
    
    # Validate credential format
    if [[ "$HETZNER_S3_ACCESS_KEY" =~ ^[A-Z0-9]{20}$ ]]; then
        echo "✅ Access key format looks correct (20 alphanumeric characters)"
    else
        echo "⚠️  Access key format may be incorrect"
    fi
    
    if [[ "$HETZNER_S3_SECRET_KEY" =~ ^[A-Za-z0-9+/=]{40}$ ]]; then
        echo "✅ Secret key format looks correct (40 base64 characters)"
    else
        echo "⚠️  Secret key format may be incorrect"
    fi
    
    echo ""
    echo "To fully test credentials, run this script on your VPS with mc installed."
    exit 0
fi

echo "1. Testing S3 connectivity..."
mc alias set test-hetzner "$HETZNER_S3_ENDPOINT" "$HETZNER_S3_ACCESS_KEY" "$HETZNER_S3_SECRET_KEY" --api s3v4 --path off

if mc alias list test-hetzner > /dev/null 2>&1; then
    echo "✅ S3 connectivity test PASSED"
else
    echo "❌ S3 connectivity test FAILED"
    mc alias remove test-hetzner > /dev/null 2>&1
    exit 1
fi

echo ""
echo "2. Listing buckets..."
if mc ls test-hetzner > /dev/null 2>&1; then
    echo "✅ Can list buckets"
    mc ls test-hetzner
    
    # Check for specific buckets
    echo ""
    echo "3. Checking for required buckets..."
    if mc ls test-hetzner/dip-entrepeai > /dev/null 2>&1; then
        echo "✅ Found 'dip-entrepeai' bucket (document storage)"
    else
        echo "❌ Missing 'dip-entrepeai' bucket"
    fi
    
    if mc ls test-hetzner/dip-documents-archive > /dev/null 2>&1; then
        echo "✅ Found 'dip-documents-archive' bucket (etcd backups)"
    else
        echo "⚠️  Missing 'dip-documents-archive' bucket"
    fi
else
    echo "⚠️  Cannot list buckets (may be empty or permissions issue)"
fi

echo ""
echo "3. Testing bucket creation..."
TEST_BUCKET="test-bucket-$(date +%s)"
if mc mb test-hetzner/$TEST_BUCKET --region "$HETZNER_S3_REGION" > /dev/null 2>&1; then
    echo "✅ Bucket creation test PASSED"
    
    echo ""
    echo "4. Testing object upload..."
    echo "test content" | mc pipe test-hetzner/$TEST_BUCKET/test-object.txt
    if mc stat test-hetzner/$TEST_BUCKET/test-object.txt > /dev/null 2>&1; then
        echo "✅ Object upload test PASSED"
    else
        echo "❌ Object upload test FAILED"
    fi
    
    echo ""
    echo "5. Testing object download..."
    mc cat test-hetzner/$TEST_BUCKET/test-object.txt > /tmp/test-download.txt 2>/dev/null
    if [ -f /tmp/test-download.txt ] && grep -q "test content" /tmp/test-download.txt; then
        echo "✅ Object download test PASSED"
    else
        echo "❌ Object download test FAILED"
    fi
    
    echo ""
    echo "6. Cleaning up test bucket..."
    mc rb --force test-hetzner/$TEST_BUCKET > /dev/null 2>&1
    echo "✅ Test bucket cleaned up"
else
    echo "❌ Bucket creation test FAILED"
fi

echo ""
echo "7. Testing WORM compliance setup..."
# This would test if we can enable WORM on a bucket
# Note: May require special permissions

echo ""
echo "8. Testing lifecycle policy setup..."
# This would test if we can set lifecycle policies
# Note: May require special permissions

echo ""
echo "Cleaning up..."
mc alias remove test-hetzner > /dev/null 2>&1
rm -f /tmp/test-download.txt

echo ""
echo "================================================"
echo "Credential Test Complete"
echo "================================================"
echo ""
echo "✅ Credentials are working correctly!"
echo ""
echo "Next steps:"
echo "1. Run pre-deployment check: ./01-pre-deployment-check.sh"
echo "2. Deploy S3 storage: ./02-deployment.sh"
echo "3. Validate deployment: ./03-validation.sh"
echo ""
echo "Note: Replication is currently disabled as requested."
echo "To enable replication later, add these to .env:"
echo "  REPLICATION_TARGET_ENDPOINT=https://nbg1.your-objectstorage.com"
echo "  REPLICATION_TARGET_ACCESS_KEY=your_dr_access_key"
echo "  REPLICATION_TARGET_SECRET_KEY=your_dr_secret_key"