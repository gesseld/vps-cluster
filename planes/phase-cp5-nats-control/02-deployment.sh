#!/bin/bash

# CP-5: Control Plane NATS (Stateless Signaling) - Deployment Script
# This script deploys a stateless NATS instance for critical control signals

set -e

echo "==========================================="
echo "CP-5: Control Plane NATS - Deployment"
echo "==========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="control-plane"
DEPLOYMENT_NAME="nats-stateless"
CONFIGMAP_NAME="nats-stateless-config"
SERVICE_NAME="nats-stateless"
PDB_NAME="nats-stateless-pdb"
SECRET_NAME="nats-stateless-tls"
CERT_NAME="nats-stateless-cert"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if resource exists
resource_exists() {
    kubectl get $1 $2 -n $3 &> /dev/null
}

# Function to wait for resource
wait_for_resource() {
    local resource=$1
    local name=$2
    local namespace=$3
    local timeout=$4
    local interval=5
    local elapsed=0
    
    log "Waiting for $resource/$name to be ready..."
    
    while [ $elapsed -lt $timeout ]; do
        if kubectl get $resource $name -n $namespace &> /dev/null; then
            if [ "$resource" == "pod" ]; then
                status=$(kubectl get pod $name -n $namespace -o jsonpath='{.status.phase}')
                if [ "$status" == "Running" ]; then
                    log "${GREEN}✓${NC} $resource/$name is running"
                    return 0
                fi
            else
                log "${GREEN}✓${NC} $resource/$name created"
                return 0
            fi
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log "${RED}✗${NC} Timeout waiting for $resource/$name"
    return 1
}

# Create directory for manifests
mkdir -p manifests

echo "Step 1: Creating NATS configuration..."
echo "-------------------------------------"

# Create NATS configuration file
cat > manifests/nats-config.conf << 'EOF'
# CP-5: Stateless NATS Configuration for Control Plane
port: 4222
http_port: 8222

# TLS Configuration (enabled if certificates available)
tls {
  cert_file: "/etc/nats-certs/tls.crt"
  key_file:  "/etc/nats-certs/tls.key"
  ca_file:   "/etc/nats-certs/ca.crt"
  timeout: 2
}

# Monitoring
server_name: "cp5-nats-stateless"
server_tags: ["control-plane", "stateless", "signaling"]

# Logging
logtime: true
log_file: "/dev/stdout"
debug: false
trace: false

# Accounts and Authorization
accounts {
  CONTROL {
    users: [
      { user: "controller", password: "${CONTROLLER_PASSWORD:-changeme}" }
    ]
    exports: [
      { service: "control.>" }
      { stream: "control.>" }
    ]
    imports: [
      { service: { account: "AUDIT", subject: "control.audit.>" } }
    ]
  }
  
  AUDIT {
    users: [
      { user: "auditor", password: "${AUDITOR_PASSWORD:-changeme}" }
    ]
    exports: [
      { service: "control.audit.>" }
      { stream: "control.audit.>" }
    ]
  }
  
  # System account for monitoring
  SYS {
    users: [
      { user: "sysadmin", password: "${SYSADMIN_PASSWORD:-changeme}" }
    ]
  }
}

# System account for monitoring
system_account: "SYS"

# JetStream disabled (stateless)
jetstream: false

# Cluster configuration (for future HA)
cluster {
  port: 6222
  routes: []
}

# Leaf node configuration (for connecting to data plane)
leafnodes {
  port: 7422
}
EOF

log "Created NATS configuration file"

echo ""
echo "Step 2: Creating Kubernetes manifests..."
echo "---------------------------------------"

# Create ConfigMap for NATS configuration
cat > manifests/stateless-nats-configmap.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: $CONFIGMAP_NAME
  namespace: $NAMESPACE
  labels:
    app: $DEPLOYMENT_NAME
    component: nats
    plane: control
data:
  nats.conf: |
$(cat manifests/nats-config.conf | sed 's/^/    /')
EOF

log "Created ConfigMap manifest"

# Create Deployment manifest
cat > manifests/stateless-nats-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $NAMESPACE
  labels:
    app: $DEPLOYMENT_NAME
    component: nats
    plane: control
    stateless: "true"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $DEPLOYMENT_NAME
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: $DEPLOYMENT_NAME
        component: nats
        plane: control
    spec:
      serviceAccountName: default
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
      - name: nats
        image: nats:2.10-alpine
        imagePullPolicy: IfNotPresent
        args: ["-c", "/etc/nats/nats.conf"]
        ports:
        - containerPort: 4222
          name: client
          protocol: TCP
        - containerPort: 8222
          name: monitor
          protocol: TCP
        - containerPort: 6222
          name: cluster
          protocol: TCP
        - containerPort: 7422
          name: leaf
          protocol: TCP
        env:
        - name: CONTROLLER_PASSWORD
          valueFrom:
            secretKeyRef:
              name: nats-auth-secrets
              key: controller-password
              optional: true
        - name: AUDITOR_PASSWORD
          valueFrom:
            secretKeyRef:
              name: nats-auth-secrets
              key: auditor-password
              optional: true
        - name: SYSADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: nats-auth-secrets
              key: sysadmin-password
              optional: true
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /
            port: 8222
          initialDelaySeconds: 10
          periodSeconds: 30
          timeoutSeconds: 5
        readinessProbe:
          httpGet:
            path: /
            port: 8222
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
        volumeMounts:
        - name: nats-config
          mountPath: /etc/nats
          readOnly: true
        - name: nats-certs
          mountPath: /etc/nats-certs
          readOnly: true
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
      volumes:
      - name: nats-config
        configMap:
          name: $CONFIGMAP_NAME
      - name: nats-certs
        secret:
          secretName: $SECRET_NAME
          optional: true
      tolerations:
      - key: "node-role.kubernetes.io/control-plane"
        operator: "Exists"
        effect: "NoSchedule"
      nodeSelector:
        node-role.kubernetes.io/control-plane: "true"
EOF

log "Created Deployment manifest"

# Create Service manifest
cat > manifests/stateless-nats-service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_NAME
  namespace: $NAMESPACE
  labels:
    app: $DEPLOYMENT_NAME
    component: nats
    plane: control
spec:
  selector:
    app: $DEPLOYMENT_NAME
  ports:
  - name: client
    port: 4222
    targetPort: 4222
    protocol: TCP
  - name: monitor
    port: 8222
    targetPort: 8222
    protocol: TCP
  - name: cluster
    port: 6222
    targetPort: 6222
    protocol: TCP
  - name: leaf
    port: 7422
    targetPort: 7422
    protocol: TCP
  type: ClusterIP
EOF

log "Created Service manifest"

# Create PodDisruptionBudget manifest
cat > manifests/stateless-nats-pdb.yaml << EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: $PDB_NAME
  namespace: $NAMESPACE
  labels:
    app: $DEPLOYMENT_NAME
    component: nats
    plane: control
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: $DEPLOYMENT_NAME
EOF

log "Created PodDisruptionBudget manifest"

# Create authentication secrets (if not using Cert-Manager TLS)
cat > manifests/nats-auth-secrets.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: nats-auth-secrets
  namespace: $NAMESPACE
  labels:
    app: $DEPLOYMENT_NAME
    component: nats
type: Opaque
stringData:
  controller-password: "\$(openssl rand -hex 16)"
  auditor-password: "\$(openssl rand -hex 16)"
  sysadmin-password: "\$(openssl rand -hex 16)"
EOF

log "Created authentication secrets manifest"

echo ""
echo "Step 3: Deploying to Kubernetes..."
echo "---------------------------------"

# Apply manifests in order
log "Creating authentication secrets..."
kubectl apply -f manifests/nats-auth-secrets.yaml

log "Creating ConfigMap..."
kubectl apply -f manifests/stateless-nats-configmap.yaml

log "Creating Deployment..."
kubectl apply -f manifests/stateless-nats-deployment.yaml

log "Creating Service..."
kubectl apply -f manifests/stateless-nats-service.yaml

log "Creating PodDisruptionBudget..."
kubectl apply -f manifests/stateless-nats-pdb.yaml

echo ""
echo "Step 4: Setting up TLS (if Cert-Manager available)..."
echo "----------------------------------------------------"

# Check if Cert-Manager is available
if kubectl get deployment cert-manager -n cert-manager &> /dev/null; then
    log "Cert-Manager detected, creating Certificate..."
    
    cat > manifests/nats-certificate.yaml << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: $CERT_NAME
  namespace: $NAMESPACE
spec:
  secretName: $SECRET_NAME
  duration: 2160h # 90 days
  renewBefore: 360h # 15 days
  subject:
    organizations:
    - control-plane
  commonName: $SERVICE_NAME.$NAMESPACE.svc.cluster.local
  dnsNames:
  - $SERVICE_NAME.$NAMESPACE.svc.cluster.local
  - $SERVICE_NAME.$NAMESPACE.svc
  - $SERVICE_NAME.$NAMESPACE
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
EOF
    
    # Check for ClusterIssuer
    if kubectl get clusterissuer selfsigned-issuer &> /dev/null; then
        kubectl apply -f manifests/nats-certificate.yaml
        log "Certificate created"
    else
        log "${YELLOW}⚠${NC} No selfsigned-issuer found. Creating one..."
        
        cat > manifests/selfsigned-issuer.yaml << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF
        
        kubectl apply -f manifests/selfsigned-issuer.yaml
        sleep 5
        kubectl apply -f manifests/nats-certificate.yaml
        log "Self-signed issuer and certificate created"
    fi
else
    log "${YELLOW}⚠${NC} Cert-Manager not available. TLS will not be enabled."
    log "To enable TLS later, create a secret named '$SECRET_NAME' with tls.crt, tls.key, and ca.crt"
fi

echo ""
echo "Step 5: Waiting for deployment to be ready..."
echo "--------------------------------------------"

# Wait for pods
PODS=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o name)
for POD in $PODS; do
    POD_NAME=${POD#pod/}
    wait_for_resource pod $POD_NAME $NAMESPACE 120
done

echo ""
echo "Step 6: Verification..."
echo "----------------------"

# Check deployment status
log "Checking deployment status..."
kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE

# Check service
log "Checking service..."
kubectl get service $SERVICE_NAME -n $NAMESPACE

# Check pods
log "Checking pods..."
kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o wide

# Check PDB
log "Checking PodDisruptionBudget..."
kubectl get pdb $PDB_NAME -n $NAMESPACE

echo ""
echo "Step 7: Testing connectivity..."
echo "------------------------------"

# Get a pod name for testing
TEST_POD=$(kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT_NAME -o jsonpath='{.items[0].metadata.name}')

if [ -n "$TEST_POD" ]; then
    log "Testing NATS server from pod: $TEST_POD"
    
    # Test basic connectivity
    if kubectl exec -n $NAMESPACE $TEST_POD -- nats-server --version &> /dev/null; then
        log "${GREEN}✓${NC} NATS server is running"
        
        # Test server info endpoint
        if kubectl exec -n $NAMESPACE $TEST_POD -- wget -q -O- http://localhost:8222/varz &> /dev/null; then
            log "${GREEN}✓${NC} Monitoring endpoint is accessible"
        else
            log "${YELLOW}⚠${NC} Monitoring endpoint check failed"
        fi
    else
        log "${RED}✗${NC} NATS server check failed"
    fi
fi

echo ""
echo "==========================================="
echo "Deployment Summary"
echo "==========================================="
echo ""
echo "Deployed resources:"
echo "  ✅ ConfigMap: $CONFIGMAP_NAME"
echo "  ✅ Deployment: $DEPLOYMENT_NAME (2 replicas)"
echo "  ✅ Service: $SERVICE_NAME"
echo "  ✅ PodDisruptionBudget: $PDB_NAME"
echo "  ✅ Authentication secrets"
echo ""
echo "Access points:"
echo "  • Client: $SERVICE_NAME.$NAMESPACE.svc.cluster.local:4222"
echo "  • Monitoring: $SERVICE_NAME.$NAMESPACE.svc.cluster.local:8222"
echo ""
echo "Subjects configured:"
echo "  • control.critical.* - Critical control signals"
echo "  • control.audit.* - Audit and logging signals"
echo ""
echo "Accounts:"
echo "  • CONTROL - Full access to control.* subjects"
echo "  • AUDIT - Access to control.audit.* subjects"
echo "  • SYS - System monitoring"
echo ""
echo "Next steps:"
echo "1. Run validation script: ./03-validation.sh"
echo "2. Configure network policies if needed"
echo "3. Set up data plane NATS leaf node connection"
echo ""
echo "Deployment completed successfully!"
echo "==========================================="