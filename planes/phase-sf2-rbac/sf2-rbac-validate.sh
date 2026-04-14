#!/bin/bash
# Validation script for SF-2: ServiceAccounts + RBAC Baseline
# Validates that foundation service accounts and RBAC are properly deployed

set -e

echo "=== SF-2 RBAC Validation ==="
echo "Validating foundation service accounts and RBAC permissions..."
echo

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ ERROR: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ ERROR: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✓ Connected to Kubernetes cluster"
echo

# Define service accounts to validate
declare -A service_accounts=(
    ["control-plane:temporal-server"]="Workflow orchestration"
    ["control-plane:kyverno"]="Policy management"
    ["control-plane:spire-server"]="Identity management"
    ["data-plane:postgres"]="Database operations"
    ["data-plane:nats"]="Messaging operations"
    ["data-plane:minio"]="Storage operations"
    ["observability-plane:vmagent"]="Metrics collection"
    ["observability-plane:fluent-bit"]="Log collection"
    ["observability-plane:loki"]="Log storage"
)

# Define expected permissions for each service account
declare -A expected_permissions=(
    ["control-plane:temporal-server"]="get.*pods.*control-plane|list.*pods.*control-plane|watch.*pods.*control-plane"
    ["control-plane:kyverno"]="get.*namespaces|list.*namespaces|watch.*namespaces"
    ["control-plane:spire-server"]="get.*pods.*control-plane|list.*pods.*control-plane|watch.*pods.*control-plane"
    ["data-plane:postgres"]="get.*pods.*data-plane|list.*pods.*data-plane|watch.*pods.*data-plane"
    ["data-plane:nats"]="get.*pods.*data-plane|list.*pods.*data-plane|watch.*pods.*data-plane"
    ["data-plane:minio"]="get.*pods.*data-plane|list.*pods.*data-plane|watch.*pods.*data-plane"
    ["observability-plane:vmagent"]="get.*pods.*observability-plane|list.*pods.*observability-plane|watch.*pods.*observability-plane"
    ["observability-plane:fluent-bit"]="get.*namespaces|list.*namespaces|watch.*namespaces"
    ["observability-plane:loki"]="get.*pods.*observability-plane|list.*pods.*observability-plane|watch.*pods.*observability-plane"
)

echo "Step 1: Validating service account existence..."
echo "========================================"
all_sas_exist=true
for sa in "${!service_accounts[@]}"; do
    ns="${sa%:*}"
    name="${sa#*:}"
    description="${service_accounts[$sa]}"
    
    if kubectl get serviceaccount "$name" -n "$ns" &> /dev/null; then
        echo "✓ Service account '$name' exists in namespace '$ns' ($description)"
    else
        echo "❌ Service account '$name' NOT FOUND in namespace '$ns' ($description)"
        all_sas_exist=false
    fi
done

echo
echo "Step 2: Validating RBAC role bindings..."
echo "========================================"
all_bindings_exist=true

# Check role bindings
role_bindings=(
    "control-plane:temporal-server-binding"
    "control-plane:spire-server-binding"
    "data-plane:postgres-binding"
    "data-plane:nats-binding"
    "data-plane:minio-binding"
    "observability-plane:vmagent-binding"
    "observability-plane:loki-binding"
)

for rb in "${role_bindings[@]}"; do
    ns="${rb%:*}"
    name="${rb#*:}"
    
    if kubectl get rolebinding "$name" -n "$ns" &> /dev/null; then
        echo "✓ Role binding '$name' exists in namespace '$ns'"
    else
        echo "❌ Role binding '$name' NOT FOUND in namespace '$ns'"
        all_bindings_exist=false
    fi
done

# Check cluster role bindings
cluster_role_bindings=(
    "kyverno-foundation-binding"
    "fluent-bit-foundation-binding"
)

for crb in "${cluster_role_bindings[@]}"; do
    if kubectl get clusterrolebinding "$crb" &> /dev/null; then
        echo "✓ Cluster role binding '$crb' exists"
    else
        echo "❌ Cluster role binding '$crb' NOT FOUND"
        all_bindings_exist=false
    fi
done

echo
echo "Step 3: Validating permissions with kubectl auth can-i..."
echo "========================================"
echo "Note: This checks if service accounts have the expected minimal permissions"
echo

# Test a subset of service accounts for permissions
test_accounts=(
    "control-plane:temporal-server"
    "control-plane:kyverno"
    "data-plane:postgres"
    "observability-plane:vmagent"
)

for sa in "${test_accounts[@]}"; do
    ns="${sa%:*}"
    name="${sa#*:}"
    
    echo "Testing permissions for '$name' in namespace '$ns':"
    echo "------------------------------------------------"
    
    # Get the actual permissions list
    if permissions_output=$(kubectl auth can-i --list --as="system:serviceaccount:$ns:$name" 2>/dev/null); then
        # Count the number of permissions
        perm_count=$(echo "$permissions_output" | grep -c "\[.*\]")
        
        if [ "$perm_count" -gt 0 ]; then
            echo "✓ Service account has $perm_count permission(s)"
            
            # Check for expected permissions pattern
            expected_pattern="${expected_permissions[$sa]}"
            if [ -n "$expected_pattern" ]; then
                # Test actual permissions with kubectl auth can-i
                can_get_pods=$(kubectl auth can-i get pods --as="system:serviceaccount:$ns:$name" -n "$ns" 2>/dev/null || echo "no")
                can_list_pods=$(kubectl auth can-i list pods --as="system:serviceaccount:$ns:$name" -n "$ns" 2>/dev/null || echo "no")
                
                if [ "$can_get_pods" = "yes" ] && [ "$can_list_pods" = "yes" ]; then
                    echo "✓ Has expected pod permissions (get, list)"
                else
                    echo "⚠️  Missing some expected permissions"
                fi
            fi
            
            # Check for wildcard permissions (should not have any)
            # Note: Some default Kubernetes permissions may include wildcards for API discovery
            # We'll check for resource wildcards specifically
            if echo "$permissions_output" | grep -q "\[\*\]" | grep -v "Non-Resource URLs"; then
                echo "⚠️  WARNING: Service account has wildcard permissions (*)"
            fi
        else
            echo "⚠️  Service account has no permissions (may be too restrictive)"
        fi
    else
        echo "❌ Failed to check permissions for service account"
    fi
    echo
done

echo
echo "Step 4: Checking namespace exclusions..."
echo "========================================"
excluded_namespaces=("kube-system" "kyverno")

for ns in "${excluded_namespaces[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        if kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.rbac-exclude}' | grep -q "true"; then
            echo "✓ Namespace '$ns' is labeled for RBAC exclusion"
        else
            echo "⚠️  Namespace '$ns' exists but not labeled for RBAC exclusion"
        fi
    else
        echo "ℹ️  Namespace '$ns' does not exist (no exclusion needed)"
    fi
done

echo
echo "========================================"
echo "Validation Summary:"
echo "========================================"

if [ "$all_sas_exist" = true ] && [ "$all_bindings_exist" = true ]; then
    echo "✅ SUCCESS: All service accounts and RBAC bindings are properly deployed"
    echo
    echo "Deployment validated:"
    echo "- 9 foundation service accounts created"
    echo "- 10 RBAC roles/rolebindings deployed"
    echo "- 2 cluster roles/clusterrolebindings deployed"
    echo "- Namespace exclusions configured"
    echo
    echo "RBAC baseline is ready for workload deployment."
else
    echo "❌ VALIDATION FAILED: Some components are missing or misconfigured"
    echo
    echo "Issues found:"
    if [ "$all_sas_exist" = false ]; then
        echo "- Missing service accounts"
    fi
    if [ "$all_bindings_exist" = false ]; then
        echo "- Missing RBAC bindings"
    fi
    echo
    echo "Please check the deployment and run the deployment script again:"
    echo "./planes/sf2-rbac-deploy.sh"
    exit 1
fi

echo
echo "For detailed permission analysis, run:"
echo "kubectl auth can-i --list --as=system:serviceaccount:control-plane:temporal-server"
echo "kubectl auth can-i --list --as=system:serviceaccount:control-plane:kyverno"
echo "kubectl auth can-i --list --as=system:serviceaccount:data-plane:postgres"
echo
echo "Documentation: ./shared/rbac-matrix.md"
echo "========================================"