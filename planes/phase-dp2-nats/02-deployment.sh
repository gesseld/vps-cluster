#!/bin/bash

set -e

echo "========================================="
echo "NATS JetStream Deployment"
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
STORAGE_CLASS=${STORAGE_CLASS:-""}
PVC_SIZE=${PVC_SIZE:-15Gi}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function for colored output
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "success")
            echo -e "${GREEN}✓${NC} $message"
            ;;
        "error")
            echo -e "${RED}✗${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}⚠${NC} $message"
            ;;
        "info")
            echo -e "  $message"
            ;;
    esac
}

# Function to check command success
check_command() {
    if [ $? -eq 0 ]; then
        print_status "success" "$1"
    else
        print_status "error" "$1 failed"
        exit 1
    fi
}

echo "Starting NATS JetStream deployment in namespace: $NAMESPACE"
echo ""

# Step 1: Create TLS certificates (self-signed for simplicity)
echo "Step 1: Creating TLS certificates..."
if ! kubectl get secret nats-tls -n "$NAMESPACE" &> /dev/null; then
    print_status "info" "Creating self-signed TLS certificates..."
    
    # Create temporary directory for certs
    TEMP_DIR=$(mktemp -d)
    
    # Generate CA
    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout "$TEMP_DIR/ca.key" -out "$TEMP_DIR/ca.crt" \
        -subj "/CN=NATS CA/O=NATS/OU=JetStream" 2>/dev/null
    
    # Generate server certificate
    openssl req -newkey rsa:4096 -sha256 -nodes \
        -keyout "$TEMP_DIR/server.key" -out "$TEMP_DIR/server.csr" \
        -subj "/CN=nats/O=NATS/OU=JetStream" 2>/dev/null
    
    # Sign server certificate
    openssl x509 -req -sha256 -days 365 \
        -in "$TEMP_DIR/server.csr" \
        -CA "$TEMP_DIR/ca.crt" -CAkey "$TEMP_DIR/ca.key" -CAcreateserial \
        -out "$TEMP_DIR/server.crt" 2>/dev/null
    
    # Create Kubernetes secret
    kubectl create secret generic nats-tls -n "$NAMESPACE" \
        --from-file=tls.crt="$TEMP_DIR/server.crt" \
        --from-file=tls.key="$TEMP_DIR/server.key" \
        --from-file=ca.crt="$TEMP_DIR/ca.crt"
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    check_command "TLS certificates created"
else
    print_status "success" "TLS certificates already exist"
fi

# Step 2: Update Helm repository
echo ""
echo "Step 2: Updating Helm repository..."
helm repo update
check_command "Helm repository updated"

# Step 3: Deploy NATS with Helm
echo ""
echo "Step 3: Deploying NATS with Helm..."

# Prepare Helm values
HELM_VALUES_FILE="data-plane/nats/values.yaml"

# Update storage configuration in values if provided
if [ -n "$STORAGE_CLASS" ] || [ -n "$PVC_SIZE" ]; then
    print_status "info" "Configuring storage..."
    
    # Create a temporary values file with updated storage configuration
    TEMP_VALUES=$(mktemp)
    cp "$HELM_VALUES_FILE" "$TEMP_VALUES"
    
    if [ -n "$STORAGE_CLASS" ]; then
        print_status "info" "Using storage class: $STORAGE_CLASS"
        sed -i "s/storageClassName: \"\"/storageClassName: \"$STORAGE_CLASS\"/" "$TEMP_VALUES"
    fi
    
    if [ -n "$PVC_SIZE" ]; then
        print_status "info" "Setting PVC size: $PVC_SIZE"
        # Update storage size in global.jetstream.fileStorage
        sed -i "s/storageSize: 15Gi/storageSize: $PVC_SIZE/" "$TEMP_VALUES"
        # Update max_file_store in serverConfig
        # Convert Gi to bytes for server config
        if [[ "$PVC_SIZE" =~ ([0-9]+)Gi ]]; then
            SIZE_GB=${BASH_REMATCH[1]}
            SIZE_BYTES=$((SIZE_GB * 1024 * 1024 * 1024))
            OVERHEAD_BYTES=$((1024 * 1024 * 1024))  # 1Gi overhead
            MAX_FILE=$((SIZE_BYTES - OVERHEAD_BYTES))
            sed -i "s/max_file_store: 15032385536/max_file_store: $MAX_FILE/" "$TEMP_VALUES"
        fi
    fi
    
    HELM_VALUES_FILE="$TEMP_VALUES"
fi

# Install or upgrade NATS
if helm status nats -n "$NAMESPACE" &> /dev/null; then
    print_status "info" "Upgrading existing NATS deployment..."
    helm upgrade nats "$HELM_REPO/$HELM_CHART" \
        --version "$HELM_CHART_VERSION" \
        -n "$NAMESPACE" \
        -f "$HELM_VALUES_FILE" \
        --wait \
        --timeout 10m
else
    print_status "info" "Installing new NATS deployment..."
    helm install nats "$HELM_REPO/$HELM_CHART" \
        --version "$HELM_CHART_VERSION" \
        -n "$NAMESPACE" \
        -f "$HELM_VALUES_FILE" \
        --wait \
        --timeout 10m
fi

check_command "NATS Helm deployment completed"

# Cleanup temporary values file
if [ -n "$TEMP_VALUES" ] && [ -f "$TEMP_VALUES" ]; then
    rm -f "$TEMP_VALUES"
fi

# Step 4: Apply additional configurations
echo ""
echo "Step 4: Applying additional configurations..."

# Apply stream configuration
print_status "info" "Applying stream configuration..."
kubectl apply -f data-plane/nats/stream-config.yaml -n "$NAMESPACE"
check_command "Stream configuration applied"

# Apply network policies
print_status "info" "Applying network policies..."
kubectl apply -f data-plane/nats/networkpolicy.yaml -n "$NAMESPACE"
check_command "Network policies applied"

# Apply Pod Disruption Budget
print_status "info" "Applying Pod Disruption Budget..."
kubectl apply -f data-plane/nats/pdb.yaml -n "$NAMESPACE"
check_command "Pod Disruption Budget applied"

# Apply metrics exporter configuration
print_status "info" "Applying metrics exporter configuration..."
kubectl apply -f data-plane/nats/metrics-exporter.yaml -n "$NAMESPACE"
check_command "Metrics exporter configuration applied"

# Apply VMAgent configuration for VictoriaMetrics
print_status "info" "Applying VMAgent configuration for VictoriaMetrics..."
kubectl apply -f data-plane/nats/vmagent-config.yaml -n "$NAMESPACE"
check_command "VMAgent configuration applied"

# Step 5: Create required namespaces and labels
echo ""
echo "Step 5: Setting up namespaces..."

# Create and label namespaces if they don't exist
for ns in execution control observability; do
    if ! kubectl get namespace "$ns" &> /dev/null; then
        print_status "info" "Creating namespace: $ns"
        kubectl create namespace "$ns"
        check_command "Namespace $ns created"
    fi
    
    # Label namespace
    print_status "info" "Labeling namespace: $ns"
    kubectl label namespace "$ns" kubernetes.io/metadata.name="$ns" --overwrite
    check_command "Namespace $ns labeled"
done

# Step 6: Wait for NATS to be ready
echo ""
echo "Step 6: Waiting for NATS to be ready..."

# Wait for NATS pod
print_status "info" "Waiting for NATS pod..."
kubectl wait --for=condition=ready pod -l app=nats -n "$NAMESPACE" --timeout=300s
check_command "NATS pod is ready"

# Wait for NATS exporter pod
print_status "info" "Waiting for NATS exporter pod..."
kubectl wait --for=condition=ready pod -l app=nats,component=exporter -n "$NAMESPACE" --timeout=180s
check_command "NATS exporter pod is ready"

# Step 7: Create JetStream streams
echo ""
echo "Step 7: Creating JetStream streams..."

# Get NATS pod name
NATS_POD=$(kubectl get pod -l app=nats -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}')

# Copy stream creation script to pod
print_status "info" "Copying stream creation script to NATS pod..."
kubectl cp data-plane/nats/stream-config.yaml "$NAMESPACE/$NATS_POD:/tmp/stream-config.yaml" -c nats

# Extract and execute stream creation script
print_status "info" "Creating streams..."
kubectl exec "$NATS_POD" -n "$NAMESPACE" -c nats -- sh -c '
    # Extract the create-streams.sh script from configmap
    grep -A 1000 "create-streams.sh: |" /tmp/stream-config.yaml | \
    tail -n +2 | sed "s/^  //" > /tmp/create-streams.sh
    
    # Make it executable and run
    chmod +x /tmp/create-streams.sh
    /tmp/create-streams.sh
'

check_command "JetStream streams created"

# Step 8: Verify deployment
echo ""
echo "Step 8: Verifying deployment..."

# Check pods
print_status "info" "Checking pods..."
kubectl get pods -n "$NAMESPACE" -l app=nats

# Check services
print_status "info" "Checking services..."
kubectl get svc -n "$NAMESPACE" -l app=nats

# Check PVC
print_status "info" "Checking PersistentVolumeClaim..."
kubectl get pvc -n "$NAMESPACE" -l app=nats

# Check network policies
print_status "info" "Checking network policies..."
kubectl get networkpolicy -n "$NAMESPACE" -l app=nats

# Check PDB
print_status "info" "Checking PodDisruptionBudget..."
kubectl get pdb -n "$NAMESPACE" -l app=nats

# Step 9: Display connection information
echo ""
echo "Step 9: Connection Information"
echo "=============================="

# Get service IP/port
NATS_SERVICE=$(kubectl get svc nats -n "$NAMESPACE" -o jsonpath='{.metadata.name}')
NATS_CLUSTER_IP=$(kubectl get svc nats -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
NATS_PORT=$(kubectl get svc nats -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="client")].port}')

# Get exporter service
EXPORTER_SERVICE=$(kubectl get svc nats-exporter -n "$NAMESPACE" -o jsonpath='{.metadata.name}' 2>/dev/null || echo "nats-exporter")
EXPORTER_PORT=$(kubectl get svc "$EXPORTER_SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="metrics")].port}' 2>/dev/null || echo "7777")

echo "NATS Server:"
echo "  Internal: nats://$NATS_SERVICE.$NAMESPACE.svc.cluster.local:$NATS_PORT"
echo "  ClusterIP: nats://$NATS_CLUSTER_IP:$NATS_PORT"
echo ""
echo "Monitoring:"
echo "  Server Metrics: http://$NATS_SERVICE.$NAMESPACE.svc.cluster.local:8222"
echo "  VictoriaMetrics Export: http://$EXPORTER_SERVICE.$NAMESPACE.svc.cluster.local:$EXPORTER_PORT/metrics"
echo ""
echo "Streams Created:"
echo "  • DOCUMENTS (data.doc.>) - WorkQueue, 100k messages, 5GB"
echo "  • EXECUTION (exec.task.>) - Interest, 24h retention"
echo "  • OBSERVABILITY (obs.metric.>) - Limits, 1GB"
echo ""
echo "TLS Configuration:"
echo "  • TLS enabled on port 4222"
echo "  • Self-signed certificates (for development)"
echo "  • CA certificate in secret 'nats-tls'"
echo ""
echo "Next Steps:"
echo "  1. Run ./03-validation.sh to validate the deployment"
echo "  2. Configure your applications to connect to NATS"
echo "  3. Set up VictoriaMetrics alerts for backpressure >80%"
echo "  4. Import Grafana dashboard for VictoriaMetrics"
echo ""
echo "To test connection from within cluster:"
echo "  kubectl run -it --rm test-nats --image=natsio/nats-box --restart=Never -- \\"
echo "    nats --server nats://nats:$NATS_PORT pub test.hello 'Hello NATS!'"
echo ""
print_status "success" "NATS JetStream deployment completed successfully!"