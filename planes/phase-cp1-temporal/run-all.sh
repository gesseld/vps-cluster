#!/bin/bash
set -e

echo "=========================================="
echo "Temporal Server CP-1: Complete Deployment"
echo "=========================================="
echo "This script runs all deployment steps in sequence."
echo

SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

# Step 1: Pre-deployment check
echo "Step 1: Running pre-deployment check..."
echo "----------------------------------------"
if ! ./01-pre-deployment-check.sh; then
    echo "❌ Pre-deployment check failed. Please fix issues before proceeding."
    exit 1
fi
echo

# Step 2: Deployment
echo "Step 2: Deploying Temporal Server..."
echo "------------------------------------"
if ! ./02-deployment.sh; then
    echo "❌ Deployment failed. Check logs for details."
    exit 1
fi
echo

# Step 3: Validation
echo "Step 3: Validating deployment..."
echo "--------------------------------"
if ! ./03-validation.sh; then
    echo "❌ Validation failed. Check deployment status."
    exit 1
fi
echo

echo "=========================================="
echo "✅ Deployment completed successfully!"
echo "=========================================="
echo
echo "Temporal Server is now running with:"
echo "  - 2 HA replicas"
echo "  - Anti-affinity across nodes"
echo "  - Resource limits: 750Mi/1Gi per pod"
echo "  - Network policies for execution-plane access"
echo "  - PodDisruptionBudget (minAvailable: 1)"
echo
echo "Access endpoints:"
echo "  - Frontend: temporal.control-plane.svc.cluster.local:7233"
echo "  - Metrics: temporal.control-plane.svc.cluster.local:9090/metrics"
echo
echo "Next steps:"
echo "  1. Configure workflows in execution-plane to use Temporal"
echo "  2. Set up monitoring and alerting"
echo "  3. Test failover scenarios"
echo
echo "For troubleshooting, see README.md"