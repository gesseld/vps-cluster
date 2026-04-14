#!/bin/bash
# Don't exit on error - collect all issues first
# set -e

echo "================================================"
echo "Task DP-3: Hetzner S3 Pre-Deployment Check"
echo "================================================"
echo "Checking prerequisites for enterprise-resilient S3 storage..."
echo ""

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
    echo "✓ Loaded environment variables from $PROJECT_ROOT/.env"
else
    echo "⚠️  No .env file found. Using defaults."
fi

# Set defaults
NAMESPACE=${NAMESPACE:-data-plane}
STORAGE_CLASS=${STORAGE_CLASS:-hcloud-volumes}
EXTERNAL_SECRETS_OPERATOR=${EXTERNAL_SECRETS_OPERATOR:-true}
CILIUM_ENABLED=${CILIUM_ENABLED:-true}
OBSERVABILITY_NAMESPACE=${OBSERVABILITY_NAMESPACE:-observability-plane}

echo ""
echo "1. Checking Kubernetes cluster access..."
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "❌ Cannot connect to Kubernetes cluster"
    echo "   Run: export KUBECONFIG=/path/to/kubeconfig"
    KUBERNETES_ISSUE=true
else
    echo "✓ Connected to Kubernetes cluster"
fi

echo ""
echo "2. Checking namespace '$NAMESPACE'..."
if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
    echo "❌ Namespace '$NAMESPACE' does not exist"
    echo "   Run: kubectl create namespace $NAMESPACE"
    NAMESPACE_ISSUE=true
else
    echo "✓ Namespace '$NAMESPACE' exists"
fi

echo ""
echo "3. Checking External Secrets Operator..."
if [ "$EXTERNAL_SECRETS_OPERATOR" = "true" ]; then
    if ! kubectl get crd externalsecrets.external-secrets.io > /dev/null 2>&1; then
        echo "❌ External Secrets Operator CRD not found"
        echo "   Install with: helm install external-secrets external-secrets/external-secrets"
        EXTERNAL_SECRETS_ISSUE=true
    else
        echo "✓ External Secrets Operator CRD exists"
        
        if ! kubectl get pods -n external-secrets -l app.kubernetes.io/name=external-secrets 2>/dev/null | grep -q Running; then
            echo "⚠️  External Secrets Operator pods not running in external-secrets namespace"
            echo "   Check: kubectl get pods -n external-secrets"
        else
            echo "✓ External Secrets Operator pods are running"
        fi
    fi
fi

echo ""
echo "4. Checking Cilium CNI (for FQDN policies)..."
if [ "$CILIUM_ENABLED" = "true" ]; then
    if ! kubectl get ds -n kube-system cilium > /dev/null 2>&1; then
        echo "❌ Cilium DaemonSet not found in kube-system"
        echo "   Cilium is required for FQDN-based network policies"
        CILIUM_ISSUE=true
    else
        echo "✓ Cilium DaemonSet exists"
        
        CILIUM_PODS=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | wc -l)
        CILIUM_READY=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | grep -c "Running")
        if [ "$CILIUM_PODS" -eq 0 ]; then
            echo "❌ No Cilium pods found"
            CILIUM_ISSUE=true
        elif [ "$CILIUM_PODS" -ne "$CILIUM_READY" ]; then
            echo "⚠️  Not all Cilium pods are ready ($CILIUM_READY/$CILIUM_PODS)"
        else
            echo "✓ All Cilium pods are ready ($CILIUM_READY/$CILIUM_PODS)"
        fi
    fi
fi

echo ""
echo "5. Checking observability namespace '$OBSERVABILITY_NAMESPACE'..."
if ! kubectl get namespace "$OBSERVABILITY_NAMESPACE" > /dev/null 2>&1; then
    echo "⚠️  Namespace '$OBSERVABILITY_NAMESPACE' does not exist"
    echo "   Alerting rules will be deployed to default namespace"
    OBSERVABILITY_NAMESPACE=default
else
    echo "✓ Observability namespace exists"
fi

echo ""
echo "6. Checking for required tools..."
REQUIRED_TOOLS=("kubectl" "jq" "curl")
MISSING_TOOLS=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo "⚠️  Missing tools: ${MISSING_TOOLS[*]}"
    echo "   Install on your VPS:"
    echo "   - kubectl: Follow Kubernetes documentation"
    echo "   - jq: sudo apt-get install jq"
    echo "   - curl: sudo apt-get install curl"
else
    echo "✓ All required tools are available"
fi

echo ""
echo "7. Note about S3 tools:"
echo "   - mc (MinIO Client) should be installed on the VPS for S3 operations"
echo "   - AWS CLI can be used as an alternative"
echo "   - The deployment will install mc in containers for internal use"

echo ""
echo "7. Checking Hetzner S3 credentials..."
if [ -z "$HETZNER_S3_ENDPOINT" ] || [ -z "$HETZNER_S3_ACCESS_KEY" ] || [ -z "$HETZNER_S3_SECRET_KEY" ]; then
    echo "⚠️  Hetzner S3 credentials not found in environment"
    echo "   Required variables:"
    echo "   - HETZNER_S3_ENDPOINT (e.g., https://fsn1.your-objectstorage.com)"
    echo "   - HETZNER_S3_ACCESS_KEY"
    echo "   - HETZNER_S3_SECRET_KEY"
    echo "   - HETZNER_S3_REGION (optional, defaults to fsn1)"
    echo ""
    echo "   You can create these credentials in Hetzner Cloud Console:"
    echo "   1. Go to Object Storage → Create Bucket"
    echo "   2. Generate Access Key + Secret Key"
    echo "   3. Set permissions: read/write for required buckets"
else
    echo "✓ Hetzner S3 credentials found in environment"
    
    # Test connectivity
    echo "   Testing S3 connectivity..."
    if command -v mc > /dev/null 2>&1; then
        mc alias set test-hetzner "$HETZNER_S3_ENDPOINT" "$HETZNER_S3_ACCESS_KEY" "$HETZNER_S3_SECRET_KEY" --api s3v4 --path off > /dev/null 2>&1
        if mc alias list test-hetzner > /dev/null 2>&1; then
            echo "✓ S3 connectivity test passed"
            mc alias remove test-hetzner > /dev/null 2>&1
        else
            echo "❌ S3 connectivity test failed"
            echo "   Check credentials and network connectivity"
        fi
    fi
fi

echo ""
echo "8. Checking replication target credentials..."
if [ -z "$REPLICATION_TARGET_ENDPOINT" ] || [ -z "$REPLICATION_TARGET_ACCESS_KEY" ] || [ -z "$REPLICATION_TARGET_SECRET_KEY" ]; then
    echo "⚠️  Replication target credentials not found"
    echo "   For dual-S3 replication (recommended), set:"
    echo "   - REPLICATION_TARGET_ENDPOINT (e.g., https://nbg1.your-objectstorage.com)"
    echo "   - REPLICATION_TARGET_ACCESS_KEY"
    echo "   - REPLICATION_TARGET_SECRET_KEY"
    echo ""
    echo "   For Storage Box fallback, set:"
    echo "   - REPLICATION_TARGET_ENDPOINT=sftp://u123456.your-storagebox.de"
    echo "   - REPLICATION_TARGET_ACCESS_KEY=username"
    echo "   - REPLICATION_TARGET_SECRET_KEY=password"
else
    echo "✓ Replication target credentials found"
fi

echo ""
echo "9. Checking storage class '$STORAGE_CLASS'..."
if ! kubectl get storageclass "$STORAGE_CLASS" > /dev/null 2>&1; then
    echo "⚠️  Storage class '$STORAGE_CLASS' not found"
    echo "   Available storage classes:"
    kubectl get storageclass
else
    echo "✓ Storage class '$STORAGE_CLASS' exists"
fi

echo ""
echo "10. Checking for existing S3 resources..."
EXISTING_SECRETS=$(kubectl get secrets -n "$NAMESPACE" -l app=hetzner-s3 2>/dev/null | wc -l)
if [ "$EXISTING_SECRETS" -gt 1 ]; then
    echo "⚠️  Existing S3 secrets found in namespace $NAMESPACE"
    echo "   Run: kubectl get secrets -n $NAMESPACE -l app=hetzner-s3"
fi

EXISTING_DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" -l app=s3-replicator 2>/dev/null | wc -l)
if [ "$EXISTING_DEPLOYMENTS" -gt 1 ]; then
    echo "⚠️  Existing S3 replicator deployment found"
    echo "   Run: kubectl get deployments -n $NAMESPACE -l app=s3-replicator"
fi

echo ""
echo "================================================"
echo "Pre-deployment check completed"
echo "================================================"
echo ""
echo "Summary:"
echo "- Kubernetes: ✓ Connected"
echo "- Namespace '$NAMESPACE': ✓ Exists"
echo "- External Secrets Operator: $( [ "$EXTERNAL_SECRETS_OPERATOR" = "true" ] && echo "✓" || echo "✗" )"
echo "- Cilium CNI: $( [ "$CILIUM_ENABLED" = "true" ] && echo "✓" || echo "✗" )"
echo "- Observability: $( [ "$OBSERVABILITY_NAMESPACE" != "default" ] && echo "✓" || echo "⚠️" )"
echo "- Required tools: $( [ ${#MISSING_TOOLS[@]} -eq 0 ] && echo "✓" || echo "⚠️ Missing ${#MISSING_TOOLS[@]}" )"
echo "- Hetzner S3 credentials: $( [ -n "$HETZNER_S3_ENDPOINT" ] && echo "✓" || echo "⚠️" )"
echo "- Replication target: $( [ -n "$REPLICATION_TARGET_ENDPOINT" ] && echo "✓" || echo "⚠️" )"
echo "- Storage class: $( kubectl get storageclass "$STORAGE_CLASS" > /dev/null 2>&1 && echo "✓" || echo "⚠️" )"
echo ""
echo "Next steps:"
echo "1. Ensure all credentials are set in .env file"
echo "2. Run: ./02-deployment.sh"
echo ""
echo "For troubleshooting:"
echo "- Check kubectl config: kubectl config view"
echo "- Verify node readiness: kubectl get nodes"
echo "- Check Cilium status: kubectl get pods -n kube-system -l k8s-app=cilium"