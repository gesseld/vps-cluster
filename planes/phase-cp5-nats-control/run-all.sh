#!/bin/bash

# CP-5: Control Plane NATS - Complete Implementation Script
# Runs all phases: pre-deployment check, deployment, and validation

set -e

echo "========================================================"
echo "CP-5: Control Plane NATS - Complete Implementation"
echo "========================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Timestamp for logging
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_DIR="logs"
mkdir -p $LOG_DIR

# Function to run phase with logging
run_phase() {
    local phase_number=$1
    local phase_script=$2
    local phase_name=$3
    
    echo ""
    echo "Phase $phase_number: $phase_name"
    echo "========================================"
    
    if [ -f "$phase_script" ]; then
        echo "Running $phase_script..."
        chmod +x "$phase_script"
        
        # Run script and capture output
        if "./$phase_script" 2>&1 | tee "$LOG_DIR/phase${phase_number}-${TIMESTAMP}.log"; then
            echo -e "${GREEN}✓${NC} Phase $phase_number completed successfully"
            return 0
        else
            echo -e "${RED}✗${NC} Phase $phase_number failed"
            return 1
        fi
    else
        echo -e "${RED}✗${NC} Script not found: $phase_script"
        return 1
    fi
}

# Function to create quick test script
create_test_script() {
    cat > test-nats-quick.sh << 'EOF'
#!/bin/bash
# Quick test for CP-5 NATS deployment

echo "Quick test for CP-5 NATS control plane..."
echo ""

# Check if NATS is running
if kubectl get deployment nats-stateless -n control-plane &> /dev/null; then
    echo "✅ NATS deployment exists"
    
    # Check pod status
    PODS=$(kubectl get pods -n control-plane -l app=nats-stateless --no-headers | wc -l)
    RUNNING_PODS=$(kubectl get pods -n control-plane -l app=nats-stateless --no-headers | grep Running | wc -l)
    
    echo "   Pods: $RUNNING_PODS/$PODS running"
    
    # Test connectivity
    SERVICE_IP=$(kubectl get service nats-stateless -n control-plane -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    if [ -n "$SERVICE_IP" ]; then
        echo "✅ Service IP: $SERVICE_IP"
        
        # Quick port check
        if timeout 2 nc -z $SERVICE_IP 4222; then
            echo "✅ Port 4222 (client) is open"
        else
            echo "❌ Port 4222 is not accessible"
        fi
        
        if timeout 2 nc -z $SERVICE_IP 8222; then
            echo "✅ Port 8222 (monitor) is open"
        else
            echo "❌ Port 8222 is not accessible"
        fi
    fi
else
    echo "❌ NATS deployment not found"
fi

echo ""
echo "For full validation, run: ./03-validation.sh"
EOF
    
    chmod +x test-nats-quick.sh
    echo -e "${GREEN}✓${NC} Created quick test script: test-nats-quick.sh"
}

# Main execution
echo "Starting CP-5 NATS implementation at $(date)"
echo "Logs will be saved to: $LOG_DIR/"
echo ""

# Phase 1: Pre-deployment check
if ! run_phase 1 "01-pre-deployment-check.sh" "Pre-deployment Check"; then
    echo -e "${YELLOW}⚠${NC} Pre-deployment check reported issues. Review logs before continuing."
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Stopping implementation."
        exit 1
    fi
fi

# Phase 2: Deployment
if ! run_phase 2 "02-deployment.sh" "Deployment"; then
    echo -e "${RED}✗${NC} Deployment failed. Check logs: $LOG_DIR/phase2-${TIMESTAMP}.log"
    exit 1
fi

# Wait for deployment to stabilize
echo ""
echo "Waiting for deployment to stabilize (30 seconds)..."
sleep 30

# Phase 3: Validation
if ! run_phase 3 "03-validation.sh" "Validation"; then
    echo -e "${YELLOW}⚠${NC} Validation reported issues. Review logs: $LOG_DIR/phase3-${TIMESTAMP}.log"
    echo "Some tests may have failed. Check the validation report for details."
fi

# Create quick test script
create_test_script

echo ""
echo "========================================================"
echo "Implementation Complete"
echo "========================================================"
echo ""
echo "Summary:"
echo "  ✅ Pre-deployment checks completed"
echo "  ✅ NATS control plane deployed"
echo "  ✅ Validation tests executed"
echo ""
echo "Created resources:"
echo "  • Deployment: nats-stateless (2 replicas)"
echo "  • Service: nats-stateless"
echo "  • ConfigMap: nats-stateless-config"
echo "  • Secrets: nats-auth-secrets"
echo "  • PodDisruptionBudget: nats-stateless-pdb"
echo ""
echo "Access points:"
echo "  • Client: nats-stateless.control-plane.svc.cluster.local:4222"
echo "  • Monitoring: nats-stateless.control-plane.svc.cluster.local:8222"
echo ""
echo "Subjects available:"
echo "  • control.critical.* - Critical control signals"
echo "  • control.audit.* - Audit and logging signals"
echo ""
echo "Accounts configured:"
echo "  • CONTROL (controller) - Full control plane access"
echo "  • AUDIT (auditor) - Audit trail access"
echo "  • SYS (sysadmin) - System monitoring"
echo ""
echo "Quick test:"
echo "  ./test-nats-quick.sh"
echo ""
echo "Full validation report:"
echo "  validation-report.md"
echo ""
echo "Logs directory:"
echo "  $LOG_DIR/"
echo ""
echo "Next steps:"
echo "1. Review validation report for any issues"
echo "2. Update passwords in production (see nats-auth-secrets)"
echo "3. Configure network policies for NATS ports"
echo "4. Set up monitoring and alerting"
echo "5. Connect data plane NATS via leaf nodes (port 7422)"
echo ""
echo "CP-5 implementation completed at $(date)"
echo "========================================================"