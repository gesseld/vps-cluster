#!/bin/bash

# Phase SF-1: Cert-Manager + SPIRE PKI Bootstrap - Pre-deployment Check
# This script ensures all prerequisites are met before deployment

set -e

echo "=============================================="
echo "Phase SF-1: Cert-Manager + SPIRE PKI Bootstrap"
echo "Pre-deployment Check Script"
echo "=============================================="
echo ""

# Load environment variables
if [ -f "../.env" ]; then
    source ../.env
    echo "✓ Loaded environment variables from ../.env"
else
    echo "⚠ Warning: ../.env file not found"
fi

# Check kubectl connectivity
echo ""
echo "1. Checking Kubernetes cluster connectivity..."
if kubectl cluster-info > /dev/null 2>&1; then
    echo "✓ Kubernetes cluster is accessible"
    
    # Check cluster version
    K8S_VERSION=$(kubectl version --short 2>/dev/null | grep "Server Version" | awk '{print $3}')
    echo "   Cluster version: $K8S_VERSION"
    
    # Check if cert-manager CRDs already exist
    if kubectl get crd | grep -q "certificaterequests.cert-manager.io"; then
        echo "⚠ Warning: cert-manager CRDs already exist"
    else
        echo "✓ cert-manager CRDs not found (good for fresh install)"
    fi
    
    # Check for existing SPIRE resources
    if kubectl get ns | grep -q "spire"; then
        echo "⚠ Warning: 'spire' namespace already exists"
    fi
else
    echo "✗ ERROR: Cannot connect to Kubernetes cluster"
    echo "   Please ensure kubectl is configured correctly"
    exit 1
fi

# Check for required tools
echo ""
echo "2. Checking for required tools..."
REQUIRED_TOOLS=("kubectl" "helm" "jq" "curl")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v $tool > /dev/null 2>&1; then
        echo "✓ $tool is installed"
    else
        # Special handling for jq which might be in project directory
        if [ "$tool" = "jq" ] && [ -f "../../jq.exe" ]; then
            echo "✓ jq is available in project directory (../../jq.exe)"
        else
            echo "✗ ERROR: $tool is not installed"
            exit 1
        fi
    fi
done

# Check helm repositories
echo ""
echo "3. Checking Helm repositories..."
if helm repo list | grep -q "jetstack"; then
    echo "✓ jetstack Helm repo already added"
else
    echo "⚠ jetstack Helm repo not added (will be added during deployment)"
fi

if helm repo list | grep -q "spiffe"; then
    echo "✓ spiffe Helm repo already added"
else
    echo "⚠ spiffe Helm repo not added (will be added during deployment)"
fi

# Check for PostgreSQL dependency (Data Plane dependency noted in requirements)
echo ""
echo "4. Checking PostgreSQL availability..."
if kubectl get pods -n postgresql 2>/dev/null | grep -q "postgresql"; then
    echo "✓ PostgreSQL is running in 'postgresql' namespace"
    # Test connection
    POSTGRES_POD=$(kubectl get pods -n postgresql -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$POSTGRES_POD" ]; then
        echo "   PostgreSQL pod: $POSTGRES_POD"
    fi
else
    echo "⚠ PostgreSQL not found in 'postgresql' namespace"
    echo "   Note: SPIRE requires PostgreSQL backend (Data Plane dependency)"
    echo "   This will need to be deployed separately if not available"
fi

# Check for monitoring stack (vmagent for metrics)
echo ""
echo "5. Checking monitoring stack..."
if kubectl get pods -n monitoring 2>/dev/null | grep -q "vmagent"; then
    echo "✓ vmagent is running in 'monitoring' namespace"
else
    echo "⚠ vmagent not found in 'monitoring' namespace"
    echo "   SPIRE metrics will be exported but may not be collected"
fi

# Check node resources
echo ""
echo "6. Checking node resources..."
NODES=$(kubectl get nodes --no-headers | wc -l)
echo "   Number of nodes: $NODES"

# Check node labels for k8s_psat attestor
echo "   Checking node labels for k8s_psat attestor..."
NODE_WITH_LABELS=0
for node in $(kubectl get nodes -o name | cut -d'/' -f2); do
    if kubectl get node $node --show-labels | grep -q "node-role.kubernetes.io/"; then
        NODE_WITH_LABELS=$((NODE_WITH_LABELS + 1))
    fi
done
echo "   Nodes with role labels: $NODE_WITH_LABELS/$NODES"

# Check for existing cert-manager or SPIRE installations
echo ""
echo "7. Checking for existing installations..."
EXISTING_CM=$(helm list -A | grep -c "cert-manager" || true)
EXISTING_SPIRE=$(helm list -A | grep -c "spire" || true)

if [ "$EXISTING_CM" -gt 0 ]; then
    echo "⚠ cert-manager is already installed ($EXISTING_CM instances)"
    echo "   Namespaces:"
    helm list -A | grep "cert-manager" | awk '{print "   - " $2}'
fi

if [ "$EXISTING_SPIRE" -gt 0 ]; then
    echo "⚠ SPIRE is already installed ($EXISTING_SPIRE instances)"
    echo "   Namespaces:"
    helm list -A | grep "spire" | awk '{print "   - " $2}'
fi

if [ "$EXISTING_CM" -eq 0 ] && [ "$EXISTING_SPIRE" -eq 0 ]; then
    echo "✓ No existing cert-manager or SPIRE installations found"
fi

# Check storage class for SPIRE server PVC
echo ""
echo "8. Checking storage classes..."
STORAGE_CLASSES=$(kubectl get storageclass --no-headers | wc -l)
echo "   Available storage classes: $STORAGE_CLASSES"
if kubectl get storageclass --no-headers | grep -q "(default)"; then
    DEFAULT_SC=$(kubectl get storageclass | grep "(default)" | awk '{print $1}')
    echo "   Default storage class: $DEFAULT_SC"
else
    echo "⚠ No default storage class found"
    echo "   SPIRE server StatefulSet requires PVC"
fi

# Check RBAC permissions
echo ""
echo "9. Checking RBAC permissions..."
if kubectl auth can-i create clusterissuer --all-namespaces > /dev/null 2>&1; then
    echo "✓ Has permission to create ClusterIssuer"
else
    echo "✗ ERROR: Insufficient permissions to create ClusterIssuer"
    echo "   Need cluster-admin or equivalent role"
fi

if kubectl auth can-i create statefulset --all-namespaces > /dev/null 2>&1; then
    echo "✓ Has permission to create StatefulSet"
else
    echo "✗ ERROR: Insufficient permissions to create StatefulSet"
fi

# Check for required namespaces
echo ""
echo "10. Checking required namespaces..."
REQUIRED_NS=("cert-manager" "spire" "foundation")
for ns in "${REQUIRED_NS[@]}"; do
    if kubectl get ns $ns > /dev/null 2>&1; then
        echo "⚠ Namespace '$ns' already exists"
    else
        echo "✓ Namespace '$ns' will be created"
    fi
done

# Summary
echo ""
echo "=============================================="
echo "PRE-DEPLOYMENT CHECK SUMMARY"
echo "=============================================="
echo ""
echo "Prerequisites met:"
echo "  - Kubernetes cluster: ✓"
echo "  - Required tools: ✓"
echo "  - Helm repositories: Will be added if missing"
echo "  - PostgreSQL: Note: Data Plane dependency"
echo "  - Monitoring: Optional (for metrics)"
echo "  - Storage class: Checked"
echo "  - RBAC permissions: Checked"
echo ""
echo "Next steps:"
echo "  1. Ensure PostgreSQL is available for SPIRE backend"
echo "  2. Run 02-deployment.sh to deploy Cert-Manager and SPIRE"
echo "  3. Run 03-validation.sh to verify deployment"
echo ""
echo "To proceed with deployment, run:"
echo "  ./02-deployment.sh"
echo ""

exit 0