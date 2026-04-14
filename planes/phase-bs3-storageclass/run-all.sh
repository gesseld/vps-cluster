#!/bin/bash
# BS-3: StorageClass with WaitForFirstConsumer - Complete Implementation
# Runs all three phases in sequence

set -euo pipefail

echo "================================================================"
echo "BS-3: STORAGECLASS WITH WAITFORFIRSTCONSUMER - COMPLETE RUN"
echo "================================================================"
echo "Running all three phases in sequence"
echo "Date: $(date)"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== PHASE 1: PRE-DEPLOYMENT CHECK ==="
echo ""
if ./01-pre-deployment-check.sh; then
    echo -e "${GREEN}✅ Phase 1 completed successfully${NC}"
    echo ""
else
    echo -e "${RED}❌ Phase 1 failed. Please fix issues before continuing.${NC}"
    exit 1
fi

echo ""
echo "=== PHASE 2: DEPLOYMENT ==="
echo ""
if ./02-deployment.sh; then
    echo -e "${GREEN}✅ Phase 2 completed successfully${NC}"
    echo ""
else
    echo -e "${RED}❌ Phase 2 failed. Check deployment logs.${NC}"
    exit 1
fi

echo ""
echo "=== PHASE 3: VALIDATION ==="
echo ""
if ./03-validation-simple.sh; then
    echo -e "${GREEN}✅ Phase 3 completed successfully${NC}"
    echo ""
else
    echo -e "${RED}❌ Phase 3 failed. Check validation report.${NC}"
    exit 1
fi

echo ""
echo "================================================================"
echo -e "${GREEN}✅ ALL PHASES COMPLETED SUCCESSFULLY${NC}"
echo "================================================================"
echo ""
echo "Summary:"
echo "  - Pre-deployment checks: ✅ PASSED"
echo "  - StorageClass deployment: ✅ COMPLETE"
echo "  - Validation tests: ✅ PASSED"
echo ""
echo "StorageClass 'nvme-waitfirst' is now ready for use with WaitForFirstConsumer."
echo ""
echo "Quick verification:"
echo "  kubectl get storageclass nvme-waitfirst -o jsonpath='{.volumeBindingMode}'"
echo "  # Expected: WaitForFirstConsumer"
echo ""
echo "Next steps:"
echo "  1. Review validation report: VALIDATION_REPORT.md"
echo "  2. Test with your applications"
echo "  3. Monitor volume provisioning"
echo ""
echo "Documentation:"
echo "  - README.md - Overview and usage"
echo "  - CSI_DRIVER_COMPATIBILITY.md - Driver compatibility"
echo "  - shared-storage-classes.yaml - Reference manifests"
echo ""