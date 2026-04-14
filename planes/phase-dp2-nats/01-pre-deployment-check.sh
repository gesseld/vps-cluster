#!/bin/bash

set -e

echo "========================================="
echo "NATS JetStream Pre-Deployment Check"
echo "========================================="

# Source environment variables if .env exists
if [ -f .env ]; then
    echo "Loading environment variables from .env"
    source .env
fi

# Default values
NAMESPACE=${NAMESPACE:-default}
NATS_VERSION=${NATS_VERSION:-2.10}
HELM_REPO=${HELM_REPO:-nats}
HELM_CHART=${HELM_CHART:-nats}
HELM_CHART_VERSION=${HELM_CHART_VERSION:-1.0.0}

echo "Checking prerequisites for NATS JetStream deployment..."

# 1. Check kubectl access
echo -n "1. Checking kubectl access... "
if command -v kubectl &> /dev/null; then
    if kubectl cluster-info &> /dev/null; then
        echo "✓ OK"
        echo "   Cluster: $(kubectl config current-context)"
        echo "   API Server: $(kubectl cluster-info | grep -E 'Kubernetes control plane|master' | head -1 | cut -d' ' -f7-)"
    else
        echo "✗ FAILED"
        echo "   Error: Cannot connect to Kubernetes cluster"
        exit 1
    fi
else
    echo "✗ FAILED"
    echo "   Error: kubectl not found in PATH"
    exit 1
fi

# 2. Check namespace
echo -n "2. Checking namespace '$NAMESPACE'... "
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "✓ OK"
else
    echo "✗ FAILED"
    echo "   Error: Namespace '$NAMESPACE' does not exist"
    echo "   Creating namespace..."
    kubectl create namespace "$NAMESPACE"
    echo "   ✓ Namespace created"
fi

# 3. Check Helm
echo -n "3. Checking Helm installation... "
if command -v helm &> /dev/null; then
    echo "✓ OK"
    echo "   Helm version: $(helm version --short)"
else
    echo "✗ FAILED"
    echo "   Error: Helm not found in PATH"
    exit 1
fi

# 4. Check NATS Helm repo
echo -n "4. Checking NATS Helm repository... "
if helm repo list | grep -q "$HELM_REPO"; then
    echo "✓ OK"
else
    echo "✗ NOT FOUND"
    echo "   Adding NATS Helm repository..."
    helm repo add "$HELM_REPO" https://nats-io.github.io/k8s/helm/charts/
    helm repo update
    echo "   ✓ Repository added and updated"
fi

# 5. Check available nodes
echo -n "5. Checking available nodes... "
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -ge 1 ]; then
    echo "✓ OK ($NODE_COUNT nodes available)"
    kubectl get nodes -o wide | awk 'NR==1 || NR<=4'
else
    echo "✗ FAILED"
    echo "   Error: No nodes available in cluster"
    exit 1
fi

# 6. Check storage class (for JetStream persistence)
echo -n "6. Checking storage classes... "
STORAGE_CLASSES=$(kubectl get storageclass --no-headers | wc -l)
if [ "$STORAGE_CLASSES" -gt 0 ]; then
    echo "✓ OK ($STORAGE_CLASSES storage classes available)"
    kubectl get storageclass
else
    echo "⚠ WARNING"
    echo "   No storage classes found. JetStream persistence may not work properly."
fi

# 7. Check existing NATS resources
echo -n "7. Checking for existing NATS resources... "
EXISTING_NATS=$(kubectl get pods -n "$NAMESPACE" -l app=nats 2>/dev/null | wc -l)
if [ "$EXISTING_NATS" -gt 1 ]; then
    echo "⚠ WARNING"
    echo "   Existing NATS pods found in namespace '$NAMESPACE':"
    kubectl get pods -n "$NAMESPACE" -l app=nats
    echo ""
    read -p "   Do you want to continue? Existing resources may be modified. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "   Deployment cancelled."
        exit 0
    fi
else
    echo "✓ OK (No existing NATS resources found)"
fi

# 8. Check resource availability
echo -n "8. Checking cluster resource availability... "
TOTAL_CPU=$(kubectl describe nodes | grep -E "cpu:[[:space:]]*[0-9]+" | awk '{sum += $2} END {print sum}')
TOTAL_MEM=$(kubectl describe nodes | grep -E "memory:[[:space:]]*[0-9]+" | awk '{sum += $2} END {print sum/1024/1024 " Gi"}')
echo "✓ OK"
echo "   Total CPU: ${TOTAL_CPU:-Unknown}"
echo "   Total Memory: ${TOTAL_MEM:-Unknown}"

# 9. Check for required tools (nats CLI)
echo -n "9. Checking for NATS CLI... "
if command -v nats &> /dev/null; then
    echo "✓ OK"
    echo "   NATS CLI version: $(nats --version 2>/dev/null | head -1 || echo "Unknown")"
else
    echo "⚠ WARNING"
    echo "   NATS CLI not found. Validation steps requiring 'nats' command may fail."
    echo "   Install with: brew install nats-io/nats-tools/nats or download from https://github.com/nats-io/natscli"
fi

# 10. Check for monitoring stack (optional)
echo -n "10. Checking for monitoring stack... "
if kubectl get pods -n monitoring 2>/dev/null | grep -q prometheus; then
    echo "✓ OK (Prometheus found)"
elif kubectl get pods -n default 2>/dev/null | grep -q prometheus; then
    echo "✓ OK (Prometheus found in default namespace)"
else
    echo "⚠ WARNING"
    echo "   Prometheus not found. Metrics export may not work."
fi

echo ""
echo "========================================="
echo "Pre-deployment check completed successfully"
echo "========================================="
echo ""
echo "Configuration Summary:"
echo "  Namespace:          $NAMESPACE"
echo "  NATS Version:       $NATS_VERSION"
echo "  Helm Repository:    $HELM_REPO/$HELM_CHART"
echo "  Helm Chart Version: $HELM_CHART_VERSION"
echo "  Available Nodes:    $NODE_COUNT"
echo "  PVC Size:           15Gi (default)"
echo ""
echo "Next steps:"
echo "  1. Review the configuration above"
echo "  2. Run ./02-deployment.sh to deploy NATS JetStream"
echo "  3. Run ./03-validation.sh to validate the deployment"
echo ""
echo "To customize deployment, set environment variables:"
echo "  export NAMESPACE=custom-namespace"
echo "  export NATS_VERSION=2.10.0"
echo "  export STORAGE_CLASS=your-storage-class"
echo "  export PVC_SIZE=20Gi  # Adjust PVC size as needed"
echo ""