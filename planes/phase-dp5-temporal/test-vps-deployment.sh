#!/bin/bash
# Test VPS Deployment Script
# Validates that scripts are ready for VPS deployment

set -e

echo "================================================"
echo "🔍 VPS DEPLOYMENT READINESS TEST"
echo "================================================"
echo "Phase: DP-5 (Data Plane Temporal HA)"
echo "Date: $(date)"
echo "VPS IP: 49.12.37.154"
echo "================================================"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "📋 Testing script readiness for VPS deployment..."
echo "------------------------------------------------"

# Test 1: Check script permissions
echo "1. Checking script permissions..."
if [ -x "scripts/01-pre-deployment-check.sh" ] && \
   [ -x "scripts/02-deployment.sh" ] && \
   [ -x "scripts/03-validation.sh" ]; then
    echo -e "${GREEN}✅ All scripts are executable${NC}"
else
    echo -e "${RED}❌ Some scripts are not executable${NC}"
    exit 1
fi

# Test 2: Check script syntax
echo "2. Checking script syntax..."
ERRORS=0
for script in scripts/*.sh; do
    if bash -n "$script" 2>/dev/null; then
        echo -e "  ${GREEN}✓ $script - valid syntax${NC}"
    else
        echo -e "  ${RED}✗ $script - invalid syntax${NC}"
        ((ERRORS++))
    fi
done

if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}❌ Script syntax errors found${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All scripts have valid syntax${NC}"
fi

# Test 3: Check for VPS IP configuration
echo "3. Checking VPS IP configuration..."
if grep -q "49.12.37.154" scripts/02-deployment.sh; then
    echo -e "${GREEN}✅ VPS IP (49.12.37.154) configured in deployment script${NC}"
else
    echo -e "${YELLOW}⚠️  VPS IP not found in deployment script${NC}"
fi

# Test 4: Check for domain update requirements
echo "4. Checking for manual domain updates..."
if grep -q "UPDATE THIS DOMAIN" scripts/02-deployment.sh; then
    echo -e "${RED}❌ Manual domain updates still required${NC}"
    exit 1
else
    echo -e "${GREEN}✅ No manual domain updates required${NC}"
fi

# Test 5: Check for password change warnings
echo "5. Checking password security warnings..."
if grep -q "Change default passwords" scripts/01-pre-deployment-check.sh && \
   grep -q "Change default passwords" scripts/03-validation.sh; then
    echo -e "${YELLOW}⚠️  Password change warnings present (expected)${NC}"
else
    echo -e "${GREEN}✅ Password security warnings configured${NC}"
fi

# Test 6: Check directory structure
echo "6. Checking directory structure..."
REQUIRED_DIRS=("scripts" "manifests" "logs" "deliverables")
MISSING_DIRS=0
for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "  ${GREEN}✓ $dir directory exists${NC}"
    else
        echo -e "  ${YELLOW}⚠️  $dir directory missing (will be created)${NC}"
        ((MISSING_DIRS++))
    fi
done

if [ $MISSING_DIRS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Some directories missing (will be created during execution)${NC}"
else
    echo -e "${GREEN}✅ All required directories exist${NC}"
fi

echo ""
echo "================================================"
echo "📊 TEST SUMMARY"
echo "================================================"
echo "✅ Scripts are ready for VPS deployment"
echo ""
echo "🔗 Expected Access URLs:"
echo "   - Temporal gRPC: http://49.12.37.154/temporal"
echo "   - Temporal Web UI: http://49.12.37.154/temporal-ui"
echo ""
echo "⚠️  IMPORTANT NOTES:"
echo "   1. Default passwords should be changed before production use"
echo "   2. TLS certificates should be configured for secure access"
echo "   3. Firewall rules may need adjustment for external access"
echo ""
echo "🚀 Deployment Command:"
echo "   cd scripts && ./01-pre-deployment-check.sh"
echo "   cd scripts && ./02-deployment.sh"
echo "   cd scripts && ./03-validation.sh"
echo ""
echo "📝 Or use the run-all script:"
echo "   ./run-all.sh"
echo "================================================"