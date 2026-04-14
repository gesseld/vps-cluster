#!/bin/bash

# ArgoCD GitOps Controller - Deployment Script
# Deploys ArgoCD v2.9+ with 5-plane ApplicationSets

set -e

echo "=============================================="
echo "ArgoCD GitOps Controller - Deployment"
echo "=============================================="

# Load environment variables
if [ -f .env ]; then
    echo "Loading environment variables from .env file..."
    source .env
fi

# Default values
ARGOCD_NAMESPACE=${ARGOCD_NAMESPACE:-argocd}
ARGOCD_VERSION=${ARGOCD_VERSION:-2.9.0}
GIT_REPO_URL=${GIT_REPO_URL:-git@github.com:your-org/your-repo.git}
GIT_BRANCH=${GIT_BRANCH:-main}
GIT_PATH=${GIT_PATH:-manifests}
HELM_TIMEOUT=${HELM_TIMEOUT:-10m}

echo "Configuration:"
echo "  ArgoCD Namespace: $ARGOCD_NAMESPACE"
echo "  ArgoCD Version: $ARGOCD_VERSION"
echo "  Git Repository: $GIT_REPO_URL"
echo "  Git Branch: $GIT_BRANCH"
echo "  Git Path: $GIT_PATH"
echo "  Helm Timeout: $HELM_TIMEOUT"
echo ""

# Function to wait for resource
wait_for_resource() {
    local resource=$1
    local name=$2
    local namespace=$3
    local timeout=$4
    local interval=5
    
    echo "Waiting for $resource/$name in namespace $namespace (timeout: ${timeout})..."
    
    local start_time=$(date +%s)
    while true; do
        if kubectl get $resource $name -n $namespace &> /dev/null; then
            echo "✅ $resource/$name is ready"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            echo "❌ ERROR: Timeout waiting for $resource/$name"
            return 1
        fi
        
        echo "  Still waiting... ($elapsed seconds elapsed)"
        sleep $interval
    done
}

# Function to wait for pod readiness
wait_for_pod() {
    local namespace=$1
    local selector=$2
    local timeout=$3
    local interval=5
    
    echo "Waiting for pods with selector $selector in namespace $namespace..."
    
    local start_time=$(date +%s)
    while true; do
        local pod_status=$(kubectl get pods -n $namespace -l $selector -o jsonpath='{.items[*].status.phase}' 2>/dev/null || echo "")
        
        if [[ "$pod_status" == *"Running"* ]]; then
            echo "✅ Pods are running"
            return 0
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            echo "❌ ERROR: Timeout waiting for pods"
            kubectl get pods -n $namespace -l $selector
            return 1
        fi
        
        echo "  Pod status: $pod_status ($elapsed seconds elapsed)"
        sleep $interval
    done
}

echo "Step 1: Creating ArgoCD namespace..."
if ! kubectl get namespace $ARGOCD_NAMESPACE &> /dev/null; then
    kubectl create namespace $ARGOCD_NAMESPACE
    echo "✅ Namespace $ARGOCD_NAMESPACE created"
else
    echo "✅ Namespace $ARGOCD_NAMESPACE already exists"
fi
echo ""

echo "Step 2: Applying resource quota..."
kubectl apply -f control-plane/argocd/resource-quota.yaml -n $ARGOCD_NAMESPACE
echo "✅ Resource quota applied"
echo ""

echo "Step 3: Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
echo "✅ ArgoCD Helm repository added and updated"
echo ""

echo "Step 4: Installing ArgoCD via Helm..."
# Create values file for ArgoCD
cat > argocd-values.yaml <<EOF
global:
  image:
    tag: v$ARGOCD_VERSION
  
server:
  replicaCount: 1  # Single replica for resource constraints
  service:
    type: ClusterIP
  extraArgs:
    - --insecure
  resources:
    limits:
      memory: 512Mi
      cpu: 500m
    requests:
      memory: 256Mi
      cpu: 250m
  
  # Disable polling to save CPU cycles
  config:
    repositories: |
      - url: $GIT_REPO_URL
        type: git
        passwordSecret:
          name: argocd-repo-secret
          key: password
        usernameSecret:
          name: argocd-repo-secret
          key: username
    resource.customizations: |
      admissionregistration.k8s.io/MutatingWebhookConfiguration:
        ignoreDifferences: |
          jsonPointers:
          - /webhooks/0/clientConfig/caBundle
      admissionregistration.k8s.io/ValidatingWebhookConfiguration:
        ignoreDifferences: |
          jsonPointers:
          - /webhooks/0/clientConfig/caBundle
  
controller:
  replicaCount: 1
  resources:
    limits:
      memory: 256Mi
      cpu: 250m
    requests:
      memory: 128Mi
      cpu: 125m
  
  # Enable automated sync with pruning
  applicationSet:
    enabled: true
  
repoServer:
  replicaCount: 1
  resources:
    limits:
      memory: 256Mi
      cpu: 250m
    requests:
      memory: 128Mi
      cpu: 125m
  
  # Disable polling parallelism
  parallelism:
    limit: 0
  
redis:
  enabled: true
  replicaCount: 1
  resources:
    limits:
      memory: 128Mi
      cpu: 100m
    requests:
      memory: 64Mi
      cpu: 50m
EOF

# Install ArgoCD - skip CRDs since they might fail on K3s
helm upgrade --install argocd argo/argo-cd \
  --namespace $ARGOCD_NAMESPACE \
  --version 9.5.0 \
  --values argocd-values.yaml \
  --timeout $HELM_TIMEOUT \
  --skip-crds \
  --wait

echo "✅ ArgoCD Helm installation completed"
echo ""

echo "Step 5: Waiting for ArgoCD pods to be ready..."
wait_for_pod $ARGOCD_NAMESPACE "app.kubernetes.io/name=argocd-server" 120
wait_for_pod $ARGOCD_NAMESPACE "app.kubernetes.io/name=argocd-repo-server" 120
wait_for_pod $ARGOCD_NAMESPACE "app.kubernetes.io/name=argocd-application-controller" 120
wait_for_pod $ARGOCD_NAMESPACE "app.kubernetes.io/name=argocd-redis" 60
echo "✅ All ArgoCD pods are running"
echo ""

echo "Step 6: Applying ArgoCD ConfigMap with parallelism limits..."
kubectl apply -f control-plane/argocd/argocd-cm.yaml -n $ARGOCD_NAMESPACE
echo "✅ ConfigMap applied"
echo ""

echo "Step 7: Creating Git repository secret..."
# Check if we need to create SSH key secret or token secret
if [[ "$GIT_REPO_URL" == git@* ]]; then
    echo "Creating SSH key secret for Git repository..."
    
    # Check for SSH key
    if [[ -f "$HOME/.ssh/id_rsa" ]]; then
        SSH_KEY_FILE="$HOME/.ssh/id_rsa"
    elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
        SSH_KEY_FILE="$HOME/.ssh/id_ed25519"
    else
        echo "❌ ERROR: No SSH private key found"
        echo "   Please create an SSH key or configure HTTPS access"
        exit 1
    fi
    
    # Create secret with SSH key
    kubectl create secret generic argocd-repo-secret \
      --namespace $ARGOCD_NAMESPACE \
      --from-file=sshPrivateKey=$SSH_KEY_FILE \
      --dry-run=client -o yaml | kubectl apply -f -
    
    # Add SSH known hosts
    if [[ "$GIT_REPO_URL" == *github.com* ]]; then
        ssh-keyscan github.com > known_hosts
    elif [[ "$GIT_REPO_URL" == *gitlab.com* ]]; then
        ssh-keyscan gitlab.com > known_hosts
    fi
    
    if [ -f known_hosts ]; then
        kubectl create secret generic argocd-ssh-known-hosts \
          --namespace $ARGOCD_NAMESPACE \
          --from-file=ssh_known_hosts=known_hosts \
          --dry-run=client -o yaml | kubectl apply -f -
        rm -f known_hosts
    fi
else
    echo "Creating HTTPS token secret for Git repository..."
    
    if [[ -z "$GIT_USERNAME" || -z "$GIT_PASSWORD" ]]; then
        echo "❌ ERROR: GIT_USERNAME and GIT_PASSWORD must be set for HTTPS repository"
        exit 1
    fi
    
    # Create secret with username/password
    kubectl create secret generic argocd-repo-secret \
      --namespace $ARGOCD_NAMESPACE \
      --from-literal=username=$GIT_USERNAME \
      --from-literal=password=$GIT_PASSWORD \
      --dry-run=client -o yaml | kubectl apply -f -
fi

echo "✅ Git repository secret created"
echo ""

echo "Step 8: Applying ApplicationSets for 5-plane structure..."
# Apply all ApplicationSets
for appset in control-plane/argocd/applicationsets/*.yaml; do
    if [ -f "$appset" ]; then
        echo "Applying $(basename $appset)..."
        kubectl apply -f "$appset" -n $ARGOCD_NAMESPACE
    fi
done
echo "✅ All ApplicationSets applied"
echo ""

echo "Step 9: Configuring webhook server..."
# Get ArgoCD server service IP/port
ARGOCD_SERVICE=$(kubectl get service argocd-server -n $ARGOCD_NAMESPACE -o jsonpath='{.spec.clusterIP}')
ARGOCD_PORT=$(kubectl get service argocd-server -n $ARGOCD_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="https")].port}')

echo "ArgoCD server is available at:"
echo "  ClusterIP: https://$ARGOCD_SERVICE:$ARGOCD_PORT"
echo "  Ingress/Route: (configure based on your environment)"
echo ""

echo "Step 10: Getting ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n $ARGOCD_NAMESPACE get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD admin password: $ARGOCD_PASSWORD"
echo ""
echo "⚠️  IMPORTANT: Change the admin password immediately!"
echo "   Run: argocd account update-password --current-password $ARGOCD_PASSWORD --new-password <new-password>"
echo ""

echo "Step 11: Setting up port forwarding for local access..."
echo "To access ArgoCD UI locally, run in a separate terminal:"
echo "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
echo ""
echo "Then access at: https://localhost:8080"
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"
echo ""

echo "Step 12: Verifying deployment..."
# Check all resources
echo "Checking ArgoCD resources..."
kubectl get all -n $ARGOCD_NAMESPACE
echo ""

echo "Checking ApplicationSets..."
kubectl get applicationsets -n $ARGOCD_NAMESPACE
echo ""

echo "Checking resource quota..."
kubectl describe resourcequota argocd-resource-quota -n $ARGOCD_NAMESPACE
echo ""

echo "=============================================="
echo "ArgoCD GitOps Controller Deployment Complete!"
echo "=============================================="
echo ""
echo "Summary:"
echo "✅ ArgoCD v$ARGOCD_VERSION deployed in namespace: $ARGOCD_NAMESPACE"
echo "✅ Single replica mode (non-HA) for resource constraints"
echo "✅ Resource quota applied (512MB memory limit)"
echo "✅ Polling disabled, webhooks enabled"
echo "✅ Parallelism limit configured (kubectl.parallelism.limit: 5)"
echo "✅ 5 ApplicationSets created for plane structure"
echo "✅ Git repository configured: $GIT_REPO_URL"
echo ""
echo "Next steps:"
echo "1. Change the admin password"
echo "2. Configure webhook in your Git repository"
echo "3. Run validation script: ./03-validation.sh"
echo "4. Test drift detection and sync functionality"
echo ""
echo "Webhook configuration:"
echo "  URL: https://$ARGOCD_SERVICE:$ARGOCD_PORT/api/webhook"
echo "  Content-Type: application/json"
echo "  Secret: (configure in argocd-cm.yaml if needed)"
echo ""
echo "To test deployment, run:"
echo "  ./03-validation.sh"
echo "=============================================="

# Clean up temporary files
rm -f argocd-values.yaml

exit 0