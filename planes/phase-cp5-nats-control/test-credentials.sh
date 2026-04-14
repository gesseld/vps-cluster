#!/bin/bash

# CP-5: Test NATS credentials and connectivity
# Quick test script for validating NATS authentication

set -e

echo "========================================"
echo "CP-5 NATS Credentials Test"
echo "========================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
NAMESPACE="control-plane"
SERVICE="nats-stateless"
PORT="4222"

# Function to test account
test_account() {
    local account=$1
    local user=$2
    local password=$3
    
    echo -n "Testing $account account ($user)... "
    
    # Get password from secret if not provided
    if [ -z "$password" ]; then
        password=$(kubectl get secret nats-auth-secrets -n $NAMESPACE -o jsonpath="{.data.${account}-password}" 2>/dev/null | base64 -d || echo "changeme")
    fi
    
    # Test connection
    if nats server info --server "$SERVICE.$NAMESPACE.svc.cluster.local:$PORT" --user "$user" --password "$password" &> /dev/null; then
        echo -e "${GREEN}PASS${NC}"
        echo "  Password: $password"
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        return 1
    fi
}

echo "1. Checking Kubernetes resources..."
echo "---------------------------------"

# Check if NATS is deployed
if kubectl get deployment nats-stateless -n $NAMESPACE &> /dev/null; then
    echo -e "${GREEN}✓${NC} NATS deployment exists"
else
    echo -e "${RED}✗${NC} NATS deployment not found"
    exit 1
fi

# Check service
SERVICE_IP=$(kubectl get service $SERVICE -n $NAMESPACE -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [ -n "$SERVICE_IP" ]; then
    echo -e "${GREEN}✓${NC} Service IP: $SERVICE_IP"
else
    echo -e "${RED}✗${NC} Service not found"
    exit 1
fi

echo ""
echo "2. Testing connectivity..."
echo "-------------------------"

# Test basic connectivity
if timeout 2 nc -z $SERVICE_IP $PORT; then
    echo -e "${GREEN}✓${NC} Port $PORT is open"
else
    echo -e "${RED}✗${NC} Port $PORT is not accessible"
    exit 1
fi

echo ""
echo "3. Testing authentication..."
echo "---------------------------"

# Test each account
test_account "controller" "controller"
test_account "auditor" "auditor"
test_account "sysadmin" "sysadmin"

echo ""
echo "4. Testing subject publishing..."
echo "-------------------------------"

# Get controller password
CONTROLLER_PASSWORD=$(kubectl get secret nats-auth-secrets -n $NAMESPACE -o jsonpath='{.data.controller-password}' 2>/dev/null | base64 -d || echo "changeme")

# Test publish to critical subject
echo -n "Publishing to control.critical.test... "
if echo "test message $(date)" | nats pub control.critical.test --server "$SERVICE.$NAMESPACE.svc.cluster.local:$PORT" --user "controller" --password "$CONTROLLER_PASSWORD" &> /dev/null; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
fi

# Test publish to audit subject
echo -n "Publishing to control.audit.test... "
if echo "audit message $(date)" | nats pub control.audit.test --server "$SERVICE.$NAMESPACE.svc.cluster.local:$PORT" --user "auditor" --password "$CONTROLLER_PASSWORD" &> /dev/null; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
fi

echo ""
echo "5. Testing monitoring endpoint..."
echo "--------------------------------"

MONITOR_PORT="8222"
if timeout 2 nc -z $SERVICE_IP $MONITOR_PORT; then
    echo -e "${GREEN}✓${NC} Monitoring port $MONITOR_PORT is open"
    
    # Test monitoring endpoint
    if curl -s "http://$SERVICE_IP:$MONITOR_PORT/" &> /dev/null; then
        echo -e "${GREEN}✓${NC} Monitoring endpoint is accessible"
        
        # Get server info
        SERVER_INFO=$(curl -s "http://$SERVICE_IP:$MONITOR_PORT/varz" 2>/dev/null || true)
        if echo "$SERVER_INFO" | grep -q "server_name"; then
            SERVER_NAME=$(echo "$SERVER_INFO" | grep '"server_name"' | head -1 | cut -d'"' -f4)
            echo -e "${GREEN}✓${NC} Server: $SERVER_NAME"
        fi
    fi
else
    echo -e "${YELLOW}⚠${NC} Monitoring port not accessible"
fi

echo ""
echo "========================================"
echo "Credentials Test Summary"
echo "========================================"
echo ""
echo "Connection string examples:"
echo ""
echo "Controller account:"
echo "  nats://controller:$CONTROLLER_PASSWORD@$SERVICE.$NAMESPACE.svc.cluster.local:$PORT"
echo ""
echo "Auditor account:"
AUDITOR_PASSWORD=$(kubectl get secret nats-auth-secrets -n $NAMESPACE -o jsonpath='{.data.auditor-password}' 2>/dev/null | base64 -d || echo "changeme")
echo "  nats://auditor:$AUDITOR_PASSWORD@$SERVICE.$NAMESPACE.svc.cluster.local:$PORT"
echo ""
echo "Monitoring:"
echo "  http://$SERVICE.$NAMESPACE.svc.cluster.local:8222"
echo ""
echo "Quick test command:"
echo "  nats sub control.critical.> --server $SERVICE.$NAMESPACE.svc.cluster.local:$PORT --user controller --password \"$CONTROLLER_PASSWORD\""
echo ""
echo "Test completed successfully!"
echo "========================================"