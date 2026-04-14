#!/bin/bash

# SF-3 NetworkPolicy Default-Deny Pre-deployment Check Script
# This script ensures all prerequisites are met before deploying network policies

set -e

echo "================================================"
echo "SF-3 NetworkPolicy Default-Deny Pre-deployment Check"
echo "================================================"
echo ""

# Color codes for output
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
        echo -e "${RED}✗${NC} $1/$2 does NOT exist in namespace $3"
        return 1
    fi
}

# Function to check namespace
check_namespace() {
    if kubectl get namespace $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} Namespace $1 exists"
        return 0
    else
        echo -e "${RED}✗${NC} Namespace $1 does NOT exist"
        return 1
    fi
}

# Function to check CNI supports NetworkPolicy
check_cni_networkpolicy() {
    echo "Checking CNI NetworkPolicy support..."
    
    # Check if Cilium is installed (common CNI that supports NetworkPolicy)
    if kubectl get daemonset -n kube-system cilium &> /dev/null; then
        echo -e "${GREEN}✓${NC} Cilium CNI detected (supports NetworkPolicy)"
        return 0
    fi
    
    # Check if Calico is installed
    if kubectl get daemonset -n kube-system calico-node &> /dev/null; then
        echo -e "${GREEN}✓${NC} Calico CNI detected (supports NetworkPolicy)"
        return 0
    fi
    
    # Check if Weave is installed
    if kubectl get daemonset -n kube-system weave-net &> /dev/null; then
        echo -e "${GREEN}✓${NC} Weave Net CNI detected (supports NetworkPolicy)"
        return 0
    fi
    
    # Generic check for NetworkPolicy support
    if kubectl api-resources | grep -q networkpolicies; then
        echo -e "${GREEN}✓${NC} NetworkPolicy API resource is available"
        return 0
    else
        echo -e "${RED}✗${NC} NetworkPolicy API resource is NOT available"
        echo -e "${YELLOW}⚠${NC} Your CNI may not support NetworkPolicy"
        return 1
    fi
}

echo "1. Checking required commands..."
echo "--------------------------------"

# Check for kubectl
check_command kubectl || {
    echo -e "${RED}Error: kubectl is required but not found${NC}"
    exit 1
}

# Check for curl (for validation tests)
check_command curl || echo -e "${YELLOW}Warning: curl not found (needed for validation tests)${NC}"

echo ""
echo "2. Checking Kubernetes cluster connectivity..."
echo "--------------------------------"

# Check kubectl connectivity
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✓${NC} Successfully connected to Kubernetes cluster"
    
    # Get cluster info
    CLUSTER_NAME=$(kubectl config current-context)
    echo -e "   Cluster context: $CLUSTER_NAME"
    
    # Check cluster version
    K8S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}')
    echo -e "   Kubernetes version: $K8S_VERSION"
else
    echo -e "${RED}✗${NC} Cannot connect to Kubernetes cluster"
    echo -e "${RED}Error: Check your kubeconfig and cluster connectivity${NC}"
    exit 1
fi

echo ""
echo "3. Checking CNI NetworkPolicy support..."
echo "--------------------------------"

check_cni_networkpolicy || {
    echo -e "${YELLOW}Warning: NetworkPolicy support may be limited${NC}"
}

echo ""
echo "4. Checking foundation namespaces..."
echo "--------------------------------"

# List of foundation namespaces from the project
FOUNDATION_NAMESPACES=(
    "control-plane"
    "data-plane" 
    "observability"
    "security"
    "network"
    "storage"
)

ALL_NAMESPACES_EXIST=true
for ns in "${FOUNDATION_NAMESPACES[@]}"; do
    if ! check_namespace "$ns"; then
        ALL_NAMESPACES_EXIST=false
    fi
done

if [ "$ALL_NAMESPACES_EXIST" = false ]; then
    echo -e "${YELLOW}⚠${NC} Some foundation namespaces are missing"
    echo -e "${YELLOW}   Consider creating missing namespaces before proceeding${NC}"
fi

echo ""
echo "5. Checking existing NetworkPolicies..."
echo "--------------------------------"

EXISTING_POLICIES=$(kubectl get networkpolicies --all-namespaces 2>/dev/null | wc -l)
if [ "$EXISTING_POLICIES" -gt 1 ]; then
    echo -e "${YELLOW}⚠${NC} Found existing NetworkPolicies:"
    kubectl get networkpolicies --all-namespaces 2>/dev/null
    echo -e "${YELLOW}   These may conflict with new default-deny policies${NC}"
else
    echo -e "${GREEN}✓${NC} No existing NetworkPolicies found"
fi

echo ""
echo "6. Checking essential services for interface matrix..."
echo "--------------------------------"

# Check for common services that will need explicit allow rules
ESSENTIAL_SERVICES=(
    "kube-dns.kube-system"
    "postgres.data-plane"
    "redis.data-plane"
    "grafana.observability"
    "prometheus.observability"
)

for service in "${ESSENTIAL_SERVICES[@]}"; do
    svc_name=$(echo $service | cut -d'.' -f1)
    svc_ns=$(echo $service | cut -d'.' -f2)
    
    if check_k8s_resource service "$svc_name" "$svc_ns"; then
        echo -e "   ${GREEN}✓${NC} Service $svc_name will need explicit allow rule"
    else
        echo -e "   ${YELLOW}⚠${NC} Service $svc_name not found (may not need allow rule)"
    fi
done

echo ""
echo "7. Checking RBAC from previous phase (SF-2)..."
echo "--------------------------------"

# Check if RBAC was properly applied
if kubectl get clusterrole network-policy-admin &> /dev/null; then
    echo -e "${GREEN}✓${NC} NetworkPolicy admin cluster role exists"
else
    echo -e "${YELLOW}⚠${NC} NetworkPolicy admin cluster role not found"
    echo -e "${YELLOW}   RBAC from SF-2 may not be fully applied${NC}"
fi

echo ""
echo "8. Checking for test resources..."
echo "--------------------------------"

# Check if test pods can be created
TEST_NS="networkpolicy-test"
if kubectl create namespace $TEST_NS --dry-run=client -o yaml &> /dev/null; then
    echo -e "${GREEN}✓${NC} Can create test namespace"
else
    echo -e "${RED}✗${NC} Cannot create test namespace (RBAC issue?)"
fi

echo ""
echo "================================================"
echo "Pre-deployment Check Summary"
echo "================================================"

if [ "$ALL_NAMESPACES_EXIST" = true ] && command -v kubectl &> /dev/null; then
    echo -e "${GREEN}✅ All critical checks passed${NC}"
    echo ""
    echo "Ready to proceed with SF-3 NetworkPolicy deployment."
    echo "Run the deployment script: ./sf3-networkpolicy-deploy.sh"
else
    echo -e "${YELLOW}⚠ Some checks require attention${NC}"
    echo ""
    echo "Please address the warnings above before proceeding."
    echo "Critical issues must be resolved before deployment."
fi

echo ""
echo "Next steps:"
echo "1. Review any warnings above"
echo "2. Create missing namespaces if needed"
echo "3. Document known dependencies in interface matrix"
echo "4. Proceed with deployment script"

exit 0