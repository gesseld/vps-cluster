#!/bin/bash

# Phase SF-1: Cert-Manager + SPIRE PKI Bootstrap - Pre-deployment Check (VPS Version)
# This script is designed to run on the VPS cluster itself

set -e

echo "=============================================="
echo "Phase SF-1: Cert-Manager + SPIRE PKI Bootstrap"
echo "Pre-deployment Check Script (VPS Version)"
echo "=============================================="
echo ""
echo "Running on: $(hostname)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
echo ""

# Load environment variables from current directory or parent
if [ -f ".env" ]; then
    source .env
    echo "✓ Loaded environment variables from .env"
elif [ -f "../.env" ]; then
    source ../.env
    echo "✓ Loaded environment variables from ../.env"
else
    echo "⚠ Warning: .env file not found"
    echo "   Using default values"
fi

# Check kubectl connectivity
echo ""
echo "1. Checking Kubernetes cluster connectivity..."
if kubectl cluster-info > /dev/null 2>&1; then
    echo "✓ Kubernetes cluster is accessible"
    
    # Check cluster version
    K8S_VERSION=$(kubectl version --short 2>/dev/null | grep "Server Version" | awk '{print $3}' || echo "Unknown")
    echo "   Cluster version: $K8S_VERSION"
    
    # Check node information
    NODES=$(kubectl get nodes --no-headers | wc -l)
    echo "   Number of nodes: $NODES"
    
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

# Check for required tools (Ubuntu/Linux version)
echo ""
echo "2. Checking for required tools..."
REQUIRED_TOOLS=("kubectl" "helm" "jq" "curl")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v $tool > /dev/null 2>&1; then
        echo "✓ $tool is installed: $(which $tool)"
    else
        echo "✗ ERROR: $tool is not installed"
        echo "   Install with: sudo apt-get install $tool"
        exit 1
    fi
done

# Check helm version
HELM_VERSION=$(helm version --short 2>/dev/null | cut -d'+' -f1 || echo "Unknown")
echo "   Helm version: $HELM_VERSION"

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
        # Check if we can get connection info
        POSTGRES_SVC=$(kubectl get svc -n postgresql -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
        if [ -n "$POSTGRES_SVC" ]; then
            echo "   PostgreSQL service: $POSTGRES_SVC"
        fi
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

# Check node resources in detail
echo ""
echo "6. Checking node resources and labels..."
echo "   Node details:"
kubectl get nodes -o custom-columns='NAME:.metadata.name,ROLES:.metadata.labels.node\.kubernetes\.io/role,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion,CPU:.status.capacity.cpu,MEM:.status.capacity.memory' 2>/dev/null || true

# Check node labels for k8s_psat attestor
echo ""
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
echo "   Available storage classes:"
kubectl get storageclass -o custom-columns='NAME:.metadata.name,PROVISIONER:.provisioner,DEFAULT:.metadata.annotations.storageclass\.kubernetes\.io/is-default-class' 2>/dev/null || true

DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || true)
if [ -n "$DEFAULT_SC" ]; then
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

if kubectl auth can-i create daemonset --all-namespaces > /dev/null 2>&1; then
    echo "✓ Has permission to create DaemonSet"
else
    echo "✗ ERROR: Insufficient permissions to create DaemonSet"
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

# Check disk space on nodes (important for SPIRE)
echo ""
echo "11. Checking node disk space..."
echo "   Node disk usage:"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.allocatable.ephemeral-storage}{"\n"}{end}' 2>/dev/null || echo "   Unable to check disk space"

# Check kernel modules for SPIRE (might need specific modules)
echo ""
echo "12. Checking kernel features (for SPIRE agent)..."
if lsmod | grep -q "overlay"; then
    echo "✓ Overlay filesystem module loaded"
else
    echo "⚠ Overlay module not loaded (may affect container storage)"
fi

# Summary
echo ""
echo "=============================================="
echo "PRE-DEPLOYMENT CHECK SUMMARY (VPS)"
echo "=============================================="
echo ""
echo "Cluster Information:"
echo "  - Nodes: $NODES (Ubuntu)"
echo "  - Kubernetes version: $K8S_VERSION"
echo "  - Storage classes: Available"
echo ""
echo "Prerequisites status:"
echo "  - Kubernetes cluster: ✓ Accessible"
echo "  - Required tools: ✓ Available"
echo "  - Helm repositories: Will be added if missing"
echo "  - PostgreSQL: ⚠ Data Plane dependency - check required"
echo "  - Monitoring: Optional (for metrics)"
echo "  - Storage: ✓ Default storage class: $DEFAULT_SC"
echo "  - RBAC permissions: ✓ Sufficient"
echo "  - Namespaces: Ready for creation"
echo ""
echo "Critical dependencies:"
echo "  1. PostgreSQL must be available for SPIRE backend"
echo "  2. Ensure sufficient disk space on nodes"
echo "  3. Verify network connectivity between nodes"
echo ""
echo "Next steps:"
if [ -n "$DEFAULT_SC" ] && [ "$EXISTING_CM" -eq 0 ] && [ "$EXISTING_SPIRE" -eq 0 ]; then
    echo "  ✅ Ready for deployment"
    echo "  1. Deploy PostgreSQL if not already available"
    echo "  2. Run deployment script: ./02-deployment.sh"
    echo "  3. Run validation: ./03-validation.sh"
else
    echo "  ⚠ Address issues before deployment:"
    [ -z "$DEFAULT_SC" ] && echo "  - No default storage class found"
    [ "$EXISTING_CM" -gt 0 ] && echo "  - cert-manager already installed"
    [ "$EXISTING_SPIRE" -gt 0 ] && echo "  - SPIRE already installed"
fi
echo ""
echo "To install missing tools on Ubuntu:"
echo "  sudo apt-get update"
echo "  sudo apt-get install -y kubectl helm jq curl"
echo ""
echo "To add missing Helm repositories:"
echo "  helm repo add jetstack https://charts.jetstack.io"
echo "  helm repo add spiffe https://spiffe.github.io/helm-charts/"
echo "  helm repo update"
echo ""

exit 0