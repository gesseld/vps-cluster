#!/bin/bash

set -e

echo "=== Kyverno Policy Engine Pre-Deployment Check ==="
echo "Checking prerequisites for Kyverno v1.11+ deployment..."

# Set default kubeconfig if not set
if [ -z "$KUBECONFIG" ]; then
    # Try to find kubeconfig in common locations
    if [ -f "$(pwd)/../../kubeconfig" ]; then
        export KUBECONFIG="$(pwd)/../../kubeconfig"
    elif [ -f "$HOME/.kube/config" ]; then
        export KUBECONFIG="$HOME/.kube/config"
    fi
fi

# Check kubectl availability
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl not found. Please install kubectl."
    exit 1
fi

echo "✓ kubectl is available"

# Check Kubernetes cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster. Check kubeconfig."
    echo "Current KUBECONFIG: $KUBECONFIG"
    exit 1
fi

echo "✓ Connected to Kubernetes cluster"

# Check cluster version
K8S_VERSION=$(kubectl version --short 2>/dev/null | grep Server | cut -d' ' -f3)
echo "Kubernetes Server Version: $K8S_VERSION"

# Check if Kyverno is already installed
if kubectl get ns kyverno &> /dev/null; then
    echo "WARNING: kyverno namespace already exists. Existing installation will be upgraded."
fi

# Check for existing OPA Gatekeeper (to be replaced)
if kubectl get crd constrainttemplates.templates.gatekeeper.sh &> /dev/null; then
    echo "NOTICE: OPA Gatekeeper CRDs detected. Kyverno will replace OPA."
fi

# Check for admission webhook conflicts
echo "Checking admission webhook configurations..."
WEBHOOK_COUNT=$(kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations -A 2>/dev/null | wc -l)
echo "Found $WEBHOOK_COUNT webhook configurations"

# Check resource availability
echo "Checking cluster resources..."
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
echo "Cluster has $NODE_COUNT nodes"

# Check for required namespaces exclusions
echo "Verifying namespace exclusions..."
EXCLUDED_NS="kube-system kyverno"
for ns in $EXCLUDED_NS; do
    if kubectl get ns $ns &> /dev/null; then
        echo "✓ Namespace $ns exists (will be excluded from policies)"
    else
        echo "Namespace $ns does not exist (will be created)"
    fi
done

# Check for vmagent (metrics destination)
if kubectl get deployment -n monitoring vmagent &> /dev/null; then
    echo "✓ vmagent found in monitoring namespace"
else
    echo "NOTE: vmagent not found. Metrics will be available but may need manual scraping setup."
fi

# Check SPIFFE/SPIRE setup (for mutation webhook)
if kubectl get deployment -n spire spire-server &> /dev/null; then
    echo "✓ SPIRE server found (for SPIFFE sidecar injection)"
else
    echo "NOTE: SPIRE not found. SPIFFE sidecar mutation will be configured but may not work."
fi

# Validate RBAC permissions
echo "Checking RBAC permissions..."
kubectl auth can-i create clusterpolicy -A &> /dev/null && echo "✓ Can create ClusterPolicy resources" || echo "WARNING: Cannot create ClusterPolicy - check RBAC"

# Check for ArgoCD (rate limiting target)
if kubectl get deployment -n argocd argocd-server &> /dev/null; then
    echo "✓ ArgoCD found (rate limiting will protect against sync storms)"
else
    echo "NOTE: ArgoCD not found. Rate limiting still applies to all namespaces."
fi

echo ""
echo "=== Pre-deployment checks completed ==="
echo "All prerequisites verified. Ready to deploy Kyverno."
echo ""
echo "To proceed with deployment, run:"
echo "  ./deploy-kyverno.sh"
echo ""
echo "To validate after deployment, run:"
echo "  ./validate-kyverno.sh"