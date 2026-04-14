#!/bin/bash
# Pre-deployment script for SF-2: ServiceAccounts + RBAC Baseline
# Checks prerequisites before deploying foundation service accounts and RBAC

set -e

echo "=== SF-2 RBAC Pre-deployment Check ==="
echo "Checking prerequisites for foundation service accounts deployment..."
echo

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ ERROR: kubectl is not installed or not in PATH"
    exit 1
fi
echo "✓ kubectl is available"

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi
echo "✓ Connected to Kubernetes cluster"

# Check if foundation namespaces exist
echo
echo "Checking foundation namespaces..."
namespaces=("control-plane" "data-plane" "observability-plane")
missing_namespaces=()

for ns in "${namespaces[@]}"; do
    if ! kubectl get namespace "$ns" &> /dev/null; then
        missing_namespaces+=("$ns")
        echo "❌ Namespace '$ns' does not exist"
    else
        echo "✓ Namespace '$ns' exists"
    fi
done

if [ ${#missing_namespaces[@]} -gt 0 ]; then
    echo
    echo "⚠️  WARNING: The following foundation namespaces are missing:"
    printf '%s\n' "${missing_namespaces[@]}"
    echo
    echo "Please create them using the foundation-namespaces.yaml manifest:"
    echo "kubectl apply -f planes/phase-01-budget/shared/foundation-namespaces.yaml"
    echo
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting deployment."
        exit 1
    fi
fi

# Check for existing service accounts that might conflict
echo
echo "Checking for existing service accounts..."
service_accounts=(
    "control-plane:temporal-server"
    "control-plane:kyverno"
    "control-plane:spire-server"
    "data-plane:postgres"
    "data-plane:nats"
    "data-plane:minio"
    "observability-plane:vmagent"
    "observability-plane:fluent-bit"
    "observability-plane:loki"
)

conflicting_sas=()
for sa in "${service_accounts[@]}"; do
    ns="${sa%:*}"
    name="${sa#*:}"
    if kubectl get serviceaccount "$name" -n "$ns" &> /dev/null; then
        conflicting_sas+=("$sa")
        echo "⚠️  Service account '$name' already exists in namespace '$ns'"
    else
        echo "✓ Service account '$name' does not exist in namespace '$ns'"
    fi
done

if [ ${#conflicting_sas[@]} -gt 0 ]; then
    echo
    echo "⚠️  WARNING: The following service accounts already exist:"
    printf '%s\n' "${conflicting_sas[@]}"
    echo
    read -p "Continue and overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting deployment."
        exit 1
    fi
fi

# Check RBAC API availability
echo
echo "Checking RBAC API availability..."
if ! kubectl api-resources | grep -q "rbac.authorization.k8s.io"; then
    echo "❌ ERROR: RBAC API is not available"
    exit 1
fi
echo "✓ RBAC API is available"

# Check current user permissions
echo
echo "Checking current user permissions..."
if ! kubectl auth can-i create serviceaccount --all-namespaces &> /dev/null; then
    echo "❌ ERROR: Current user cannot create service accounts"
    exit 1
fi
echo "✓ Current user can create service accounts"

if ! kubectl auth can-i create role --all-namespaces &> /dev/null; then
    echo "❌ ERROR: Current user cannot create roles"
    exit 1
fi
echo "✓ Current user can create roles"

if ! kubectl auth can-i create rolebinding --all-namespaces &> /dev/null; then
    echo "❌ ERROR: Current user cannot create role bindings"
    exit 1
fi
echo "✓ Current user can create role bindings"

# Check for Kyverno namespace exclusion
echo
echo "Checking Kyverno namespace..."
if kubectl get namespace kyverno &> /dev/null; then
    echo "✓ Kyverno namespace exists (will be excluded from policies)"
else
    echo "ℹ️  Kyverno namespace does not exist (no exclusion needed)"
fi

# Summary
echo
echo "========================================"
echo "Pre-deployment check completed successfully!"
echo
echo "Ready to deploy:"
echo "- 9 service accounts across 3 planes"
echo "- 10 RBAC roles/rolebindings"
echo "- 2 cluster roles/clusterrolebindings"
echo
echo "To deploy, run: ./planes/phase-sf2-rbac/sf2-rbac-deploy.sh"
echo "To validate after deployment: ./planes/phase-sf2-rbac/sf2-rbac-validate.sh"
echo "========================================"