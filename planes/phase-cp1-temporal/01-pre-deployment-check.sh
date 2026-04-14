#!/bin/bash
set -e

echo "=========================================="
echo "Temporal Server CP-1: Pre-deployment Check"
echo "=========================================="
echo "Validating prerequisites for Temporal Server deployment..."
echo

# Source environment variables if .env exists
ENV_FILE="$(dirname "$0")/.env"
if [ -f "$ENV_FILE" ]; then
    echo "Loading environment variables from $ENV_FILE"
    source "$ENV_FILE"
fi

# Default values
NAMESPACE=${NAMESPACE:-control-plane}
TEMPORAL_VERSION=${TEMPORAL_VERSION:-1.25.0}
STORAGE_CLASS=${STORAGE_CLASS:-hcloud-volumes}
PRIORITY_CLASS=${PRIORITY_CLASS:-foundation-critical}

echo "Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Temporal Version: $TEMPORAL_VERSION"
echo "  Storage Class: $STORAGE_CLASS"
echo "  Priority Class: $PRIORITY_CLASS"
echo

# Check 1: Kubernetes cluster access
echo "1. Checking Kubernetes cluster access..."
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "❌ ERROR: Cannot connect to Kubernetes cluster"
    echo "   Run: kubectl cluster-info to debug"
    exit 1
fi
echo "   ✓ Connected to Kubernetes cluster"

# Check 2: Namespace exists
echo "2. Checking namespace '$NAMESPACE'..."
if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    echo "❌ ERROR: Namespace '$NAMESPACE' does not exist"
    echo "   Create it with: kubectl create namespace $NAMESPACE"
    exit 1
fi
echo "   ✓ Namespace '$NAMESPACE' exists"

# Check 3: Storage class exists
echo "3. Checking storage class '$STORAGE_CLASS'..."
if ! kubectl get storageclass "$STORAGE_CLASS" > /dev/null 2>&1; then
    echo "❌ ERROR: Storage class '$STORAGE_CLASS' does not exist"
    echo "   Available storage classes:"
    kubectl get storageclass
    exit 1
fi
echo "   ✓ Storage class '$STORAGE_CLASS' exists"

# Check 4: Priority class exists
echo "4. Checking priority class '$PRIORITY_CLASS'..."
if ! kubectl get priorityclass "$PRIORITY_CLASS" > /dev/null 2>&1; then
    echo "⚠️  WARNING: Priority class '$PRIORITY_CLASS' does not exist"
    echo "   Temporal will run without priority class"
else
    echo "   ✓ Priority class '$PRIORITY_CLASS' exists"
fi

# Check 5: Check for existing Temporal resources
echo "5. Checking for existing Temporal resources..."
EXISTING_TEMPORAL=$(kubectl get all -n "$NAMESPACE" -l app=temporal 2>/dev/null || true)
if [ -n "$EXISTING_TEMPORAL" ] && [ "$EXISTING_TEMPORAL" != "No resources found" ]; then
    echo "⚠️  WARNING: Existing Temporal resources found:"
    echo "$EXISTING_TEMPORAL"
    echo "   Consider cleaning up before deployment"
fi

# Check 6: Check PostgreSQL credentials secret (Data Plane reference)
echo "6. Checking PostgreSQL credentials secret..."
if ! kubectl get secret temporal-postgres-creds -n data-plane > /dev/null 2>&1; then
    echo "⚠️  WARNING: PostgreSQL credentials secret 'temporal-postgres-creds' not found in data-plane"
    echo "   Temporal requires PostgreSQL for persistence. Ensure it's deployed in Data Plane."
else
    echo "   ✓ PostgreSQL credentials secret found"
fi

# Check 7: Check SPIFFE/SPIRE setup for mTLS
echo "7. Checking SPIFFE/SPIRE setup..."
SPIRE_SERVER=$(kubectl get pods -n control-plane -l app=spire-server 2>/dev/null | grep -c "Running" || true)
if [ "$SPIRE_SERVER" -eq 0 ]; then
    echo "⚠️  WARNING: SPIRE server not found in control-plane"
    echo "   mTLS will use default certificates"
else
    echo "   ✓ SPIRE server found"
fi

# Check 8: Check node resources
echo "8. Checking node resources..."
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
echo "   Cluster has $NODE_COUNT nodes"
if [ "$NODE_COUNT" -lt 2 ]; then
    echo "⚠️  WARNING: HA deployment requires at least 2 nodes for anti-affinity"
fi

# Check 9: Check kubectl version
echo "9. Checking kubectl version..."
KUBECTL_VERSION=$(kubectl version --client -o json | jq -r '.clientVersion.gitVersion' 2>/dev/null || echo "unknown")
echo "   kubectl version: $KUBECTL_VERSION"

# Check 10: Check tctl availability
echo "10. Checking tctl availability..."
if command -v tctl > /dev/null 2>&1; then
    echo "   ✓ tctl is available"
else
    echo "⚠️  WARNING: tctl not found in PATH"
    echo "   Install with: go install go.temporal.io/server/tools/cli@latest"
fi

echo
echo "=========================================="
echo "Pre-deployment check completed!"
echo "=========================================="
echo
echo "Summary:"
echo "  - Cluster access: ✓"
echo "  - Namespace: ✓"
echo "  - Storage class: ✓"
echo "  - PostgreSQL: ⚠️ (check Data Plane deployment)"
echo "  - SPIRE/mTLS: ⚠️ (optional for mTLS)"
echo "  - Node count: $NODE_COUNT nodes"
echo
echo "Next steps:"
echo "  1. Ensure PostgreSQL is deployed in Data Plane with 'temporal_visibility' database"
echo "  2. Deploy Temporal with: ./02-deployment.sh"
echo "  3. Validate with: ./03-validation.sh"
echo
echo "To customize deployment, create .env file with:"
echo "  NAMESPACE=control-plane"
echo "  TEMPORAL_VERSION=1.25.0"
echo "  STORAGE_CLASS=hcloud-volumes"
echo "  PRIORITY_CLASS=foundation-critical"