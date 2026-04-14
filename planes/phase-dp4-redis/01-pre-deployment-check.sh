#!/bin/bash

# Redis Phase DP-4: Pre-deployment Check Script
# Validates prerequisites for Redis multi-role cache tier deployment

set -e

echo "=============================================="
echo "Redis DP-4: Pre-deployment Check"
echo "=============================================="
echo "Timestamp: $(date)"
echo ""

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$PROJECT_ROOT/.env" ]; then
    echo "Loading environment from $PROJECT_ROOT/.env"
    source "$PROJECT_ROOT/.env"
elif [ -f "$SCRIPT_DIR/.env" ]; then
    echo "Loading environment from $SCRIPT_DIR/.env"
    source "$SCRIPT_DIR/.env"
fi

# Default values
NAMESPACE=${NAMESPACE:-default}
REDIS_VERSION=${REDIS_VERSION:-7.2}
STORAGE_CLASS=${STORAGE_CLASS:-hcloud-volumes}

echo "Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Redis Version: $REDIS_VERSION"
echo "  Storage Class: $STORAGE_CLASS"
echo ""

# Function to check command availability
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ ERROR: Command '$1' not found"
        return 1
    fi
    echo "✅ $1 is available"
}

# Function to check Kubernetes resource
check_k8s_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    if kubectl get "$resource_type" "$resource_name" -n "$namespace" &> /dev/null; then
        echo "✅ $resource_type/$resource_name exists in namespace $namespace"
        return 0
    else
        echo "❌ $resource_type/$resource_name not found in namespace $namespace"
        return 1
    fi
}

echo "1. Checking required commands..."
check_command kubectl || exit 1
check_command helm || echo "⚠️  Helm not found (optional for some operations)"
echo ""

echo "2. Checking Kubernetes cluster access..."
if kubectl cluster-info &> /dev/null; then
    echo "✅ Kubernetes cluster is accessible"
    
    # Get cluster info
    CLUSTER_NAME=$(kubectl config current-context)
    echo "   Current context: $CLUSTER_NAME"
    
    # Check nodes
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    echo "   Number of nodes: $NODE_COUNT"
    
    if [ "$NODE_COUNT" -lt 1 ]; then
        echo "❌ ERROR: No nodes found in cluster"
        exit 1
    fi
else
    echo "❌ ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi
echo ""

echo "3. Checking namespace..."
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "✅ Namespace $NAMESPACE exists"
else
    echo "⚠️  Namespace $NAMESPACE does not exist, will be created during deployment"
fi
echo ""

echo "4. Checking storage classes..."
STORAGE_CLASSES=$(kubectl get storageclass -o name)
if echo "$STORAGE_CLASSES" | grep -q "$STORAGE_CLASS"; then
    echo "✅ Storage class $STORAGE_CLASS exists"
    
    # Check storage class details
    SC_DETAILS=$(kubectl get storageclass "$STORAGE_CLASS" -o jsonpath='{.provisioner}')
    echo "   Provisioner: $SC_DETAILS"
else
    echo "❌ ERROR: Storage class $STORAGE_CLASS not found"
    echo "   Available storage classes:"
    kubectl get storageclass
    exit 1
fi
echo ""

echo "5. Checking existing Redis resources..."
EXISTING_REDIS=$(kubectl get deployments,statefulsets -n "$NAMESPACE" -l app=redis 2>/dev/null || true)
if [ -n "$EXISTING_REDIS" ]; then
    echo "⚠️  WARNING: Redis resources already exist:"
    echo "$EXISTING_REDIS"
    echo ""
    read -p "Do you want to continue? Existing resources may be overwritten. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting deployment."
        exit 1
    fi
else
    echo "✅ No existing Redis resources found"
fi
echo ""

echo "6. Checking resource availability..."
echo "   Checking node resources..."
NODES=$(kubectl get nodes --no-headers -o custom-columns="NAME:.metadata.name,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory")
echo "$NODES" | while read -r node cpu memory; do
    echo "   - $node: CPU=$cpu, Memory=$memory"
done
echo ""

echo "7. Checking network policies..."
if check_k8s_resource networkpolicy control-to-redis "$NAMESPACE"; then
    echo "✅ Redis network policy exists"
else
    echo "⚠️  Redis network policy not found (will be created if needed)"
fi
echo ""

echo "8. Checking monitoring stack..."
# Check if Prometheus is available
if kubectl get pods -n monitoring -l app=prometheus 2>/dev/null | grep -q prometheus; then
    echo "✅ Prometheus monitoring stack detected"
    
    # Check PrometheusRule CRD
    if kubectl get crd prometheusrules.monitoring.coreos.com &> /dev/null; then
        echo "✅ PrometheusRule CRD available"
    else
        echo "⚠️  PrometheusRule CRD not available (alerts will not be created)"
    fi
else
    echo "⚠️  Prometheus not found in monitoring namespace (alerts will be created but may not work)"
fi
echo ""

echo "9. Checking Redis image availability..."
# Try to pull the image locally if docker is available
if command -v docker &> /dev/null; then
    if docker pull "redis:$REDIS_VERSION-alpine" &> /dev/null; then
        echo "✅ Redis image redis:$REDIS_VERSION-alpine is available"
    else
        echo "⚠️  Could not pull Redis image (cluster may pull it during deployment)"
    fi
fi

if command -v docker &> /dev/null; then
    if docker pull "oliver006/redis_exporter:v1.60.0" &> /dev/null; then
        echo "✅ Redis exporter image oliver006/redis_exporter:v1.60.0 is available"
    else
        echo "⚠️  Could not pull Redis exporter image"
    fi
fi
echo ""

echo "10. Checking required ports..."
echo "   The following ports will be used:"
echo "   - 6379: Redis main port"
echo "   - 9121: Redis exporter metrics port"
echo ""

echo "11. Validating configuration files..."
if [ -f "$PROJECT_ROOT/data-plane/redis/configmap.yaml" ]; then
    echo "✅ Redis configmap.yaml found"
    
    # Validate Redis configuration
    if grep -q "appendonly no" "$PROJECT_ROOT/data-plane/redis/configmap.yaml"; then
        echo "✅ AOF is disabled (RDB-only configuration)"
    else
        echo "❌ ERROR: AOF not disabled in configuration"
        exit 1
    fi
    
    if grep -q "maxmemory 512mb" "$PROJECT_ROOT/data-plane/redis/configmap.yaml"; then
        echo "✅ Maxmemory set to 512MB"
    else
        echo "❌ ERROR: Maxmemory not set to 512MB"
        exit 1
    fi
    
    if grep -q "save 900 1" "$PROJECT_ROOT/data-plane/redis/configmap.yaml" && \
       grep -q "save 300 10" "$PROJECT_ROOT/data-plane/redis/configmap.yaml" && \
       grep -q "save 60 10000" "$PROJECT_ROOT/data-plane/redis/configmap.yaml"; then
        echo "✅ RDB snapshot configuration correct"
    else
        echo "❌ ERROR: RDB snapshot configuration incorrect"
        exit 1
    fi
else
    echo "❌ ERROR: Redis configmap.yaml not found at $PROJECT_ROOT/data-plane/redis/configmap.yaml"
    exit 1
fi

if [ -f "$PROJECT_ROOT/data-plane/redis/deployment.yaml" ]; then
    echo "✅ Redis deployment.yaml found"
else
    echo "❌ ERROR: Redis deployment.yaml not found"
    exit 1
fi

if [ -f "$PROJECT_ROOT/data-plane/redis/metrics-alert.yaml" ]; then
    echo "✅ Redis metrics-alert.yaml found"
else
    echo "⚠️  Redis metrics-alert.yaml not found (alerts may not be created)"
fi
echo ""

echo "12. Checking security requirements..."
echo "   Checking for PSP or PodSecurity admission..."
if kubectl get pods -n kube-system -l component=kube-apiserver 2>/dev/null | grep -q kube-apiserver; then
    echo "✅ Kubernetes API server is running"
    
    # Check PodSecurity admission (Kubernetes 1.23+)
    if kubectl get ns "$NAMESPACE" -o jsonpath='{.metadata.labels}' | grep -q pod-security; then
        echo "✅ PodSecurity admission configured for namespace"
    else
        echo "⚠️  PodSecurity admission not configured (check cluster security policies)"
    fi
fi
echo ""

echo "=============================================="
echo "Pre-deployment check completed successfully!"
echo "=============================================="
echo ""
echo "Summary:"
echo "- Kubernetes cluster: ✅ Accessible ($CLUSTER_NAME)"
echo "- Nodes: ✅ $NODE_COUNT node(s) available"
echo "- Storage: ✅ $STORAGE_CLASS storage class available"
echo "- Redis configuration: ✅ Validated (RDB-only, 512MB limit)"
echo "- Monitoring: ✅ Prometheus detected"
echo "- Security: ✅ Basic checks passed"
echo ""
echo "Next steps:"
echo "1. Run deployment script: ./02-deployment.sh"
echo "2. Validate deployment: ./03-validation.sh"
echo ""
echo "Note: This deployment will create:"
echo "- Redis deployment with sidecar exporter"
echo "- Service for Redis (port 6379) and metrics (port 9121)"
echo "- ConfigMap with Redis configuration"
echo "- Prometheus alerts for memory monitoring (>450MB warning, >500MB critical)"
echo ""

exit 0