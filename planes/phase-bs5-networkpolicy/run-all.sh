#!/bin/bash

# BS-5 NetworkPolicy - Comprehensive Run Script
# Runs pre-deployment check, deployment, and validation in sequence

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"

MAIN_LOG="${LOG_DIR}/bs5-full-run-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "${MAIN_LOG}") 2>&1

echo "================================================"
echo "BS-5 NetworkPolicy - Full Implementation Run"
echo "Started: $(date)"
echo "================================================"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

run_step() {
    echo -e "${BLUE}[RUNNING]${NC} $1..."
    if bash "$2"; then
        echo -e "${GREEN}[COMPLETED]${NC} $1"
        return 0
    else
        echo -e "${RED}[FAILED]${NC} $1"
        return 1
    fi
}

# Step 1: Pre-deployment check
run_step "Pre-deployment check" "${SCRIPT_DIR}/01-pre-deployment-check.sh"
if [ $? -ne 0 ]; then
    echo "Pre-deployment check failed. Aborting."
    exit 1
fi

echo ""
echo "Pre-deployment check passed. Proceeding with deployment..."
echo ""

# Step 2: Deployment
run_step "Deployment" "${SCRIPT_DIR}/02-deployment.sh"
if [ $? -ne 0 ]; then
    echo "Deployment failed. Check logs for details."
    exit 1
fi

echo ""
echo "Deployment completed. Proceeding with validation..."
echo ""

# Step 3: Validation
run_step "Validation" "${SCRIPT_DIR}/03-validation.sh"
if [ $? -ne 0 ]; then
    echo "Validation failed. Some checks did not pass."
    exit 1
fi

echo ""
echo "================================================"
echo "BS-5 NetworkPolicy - Full Implementation Complete"
echo "================================================"
echo ""
echo "All steps completed successfully!"
echo ""
echo "Summary:"
echo "1. ✓ Pre-deployment checks passed"
echo "2. ✓ NetworkPolicy resources deployed"
echo "3. ✓ Validation tests passed"
echo ""
echo "Created resources:"
echo "  - Default-deny NetworkPolicy template"
echo "  - Plane-specific policy templates"
echo "  - Test namespace with dummy pod"
echo "  - Applied policies for testing"
echo "  - Comprehensive documentation"
echo ""
echo "Next steps:"
echo "1. Review the policies in ${SCRIPT_DIR}/shared/"
echo "2. Apply policies to your production namespaces"
echo "3. Monitor network traffic with the applied policies"
echo ""
echo "Main log file: ${MAIN_LOG}"
echo "================================================"
echo "Completed: $(date)"
echo "================================================"
