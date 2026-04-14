#!/bin/bash
set -e

echo "=========================================="
echo "Temporal Server CP-1: Fixed Deployment"
echo "=========================================="
echo "Deploying Temporal Server with proper configuration..."
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

echo "Deployment Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Temporal Version: $TEMPORAL_VERSION"
echo "  Storage Class: $STORAGE_CLASS"
echo "  Priority Class: $PRIORITY_CLASS"
echo

# Clean up any existing deployment
echo "0. Cleaning up any existing deployment..."
kubectl delete -f control-plane/temporal/ 2>/dev/null || true
kubectl delete configmap temporal-config -n "$NAMESPACE" 2>/dev/null || true
kubectl delete configmap temporal-main-config -n "$NAMESPACE" 2>/dev/null || true
sleep 5

# Create namespace if it doesn't exist
echo "1. Ensuring namespace '$NAMESPACE' exists..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create Temporal manifests directory
MANIFESTS_DIR="$(dirname "$0")/control-plane/temporal"
echo "2. Using Temporal manifests in $MANIFESTS_DIR..."

# Create the proper Temporal config
echo "3. Creating proper Temporal configuration..."
cat > "$MANIFESTS_DIR/config/temporal-config.yaml" <<EOF
# Temporal Server Configuration
# Complete configuration for monolith mode

# Global configuration
global:
  membership:
    broadcastAddress: "0.0.0.0"
  metrics:
    prometheus:
      listenAddress: "0.0.0.0:9090"
      handlerPath: "/metrics"
  pprof:
    port: 7933

# Persistence configuration
persistence:
  defaultStore: "postgres"
  visibilityStore: "postgres"
  numHistoryShards: 512
  
  datastores:
    postgres:
      sql:
        pluginName: "postgres12"
        databaseName: "temporal"
        connectAddr: "\${POSTGRES_SEEDS:?required}:5432"
        connectProtocol: "tcp"
        user: "\${POSTGRES_USER:?required}"
        password: "\${POSTGRES_PWD:?required}"
        maxConns: 20
        maxIdleConns: 20
        maxConnLifetime: "1h"
    
    postgres_visibility:
      sql:
        pluginName: "postgres12"
        databaseName: "temporal_visibility"
        connectAddr: "\${POSTGRES_SEEDS:?required}:5432"
        connectProtocol: "tcp"
        user: "\${POSTGRES_USER:?required}"
        password: "\${POSTGRES_PWD:?required}"
        maxConns: 20
        maxIdleConns: 20
        maxConnLifetime: "1h"

# Cluster metadata
clusterMetadata:
  enableGlobalNamespace: false
  failoverVersionIncrement: 10
  masterClusterName: "active"
  currentClusterName: "active"
  clusterInformation:
    active:
      enabled: true
      initialFailoverVersion: 0
      rpcAddress: "127.0.0.1:7233"
      httpAddress: "127.0.0.1:7400"

# Services configuration
services:
  frontend:
    rpc:
      grpcPort: 7233
      membershipPort: 6933
      bindOnLocalHost: false
    publicClient:
      hostPort: "0.0.0.0:7233"
  
  history:
    rpc:
      grpcPort: 7234
      membershipPort: 6934
      bindOnLocalHost: false
  
  matching:
    rpc:
      grpcPort: 7235
      membershipPort: 6935
      bindOnLocalHost: false
  
  internal-frontend:
    rpc:
      grpcPort: 7236
      membershipPort: 6936
      bindOnLocalHost: false
  
  internal-history:
    rpc:
      grpcPort: 7237
      membershipPort: 6937
      bindOnLocalHost: false
  
  internal-matching:
    rpc:
      grpcPort: 7238
      membershipPort: 6938
      bindOnLocalHost: false

# Archival configuration (disabled)
archival:
  history:
    state: "disabled"
    enableRead: false
  visibility:
    state: "disabled"
    enableRead: false

# Namespace configuration
namespace:
  default:
    retention: "72h"

# Logging configuration
log:
  stdout: true
  level: "info"
  format: "json"

# Dynamic config file path
dynamicConfigClient:
  filepath: "/etc/temporal/config/dynamicconfig.yaml"
EOF

# Create the dynamic config
echo "4. Creating dynamic configuration..."
cat > "$MANIFESTS_DIR/config/dynamicconfig.yaml" <<EOF
# Temporal dynamic configuration
# Retention policies and HA settings

frontend:
  # Retention settings
  retention: 72h  # 3 days for completed workflows
  visibilityRetention: 168h  # 7 days for visibility records
  
  # HA settings
  enableRemoteClusterMetadataRefresh: true
  maxConcurrentLongPollRequests: 5000
  
  # Rate limiting
  rps: 10000

history:
  # Shard management for HA
  numberOfShards: 512
  enableShardIDMetrics: true
  
  # Retention
  workflowExecutionRetentionPeriod: 72h

matching:
  # Task queue management
  maxTaskqueueActivitiesPerSecond: 100000
  loadUserData: true

system:
  # Advanced visibility
  enableAdvancedVisibility: true
  advancedVisibilityWritingMode: "dual"
  
  # Archival (disabled for now)
  enableArchival: false

persistence:
  # PostgreSQL settings
  defaultStore: "postgres"
  visibilityStore: "postgres"
  
  # Connection pooling
  numHistoryShards: 512
  maxQPS: 1000

clusterMetadata:
  # HA cluster configuration
  enableGlobalNamespace: false
  failoverVersionIncrement: 10
  masterClusterName: "active"
EOF

# Create the StatefulSet with proper config
echo "5. Creating Temporal Server StatefulSet with proper config..."
cat > "$MANIFESTS_DIR/temporal-server-fixed.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: temporal
  namespace: $NAMESPACE
  labels:
    app: temporal
    component: server
    plane: control
spec:
  serviceName: temporal-headless
  replicas: 2
  selector:
    matchLabels:
      app: temporal
      component: server
  template:
    metadata:
      labels:
        app: temporal
        component: server
        plane: control
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: temporal-server
      priorityClassName: $PRIORITY_CLASS
      terminationGracePeriodSeconds: 30
      
      # Anti-affinity for HA
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: temporal
                component: server
            topologyKey: kubernetes.io/hostname
      
      # Topology spread across nodes
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app: temporal
            component: server
      
      containers:
      - name: temporal
        image: temporalio/server:$TEMPORAL_VERSION
        imagePullPolicy: IfNotPresent
        
        # Resource allocation: 750MB request / 1GB limit
        resources:
          requests:
            memory: "750Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        
        # Port configuration
        ports:
        - name: frontend
          containerPort: 7233
          protocol: TCP
        - name: history
          containerPort: 7234
          protocol: TCP
        - name: matching
          containerPort: 7235
          protocol: TCP
        - name: metrics
          containerPort: 9090
          protocol: TCP
        - name: int-frontend
          containerPort: 7236
          protocol: TCP
        - name: int-history
          containerPort: 7237
          protocol: TCP
        - name: int-matching
          containerPort: 7238
          protocol: TCP
        
        # Environment variables
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: temporal-postgres-creds
              key: username
        - name: POSTGRES_PWD
          valueFrom:
            secretKeyRef:
              name: temporal-postgres-creds
              key: password
        - name: POSTGRES_SEEDS
          valueFrom:
            secretKeyRef:
              name: temporal-postgres-creds
              key: host
        
        # Volume mounts
        volumeMounts:
        - name: config
          mountPath: /etc/temporal/config
          readOnly: true
        - name: data
          mountPath: /var/lib/temporal
        
        # Health checks
        livenessProbe:
          httpGet:
            path: /health
            port: metrics
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: /health
            port: metrics
          initialDelaySeconds: 30
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 1
        
        # Security context
        securityContext:
          runAsUser: 1000
          runAsGroup: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
  
      # Volumes
      volumes:
      - name: config
        configMap:
          name: temporal-config
      - name: data
        emptyDir: {}
  
  # PVC template (optional for persistence)
  volumeClaimTemplates:
  - metadata:
      name: temporal-data
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: $STORAGE_CLASS
      resources:
        requests:
          storage: 10Gi
EOF

# Create ConfigMaps
echo "6. Creating ConfigMaps..."
kubectl create configmap temporal-config -n "$NAMESPACE" \
  --from-file="$MANIFESTS_DIR/config/temporal-config.yaml" \
  --from-file="$MANIFESTS_DIR/config/dynamicconfig.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply all manifests
echo "7. Applying Temporal manifests..."
kubectl apply -f "$MANIFESTS_DIR/rbac.yaml"
kubectl apply -f "$MANIFESTS_DIR/service.yaml"
kubectl apply -f "$MANIFESTS_DIR/networkpolicy.yaml"
kubectl apply -f "$MANIFESTS_DIR/pdb.yaml"
kubectl apply -f "$MANIFESTS_DIR/temporal-server-fixed.yaml"

echo
echo "=========================================="
echo "Fixed deployment completed!"
echo "=========================================="
echo
echo "Temporal Server components deployed:"
echo "  ✓ ServiceAccount and RBAC"
echo "  ✓ ConfigMap with proper configuration"
echo "  ✓ Headless and frontend Services"
echo "  ✓ NetworkPolicy (ingress from execution-plane)"
echo "  ✓ PodDisruptionBudget (minAvailable: 1)"
echo "  ✓ StatefulSet with 2 replicas (HA) and proper config"
echo
echo "Waiting for pods to be ready..."
echo

# Wait for pods to be ready
TIMEOUT=300
INTERVAL=10
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    READY_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=temporal,component=server -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c True || true)
    TOTAL_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=temporal,component=server --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$TOTAL_PODS" -eq 0 ]; then
        echo "  No pods found yet..."
    elif [ "$READY_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
        echo "✓ All $TOTAL_PODS Temporal pods are ready!"
        break
    else
        echo "  Waiting... ($READY_PODS/$TOTAL_PODS pods ready)"
        # Show pod status
        kubectl get pods -n "$NAMESPACE" -l app=temporal,component=server --no-headers 2>/dev/null | head -5
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "⚠️  Timeout waiting for pods to be ready"
        echo "   Check pod status with: kubectl get pods -n $NAMESPACE -l app=temporal"
        echo "   Check logs with: kubectl logs -n $NAMESPACE -l app=temporal"
        break
    fi
done

echo
echo "Deployment Summary:"
echo "  Namespace: $NAMESPACE"
echo "  Replicas: 2 (HA with anti-affinity)"
echo "  Resources: 750Mi request / 1Gi limit per pod"
echo "  Ports: 7233 (frontend), 7234-7238 (internal)"
echo "  Metrics: 9090 (Prometheus)"
echo
echo "Next steps:"
echo "  1. Run validation: ./03-validation.sh"
echo "  2. Check logs: kubectl logs -n $NAMESPACE -l app=temporal"
echo "  3. Test connectivity: kubectl port-forward -n $NAMESPACE svc/temporal 7233:7233"
echo
echo "Note: Ensure PostgreSQL is running and accessible."