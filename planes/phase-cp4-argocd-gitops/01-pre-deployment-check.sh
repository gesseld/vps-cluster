#!/bin/bash

# ArgoCD GitOps Controller - Pre-deployment Check Script
# Validates prerequisites before deploying ArgoCD v2.9+

set -e

echo "=============================================="
echo "ArgoCD GitOps Controller - Pre-deployment Check"
echo "=============================================="

# Load environment variables
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    source .env
fi

# Default values
ARGOCD_NAMESPACE=${ARGOCD_NAMESPACE:-argocd}
ARGOCD_VERSION=${ARGOCD_VERSION:-2.9.0}
GIT_REPO_URL=${GIT_REPO_URL:-git@github.com:your-org/your-repo.git}
GIT_BRANCH=${GIT_BRANCH:-main}
GIT_PATH=${GIT_PATH:-manifests}

echo "Configuration:"
echo "  ArgoCD Namespace: $ARGOCD_NAMESPACE"
echo "  ArgoCD Version: $ARGOCD_VERSION"
echo "  Git Repository: $GIT_REPO_URL"
echo "  Git Branch: $GIT_BRANCH"
echo "  Git Path: $GIT_PATH"
echo ""

# Function to check command availability
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "❌ ERROR: $1 is not installed or not in PATH"
        exit 1
    fi
    echo "✅ $1 is available"
}

# Function to check Kubernetes resource
check_k8s_resource() {
    if kubectl get $1 $2 -n $3 &> /dev/null; then
        echo "✅ $1/$2 exists in namespace $3"
    else
        echo "❌ ERROR: $1/$2 not found in namespace $3"
        exit 1
    fi
}

# Function to check namespace
check_namespace() {
    if kubectl get namespace $1 &> /dev/null; then
        echo "✅ Namespace $1 exists"
    else
        echo "⚠️  Namespace $1 does not exist (will be created during deployment)"
    fi
}

echo "1. Checking required commands..."
check_command kubectl
check_command helm
echo ""

echo "2. Checking Kubernetes cluster access..."
if kubectl cluster-info &> /dev/null; then
    echo "✅ Kubernetes cluster is accessible"
    
    # Check cluster version
    CLUSTER_VERSION=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}')
    echo "   Cluster version: $CLUSTER_VERSION"
    
    # Check if cluster supports required APIs
    if kubectl api-resources | grep -q "applications.argoproj.io"; then
        echo "✅ ArgoCD CRDs are available"
    else
        echo "⚠️  ArgoCD CRDs not installed (will be installed during deployment)"
    fi
else
    echo "❌ ERROR: Cannot connect to Kubernetes cluster"
    echo "   Please ensure kubectl is configured correctly"
    exit 1
fi
echo ""

echo "3. Checking existing ArgoCD installation..."
if kubectl get pods -n $ARGOCD_NAMESPACE 2>/dev/null | grep -q argocd; then
    echo "⚠️  ArgoCD is already installed in namespace $ARGOCD_NAMESPACE"
    echo "   This deployment will update existing installation"
else
    echo "✅ No existing ArgoCD installation found"
fi
echo ""

echo "4. Checking Git repository configuration..."
if [[ -z "$GIT_REPO_URL" ]]; then
    echo "❌ ERROR: Git repository URL is not configured"
    echo "   Please set GIT_REPO_URL in .env file or environment"
    exit 1
fi

# Check if it's the example repository
if [[ "$GIT_REPO_URL" == "https://github.com/argoproj/argocd-example-apps.git" ]]; then
    echo "⚠️  Using ArgoCD example repository for testing"
    echo "   Update GIT_REPO_URL to your actual repository for production use"
fi

# Check if it's SSH or HTTPS URL
if [[ "$GIT_REPO_URL" == git@* ]]; then
    echo "✅ Git repository uses SSH protocol"
    
    # Check for SSH key
    if [[ -f "$HOME/.ssh/id_rsa" || -f "$HOME/.ssh/id_ed25519" ]]; then
        echo "✅ SSH private key found"
    else
        echo "⚠️  No SSH private key found in ~/.ssh/"
        echo "   Please ensure SSH key is configured for Git access"
    fi
else
    echo "✅ Git repository uses HTTPS protocol"
    
    # Check for Git credentials
    if [[ -n "$GIT_USERNAME" && -n "$GIT_PASSWORD" ]]; then
        echo "✅ Git credentials configured"
    else
        echo "⚠️  Git credentials not configured"
        echo "   Please set GIT_USERNAME and GIT_PASSWORD for HTTPS access"
    fi
fi
echo ""

echo "5. Checking Kyverno installation (for rate limiting)..."
if kubectl get pods -n kyverno 2>/dev/null | grep -q kyverno; then
    echo "✅ Kyverno is installed"
    
    # Check for rate limit policy
    if kubectl get clusterpolicy rate-limit-admission 2>/dev/null; then
        echo "✅ Kyverno rate-limit-admission policy exists"
    else
        echo "⚠️  Kyverno rate-limit-admission policy not found"
        echo "   ArgoCD will not be protected by rate limits"
    fi
else
    echo "⚠️  Kyverno is not installed"
    echo "   ArgoCD will not be protected by rate limits"
fi
echo ""

echo "6. Checking resource availability..."
# Check available nodes
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
echo "   Available nodes: $NODE_COUNT"

# Check node resources
echo "   Node resources:"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}: {.status.allocatable.memory} memory, {.status.allocatable.cpu} CPU{end}' | tr '}' '\n' | sed 's/{/   /g'
echo ""

echo "7. Checking storage classes..."
STORAGE_CLASSES=$(kubectl get storageclass --no-headers | wc -l)
echo "   Available storage classes: $STORAGE_CLASSES"
if [ $STORAGE_CLASSES -eq 0 ]; then
    echo "⚠️  No storage classes found"
    echo "   ArgoCD may require storage for Redis"
fi
echo ""

echo "8. Checking network policies..."
if kubectl get networkpolicies -A --no-headers 2>/dev/null | wc -l > /dev/null; then
    echo "✅ Network policies are supported"
else
    echo "⚠️  Network policies may not be supported"
    echo "   Check if CNI plugin supports NetworkPolicy"
fi
echo ""

echo "9. Validating configuration files..."
# Check if required directories exist
if [ -d "control-plane/argocd" ]; then
    echo "✅ control-plane/argocd directory exists"
else
    echo "❌ ERROR: control-plane/argocd directory not found"
    exit 1
fi

# Check for required files
REQUIRED_FILES=(
    "control-plane/argocd/kustomization.yaml"
    "control-plane/argocd/argocd-cm.yaml"
    "control-plane/argocd/resource-quota.yaml"
    "control-plane/argocd/repository-secret.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file exists"
    else
        echo "❌ ERROR: $file not found"
        exit 1
    fi
done

# Check ApplicationSets
APPSET_FILES=$(find control-plane/argocd/applicationsets -name "*.yaml" 2>/dev/null | wc -l)
if [ $APPSET_FILES -ge 5 ]; then
    echo "✅ All 5 ApplicationSet files exist"
else
    echo "⚠️  Only $APPSET_FILES ApplicationSet files found (expected 5)"
fi
echo ""

echo "10. Checking Helm repository access..."
if helm repo add argo https://argoproj.github.io/argo-helm &> /dev/null; then
    echo "✅ ArgoCD Helm repository is accessible"
    helm repo update argo &> /dev/null
else
    echo "⚠️  Cannot access ArgoCD Helm repository"
    echo "   Check internet connectivity"
fi
echo ""

echo "11. Final validation summary..."
echo "=============================================="
echo "Pre-deployment check completed successfully!"
echo ""
echo "Next steps:"
echo "1. Review the configuration above"
echo "2. Ensure Git credentials are properly configured"
echo "3. Run deployment script: ./02-deployment.sh"
echo ""
echo "Configuration summary:"
echo "  - ArgoCD will be installed in namespace: $ARGOCD_NAMESPACE"
echo "  - Git repository: $GIT_REPO_URL"
echo "  - Git branch: $GIT_BRANCH"
echo "  - Single replica mode (non-HA)"
echo "  - Resource quota: 512MB memory limit"
echo "  - Polling disabled, webhooks enabled"
echo "  - Parallelism limit: 5 concurrent kubectl operations"
echo "=============================================="

exit 0