#!/bin/bash
# Deployment script for SF-2: ServiceAccounts + RBAC Baseline
# Deploys foundation service accounts and RBAC roles

set -e

echo "=== SF-2 RBAC Deployment ==="
echo "Deploying foundation service accounts and RBAC roles..."
echo

# Run pre-deployment check first
echo "Running pre-deployment checks..."
if [ -f "./planes/phase-sf2-rbac/sf2-rbac-precheck.sh" ]; then
    bash ./planes/phase-sf2-rbac/sf2-rbac-precheck.sh
    echo
    read -p "Continue with deployment? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "Deployment aborted by user."
        exit 0
    fi
else
    echo "⚠️  Pre-check script not found, continuing with basic checks..."
    
    # Basic kubectl check
    if ! command -v kubectl &> /dev/null; then
        echo "❌ ERROR: kubectl is not installed"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        echo "❌ ERROR: Cannot connect to Kubernetes cluster"
        exit 1
    fi
fi

echo
echo "Starting deployment..."
echo "========================================"

# Create service accounts
echo
echo "Step 1: Creating foundation service accounts..."
if [ -f "./shared/rbac/foundation-sas.yaml" ]; then
    echo "Applying foundation-sas.yaml..."
    kubectl apply -f ./shared/rbac/foundation-sas.yaml
    if [ $? -eq 0 ]; then
        echo "✓ Service accounts created successfully"
    else
        echo "❌ Failed to create service accounts"
        exit 1
    fi
else
    echo "❌ ERROR: foundation-sas.yaml not found at ./shared/rbac/foundation-sas.yaml"
    exit 1
fi

# Create RBAC roles and bindings
echo
echo "Step 2: Creating RBAC roles and bindings..."
if [ -f "./shared/rbac/foundation-roles.yaml" ]; then
    echo "Applying foundation-roles.yaml..."
    kubectl apply -f ./shared/rbac/foundation-roles.yaml
    if [ $? -eq 0 ]; then
        echo "✓ RBAC roles and bindings created successfully"
    else
        echo "❌ Failed to create RBAC roles and bindings"
        exit 1
    fi
else
    echo "❌ ERROR: foundation-roles.yaml not found at ./shared/rbac/foundation-roles.yaml"
    exit 1
fi

# Verify deployment
echo
echo "Step 3: Verifying deployment..."
echo
echo "Checking created service accounts:"
kubectl get serviceaccounts -n control-plane -l rbac-tier=foundation
kubectl get serviceaccounts -n data-plane -l rbac-tier=foundation
kubectl get serviceaccounts -n observability-plane -l rbac-tier=foundation

echo
echo "Checking created roles:"
kubectl get roles -n control-plane
kubectl get roles -n data-plane
kubectl get roles -n observability-plane

echo
echo "Checking created cluster roles:"
kubectl get clusterroles -l rbac-tier=foundation

echo
echo "Checking role bindings:"
kubectl get rolebindings -n control-plane
kubectl get rolebindings -n data-plane
kubectl get rolebindings -n observability-plane

echo
echo "Checking cluster role bindings:"
kubectl get clusterrolebindings -l rbac-tier=foundation

# Create exclusion annotations for kube-system and kyverno namespaces
echo
echo "Step 4: Configuring namespace exclusions..."
echo "Adding exclusion labels to kube-system namespace..."
kubectl label namespace kube-system rbac-exclude=true --overwrite 2>/dev/null || echo "⚠️  Could not label kube-system namespace (may not have permission)"

echo "Adding exclusion labels to kyverno namespace (if exists)..."
if kubectl get namespace kyverno &> /dev/null; then
    kubectl label namespace kyverno rbac-exclude=true --overwrite 2>/dev/null || echo "⚠️  Could not label kyverno namespace"
else
    echo "ℹ️  kyverno namespace does not exist, skipping"
fi

# Summary
echo
echo "========================================"
echo "Deployment completed successfully!"
echo
echo "Summary:"
echo "- Created 9 service accounts across 3 planes"
echo "- Created 10 RBAC roles/rolebindings"
echo "- Created 2 cluster roles/clusterrolebindings"
echo "- Configured namespace exclusions for kube-system and kyverno"
echo
echo "Service Accounts by plane:"
echo "Control-plane: temporal-server, kyverno, spire-server"
echo "Data-plane: postgres, nats, minio"
echo "Observability-plane: vmagent, fluent-bit, loki"
echo
echo "Next steps:"
echo "1. Run validation script: ./planes/phase-sf2-rbac/sf2-rbac-validate.sh"
echo "2. Review RBAC matrix: ./shared/rbac-matrix.md"
echo "3. Test specific permissions with kubectl auth can-i"
echo
echo "Example validation command:"
echo "kubectl auth can-i --list --as=system:serviceaccount:control-plane:temporal-server"
echo "========================================"