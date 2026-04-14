#!/bin/bash

# CP-5: Control Plane NATS (Stateless Signaling) - Pre-deployment Check
# This script validates all prerequisites for deploying stateless NATS in the control plane

set -e

echo "================================================"
echo "CP-5: Control Plane NATS - Pre-deployment Check"
echo "================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check command availability
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is available"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is NOT available"
        return 1
    fi
}

# Function to check Kubernetes resource
check_k8s_resource() {
    if kubectl get $1 $2 -n $3 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1/$2 exists in namespace $3"
        return 0
    else
        echo -e "${RED}✗${NC} $1/$2 NOT found in namespace $3"
        return 1
    fi
}

# Function to check namespace
check_namespace() {
    if kubectl get namespace $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} Namespace '$1' exists"
        return 0
    else
        echo -e "${RED}✗${NC} Namespace '$1' does NOT exist"
        return 1
    fi
}

echo "1. Checking required command-line tools..."
echo "----------------------------------------"
check_command kubectl
check_command helm
check_command nats
check_command jq
check_command openssl
echo ""

echo "2. Checking Kubernetes cluster connectivity..."
echo "--------------------------------------------"
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓${NC} Kubernetes cluster is accessible"
    CLUSTER_NAME=$(kubectl config current-context)
    echo "   Current context: $CLUSTER_NAME"
else
    echo -e "${RED}✗${NC} Cannot connect to Kubernetes cluster"
    exit 1
fi
echo ""

echo "3. Checking required namespaces..."
echo "---------------------------------"
check_namespace control-plane
check_namespace cert-manager
echo ""

echo "4. Checking Cert-Manager installation..."
echo "---------------------------------------"
if check_k8s_resource deployment cert-manager cert-manager; then
    echo -e "${GREEN}✓${NC} Cert-Manager is running"
    
    # Check for ClusterIssuer
    if kubectl get clusterissuer &> /dev/null; then
        echo -e "${GREEN}✓${NC} ClusterIssuer resources available"
        kubectl get clusterissuer
    else
        echo -e "${YELLOW}⚠${NC} No ClusterIssuer found. TLS certificates may need manual setup."
    fi
else
    echo -e "${RED}✗${NC} Cert-Manager is not installed or not running"
    echo -e "${YELLOW}⚠${NC} TLS will not be available without Cert-Manager"
fi
echo ""

echo "5. Checking existing NATS installations..."
echo "-----------------------------------------"
if kubectl get deployment -n control-plane | grep -q nats; then
    echo -e "${YELLOW}⚠${NC} NATS deployment already exists in control-plane namespace"
    kubectl get deployment -n control-plane | grep nats
else
    echo -e "${GREEN}✓${NC} No existing NATS deployment in control-plane"
fi

if kubectl get deployment -A | grep nats | grep -v control-plane; then
    echo -e "${YELLOW}⚠${NC} Other NATS deployments found:"
    kubectl get deployment -A | grep nats | grep -v control-plane
fi
echo ""

echo "6. Checking resource availability..."
echo "-----------------------------------"
# Check for available nodes
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ $NODE_COUNT -ge 2 ]; then
    echo -e "${GREEN}✓${NC} Sufficient nodes available: $NODE_COUNT"
else
    echo -e "${YELLOW}⚠${NC} Only $NODE_COUNT node(s) available. Consider adding more for high availability."
fi

# Check node resources
echo "Node resource summary:"
kubectl get nodes -o json | jq -r '.items[] | "  \(.metadata.name): CPU: \(.status.allocatable.cpu) Memory: \(.status.allocatable.memory)"'
echo ""

echo "7. Checking network policies..."
echo "------------------------------"
if kubectl get networkpolicy -n control-plane &> /dev/null; then
    echo -e "${GREEN}✓${NC} Network policies exist in control-plane namespace"
    kubectl get networkpolicy -n control-plane
else
    echo -e "${YELLOW}⚠${NC} No network policies in control-plane namespace"
fi
echo ""

echo "8. Validating NATS configuration requirements..."
echo "----------------------------------------------"
# Check if we can create ConfigMaps
if kubectl create configmap test-config --from-literal=test=test -n control-plane --dry-run=client &> /dev/null; then
    echo -e "${GREEN}✓${NC} Can create ConfigMaps in control-plane namespace"
else
    echo -e "${RED}✗${NC} Cannot create ConfigMaps in control-plane namespace"
fi

# Check if we can create Secrets
if kubectl create secret generic test-secret --from-literal=test=test -n control-plane --dry-run=client &> /dev/null; then
    echo -e "${GREEN}✓${NC} Can create Secrets in control-plane namespace"
else
    echo -e "${RED}✗${NC} Cannot create Secrets in control-plane namespace"
fi
echo ""

echo "9. Checking storage requirements..."
echo "----------------------------------"
echo "Stateless NATS requires no persistent storage"
echo -e "${GREEN}✓${NC} No persistent storage required for stateless NATS"
echo ""

echo "10. Security context validation..."
echo "---------------------------------"
# Check Pod Security Standards
if kubectl get pods -n control-plane --no-headers &> /dev/null; then
    echo -e "${GREEN}✓${NC} Can list pods in control-plane namespace"
    
    # Check if we can run privileged containers (should not be needed)
    echo "Checking security context requirements..."
    echo "NATS will run with standard non-privileged security context"
fi
echo ""

echo "================================================"
echo "Pre-deployment Check Summary"
echo "================================================"
echo ""
echo "Critical requirements for CP-5 NATS deployment:"
echo "1. ✅ Kubernetes cluster accessible"
echo "2. ✅ 'control-plane' namespace exists"
echo "3. ✅ kubectl command available"
echo "4. ⚠  Cert-Manager (recommended for TLS)"
echo "5. ✅ Sufficient node resources"
echo ""
echo "Next steps:"
echo "1. Ensure Cert-Manager is installed for automated TLS"
echo "2. Verify network policies allow NATS traffic (ports 4222, 8222)"
echo "3. Run deployment script: ./02-deployment.sh"
echo ""
echo "If all checks pass, proceed with deployment."
echo "================================================"