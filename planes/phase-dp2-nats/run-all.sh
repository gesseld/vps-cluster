#!/bin/bash

set -e

echo "========================================="
echo "NATS JetStream Complete Deployment"
echo "========================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to run a script and check exit code
run_script() {
    local script=$1
    local description=$2
    
    echo ""
    echo "Running: $description"
    echo "-----------------------------------------"
    
    if [ -f "$script" ] && [ -x "$script" ]; then
        if ./"$script"; then
            echo -e "${GREEN}✓ $description completed successfully${NC}"
            return 0
        else
            echo -e "${RED}✗ $description failed${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Script $script not found or not executable${NC}"
        return 1
    fi
}

# Main execution
echo "Starting complete NATS JetStream deployment process..."
echo ""

# Step 1: Pre-deployment check
if ! run_script "01-pre-deployment-check.sh" "Pre-deployment check"; then
    echo -e "${RED}Pre-deployment check failed. Please fix issues and try again.${NC}"
    exit 1
fi

echo ""
read -p "Continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Step 2: Deployment
if ! run_script "02-deployment.sh" "Deployment"; then
    echo -e "${RED}Deployment failed. Check logs above for errors.${NC}"
    exit 1
fi

echo ""
read -p "Continue with validation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Validation skipped."
    echo ""
    echo "Deployment completed. Run ./03-validation.sh manually to validate."
    exit 0
fi

# Step 3: Validation
if ! run_script "03-validation.sh" "Validation"; then
    echo -e "${RED}Validation failed. Some checks did not pass.${NC}"
    echo ""
    echo "Review the validation output above and fix any issues."
    echo "You can re-run validation with: ./03-validation.sh"
    exit 1
fi

echo ""
echo "========================================="
echo -e "${GREEN}✅ NATS JetStream deployment completed successfully!${NC}"
echo "========================================="
echo ""
echo "Summary:"
echo "--------"
echo "• NATS server deployed with JetStream persistence"
echo "• Three streams created: DOCUMENTS, EXECUTION, OBSERVABILITY"
echo "• TLS encryption enabled on client connections"
echo "• Backpressure monitoring configured"
echo "• Network policies applied for access control"
echo ""
echo "Connection Information:"
echo "----------------------"
echo "NATS Server: nats://nats.default.svc.cluster.local:4222"
echo "Monitoring: http://nats.default.svc.cluster.local:8222"
echo "Metrics: http://nats-exporter.default.svc.cluster.local:7777/metrics"
echo ""
echo "Next Steps:"
echo "-----------"
echo "1. Configure your applications to connect to NATS"
echo "2. Use TLS certificates from secret 'nats-tls'"
echo "3. Set up Prometheus alerts for backpressure >80%"
echo "4. Import Grafana dashboard from metrics-exporter.yaml"
echo ""
echo "For troubleshooting:"
echo "• Check logs: kubectl logs deployment/nats -n default"
echo "• Test connection: ./03-validation.sh"
echo "• View streams: kubectl exec deployment/nats -n default -- nats stream list"
echo ""