#!/bin/bash

set -e

echo "=== Kyverno Policy Engine Deployment ==="
echo "Deploying Kyverno v1.11+ with HA configuration..."

# Set default kubeconfig if not set
if [ -z "$KUBECONFIG" ]; then
    # Try to find kubeconfig in common locations
    if [ -f "$(pwd)/../../kubeconfig" ]; then
        export KUBECONFIG="$(pwd)/../../kubeconfig"
    elif [ -f "$HOME/.kube/config" ]; then
        export KUBECONFIG="$HOME/.kube/config"
    fi
fi

# Run pre-deployment checks first
echo "Running pre-deployment checks..."
./pre-deployment.sh

echo ""
echo "Starting Kyverno deployment..."

# Create kyverno namespace if it doesn't exist
if ! kubectl get ns kyverno &> /dev/null; then
    echo "Creating kyverno namespace..."
    kubectl create namespace kyverno
fi

# Apply Kyverno installation using Helm
echo "Deploying Kyverno using Helm for better CRD handling..."
KYVERNO_VERSION="v1.11.0"

# Add Kyverno Helm repo if not already added
if ! helm repo list | grep -q kyverno; then
    echo "Adding Kyverno Helm repository..."
    helm repo add kyverno https://kyverno.github.io/kyverno/
    helm repo update
fi

echo "Installing Kyverno with HA configuration (2 replicas)..."
helm install kyverno kyverno/kyverno \
    -n kyverno \
    --create-namespace \
    --set replicaCount=2 \
    --set admissionController.replicas=2 \
    --set podAntiAffinity.enabled=true \
    --set podDisruptionBudget.enabled=true \
    --set podDisruptionBudget.minAvailable=1 \
    --set admissionController.podDisruptionBudget.enabled=true \
    --set admissionController.podDisruptionBudget.minAvailable=1 \
    --set resources.requests.cpu=250m \
    --set resources.requests.memory=256Mi \
    --set resources.limits.cpu=500m \
    --set resources.limits.memory=512Mi

# Wait for Kyverno pods to be ready
echo "Waiting for Kyverno pods to be ready..."
sleep 15
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=kyverno -n kyverno --timeout=180s

echo "✓ Kyverno deployment completed"

# Apply custom policies
echo ""
echo "Applying Kyverno policies..."

# Create policies directory structure
POLICY_DIR="control-plane/kyverno/policies"
mkdir -p $POLICY_DIR

# Apply all policies
echo "Applying require-labels policy..."
kubectl apply -f $POLICY_DIR/require-labels.yaml

echo "Applying resource-constraints policy..."
kubectl apply -f $POLICY_DIR/resource-constraints.yaml

echo "Applying security-baseline policy..."
kubectl apply -f $POLICY_DIR/security-baseline.yaml

echo "Applying rate-limit-admission policy..."
kubectl apply -f $POLICY_DIR/rate-limit-admission.yaml

# Apply metrics service
echo "Applying metrics service..."
kubectl apply -f control-plane/kyverno/metrics-service.yaml

# Configure mutation webhook for SPIFFE sidecars
echo ""
echo "Configuring SPIFFE sidecar mutation webhook..."
cat > /tmp/spiffe-mutation.yaml <<EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: inject-spiffe-sidecar
  annotations:
    policies.kyverno.io/title: Inject SPIFFE Sidecar
    policies.kyverno.io/category: Security
    policies.kyverno.io/severity: medium
spec:
  background: false
  rules:
  - name: inject-spiffe-sidecar
    match:
      resources:
        kinds:
        - Pod
    mutate:
      patchStrategicMerge:
        spec:
          containers:
          - name: spire-agent
            image: ghcr.io/spiffe/spire-agent:1.6.3
            args:
            - -config
            - /run/spire/config/agent.conf
            volumeMounts:
            - name: spire-config
              mountPath: /run/spire/config
            - name: spire-sockets
              mountPath: /run/spire/sockets
          volumes:
          - name: spire-config
            configMap:
              name: spire-agent-config
          - name: spire-sockets
            emptyDir: {}
    exclude:
      resources:
        namespaces:
        - kube-system
        - kyverno
        - spire
EOF

kubectl apply -f /tmp/spiffe-mutation.yaml

# Verify policies are applied
echo ""
echo "Verifying policy application..."
POLICY_COUNT=$(kubectl get clusterpolicies -o name | wc -l)
echo "Applied $POLICY_COUNT ClusterPolicy resources"

# Check policy status
echo "Checking policy status..."
kubectl get clusterpolicies -o custom-columns=NAME:.metadata.name,BACKGROUND:.spec.background,VALIDATE:.spec.validationFailureAction

# Create test namespace for validation
echo ""
echo "Creating test namespace for validation..."
kubectl create namespace kyverno-test --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "=== Kyverno deployment completed successfully ==="
echo ""
echo "Next steps:"
echo "1. Run validation tests: ./validate-kyverno.sh"
echo "2. Test policy enforcement with: kubectl run nginx --image=nginx --namespace=default"
echo "3. Monitor Kyverno metrics: kubectl port-forward -n kyverno svc/kyverno-svc 8000:8000"
echo ""
echo "Policy summary:"
echo "- require-plane-labels: Enforces plane ∈ {control,data,observability,execution,ai}"
echo "- require-tenant-labels: Enforces tenant label for RLS"
echo "- require-resource-limits: Blocks pods without requests/limits"
echo "- block-privileged-exec: Denies privileged containers in execution/ai planes"
echo "- enforce-readonly-root-fs: Immutable container filesystems"
echo "- rate-limit-admission: Limits pod creation bursts per namespace"
echo "- inject-spiffe-sidecar: Automatically injects SPIFFE sidecars"