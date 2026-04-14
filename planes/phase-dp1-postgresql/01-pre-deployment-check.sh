#!/bin/bash

set -e

echo "=========================================="
echo "PostgreSQL Phase DP-1: Pre-Deployment Check"
echo "=========================================="
echo "Date: $(date)"
echo ""

# Load environment variables
if [ -f "../../.env" ]; then
    source "../../.env"
    echo "✓ Loaded environment variables from ../../.env"
else
    echo "⚠ Warning: .env file not found at ../../.env"
fi

# Check 1: Kubernetes cluster access
echo ""
echo "1. Checking Kubernetes cluster access..."
if command -v kubectl &> /dev/null; then
    kubectl cluster-info
    echo "✓ kubectl is installed and can access cluster"
else
    echo "✗ kubectl not found in PATH"
    exit 1
fi

# Check 2: Check nodes and labels
echo ""
echo "2. Checking node topology and labels..."
kubectl get nodes -o wide
echo ""
echo "Checking for storage-heavy nodes..."
kubectl get nodes -l node-role=storage-heavy --show-labels || echo "No storage-heavy nodes found (will be created during deployment)"

# Check 3: Check existing PostgreSQL resources
echo ""
echo "3. Checking for existing PostgreSQL resources..."
kubectl get statefulsets,deployments,services,pvc -n default -l app=postgresql 2>/dev/null || echo "No existing PostgreSQL resources found"

# Check 4: Check MinIO for backup bucket
echo ""
echo "4. Checking MinIO access for backups..."
if kubectl get deployment minio -n default &> /dev/null; then
    echo "✓ MinIO deployment found"
    # Check if we can access MinIO
    MINIO_ENDPOINT=$(kubectl get svc minio -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$MINIO_ENDPOINT" ]; then
        echo "  MinIO endpoint: $MINIO_ENDPOINT:9000"
    else
        echo "  ⚠ MinIO service doesn't have external IP yet"
    fi
else
    echo "⚠ MinIO not found. Backups will require MinIO deployment."
fi

# Check 5: Check storage classes
echo ""
echo "5. Checking storage classes..."
kubectl get storageclass
echo ""
echo "Checking for hcloud-volumes storage class..."
kubectl get storageclass hcloud-volumes || echo "⚠ hcloud-volumes storage class not found"

# Check 6: Check PVC capacity
echo ""
echo "6. Checking existing PVCs and capacity..."
kubectl get pvc --all-namespaces
TOTAL_PVC=$(kubectl get pvc --all-namespaces --no-headers | wc -l)
echo "Total PVCs in cluster: $TOTAL_PVC"

# Check 7: Check for required tools
echo ""
echo "7. Checking for required tools..."
REQUIRED_TOOLS=("psql" "pg_isready" "pg_basebackup")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v $tool &> /dev/null; then
        echo "✓ $tool found"
    else
        echo "⚠ $tool not found (will need to install in containers)"
    fi
done

# Check 8: Check resource availability
echo ""
echo "8. Checking cluster resource availability..."
kubectl describe nodes | grep -A 5 "Allocatable:" || true

# Check 9: Check for existing secrets
echo ""
echo "9. Checking for existing PostgreSQL secrets..."
kubectl get secrets -n default | grep -E "postgres|pgbouncer" || echo "No PostgreSQL secrets found"

# Check 10: Validate network policies
echo ""
echo "10. Checking network policies..."
kubectl get networkpolicies --all-namespaces

echo ""
echo "=========================================="
echo "Pre-deployment check summary:"
echo "=========================================="
echo "- Cluster access: ✓"
echo "- Storage classes: Check above"
echo "- MinIO for backups: Check above"
echo "- Resource availability: Check above"
echo ""
echo "If all checks pass, proceed with deployment using:"
echo "./02-deployment.sh"
echo ""
echo "To skip any failed checks (if intentional), set SKIP_CHECKS=true"
echo "SKIP_CHECKS=${SKIP_CHECKS:-false}"
echo "=========================================="

if [ "${SKIP_CHECKS}" != "true" ]; then
    echo ""
    read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
fi