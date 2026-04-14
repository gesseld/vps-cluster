#!/bin/bash
set -e

echo "=========================================="
echo "Temporal Server CP-1: Deployment"
echo "=========================================="
echo "Deploying Temporal Server with HA configuration..."
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

# Create namespace if it doesn't exist
echo "1. Ensuring namespace '$NAMESPACE' exists..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create Temporal manifests directory
MANIFESTS_DIR="$(dirname "$0")/control-plane/temporal"
echo "2. Creating Temporal manifests in $MANIFESTS_DIR..."

# Create the dynamic config
echo "3. Creating dynamic configuration..."
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
  defaultStore: "postgresql"
  visibilityStore: "postgresql"
  
  # Connection pooling
  numHistoryShards: 512
  maxQPS: 1000

clusterMetadata:
  # HA cluster configuration
  enableGlobalNamespace: false
  failoverVersionIncrement: 10
  masterClusterName: "active-active"
EOF

# Create the StatefulSet manifest
echo "4. Creating Temporal Server StatefulSet..."
cat > "$MANIFESTS_DIR/temporal-server.yaml" <<EOF
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
        - name: SERVICES
          value: "frontend,history,matching"
        - name: SQL_PLUGIN
          value: "postgres12"
        - name: DB
          value: "postgresql"
        - name: DB_PORT
          value: "5432"
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
        - name: DYNAMIC_CONFIG_FILE_PATH
          value: "/etc/temporal/config/dynamicconfig.yaml"
        - name: ENABLE_ES
          value: "false"
        - name: LOG_LEVEL
          value: "info"
        - name: NUM_HISTORY_SHARDS
          value: "512"
        
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
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: /health
            port: metrics
          initialDelaySeconds: 5
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

# Create the ConfigMap
echo "5. Creating Temporal ConfigMap..."
cat > "$MANIFESTS_DIR/config/config.yaml" <<EOF
# Temporal configuration
# This is mounted to /etc/temporal/config/config.yaml

# Database configuration
db:
  driver: "postgres"
  host: "\${POSTGRES_SEEDS:?required}"
  port: 5432
  user: "\${POSTGRES_USER:?required}"
  password: "\${POSTGRES_PWD:?required}"
  database: "temporal"
  connectAttributes:
    statement_cache_capacity: "100"
    default_transaction_isolation: "'read committed'"
  
  visibility:
    driver: "postgres"
    host: "\${POSTGRES_SEEDS:?required}"
    port: 5432
    user: "\${POSTGRES_USER:?required}"
    password: "\${POSTGRES_PWD:?required}"
    database: "temporal_visibility"
    connectAttributes:
      statement_cache_capacity: "100"
      default_transaction_isolation: "'read committed'"

# Public client configuration
publicClient:
  hostPort: "temporal.${NAMESPACE}.svc.cluster.local:7233"

# Frontend service configuration
frontend:
  bindOnLocalHost: false
  bindOnIP: "0.0.0.0"
  port: 7233
  maxConcurrentLongPollRequests: 5000
  rps: 10000

# History service configuration
history:
  bindOnLocalHost: false
  bindOnIP: "0.0.0.0"
  port: 7234
  numberOfShards: 512

# Matching service configuration
matching:
  bindOnLocalHost: false
  bindOnIP: "0.0.0.0"
  port: 7235
  maxTaskqueueActivitiesPerSecond: 100000

# Internal services (for inter-service communication)
internalFrontend:
  bindOnLocalHost: false
  bindOnIP: "0.0.0.0"
  port: 7236

internalHistory:
  bindOnLocalHost: false
  bindOnIP: "0.0.0.0"
  port: 7237

internalMatching:
  bindOnLocalHost: false
  bindOnIP: "0.0.0.0"
  port: 7238

# Metrics configuration
metrics:
  prometheus:
    listenAddress: "0.0.0.0:9090"
    handlerPath: "/metrics"

# Logging configuration
log:
  stdout: true
  level: "info"
  format: "json"

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
    retention: 72h

# Cluster metadata
clusterMetadata:
  enableGlobalNamespace: false
  failoverVersionIncrement: 10
  masterClusterName: "active-active"
  currentClusterName: "active-active"
EOF

# Create the Service manifest
echo "6. Creating Temporal Services..."
cat > "$MANIFESTS_DIR/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: temporal-headless
  namespace: $NAMESPACE
  labels:
    app: temporal
    component: server
spec:
  clusterIP: None
  ports:
  - name: frontend
    port: 7233
    targetPort: frontend
  - name: history
    port: 7234
    targetPort: history
  - name: matching
    port: 7235
    targetPort: matching
  - name: metrics
    port: 9090
    targetPort: metrics
  - name: internal-frontend
    port: 7236
    targetPort: int-frontend
  - name: internal-history
    port: 7237
    targetPort: int-history
  - name: internal-matching
    port: 7238
    targetPort: int-matching
  selector:
    app: temporal
    component: server
---
apiVersion: v1
kind: Service
metadata:
  name: temporal
  namespace: $NAMESPACE
  labels:
    app: temporal
    component: frontend
spec:
  type: ClusterIP
  ports:
  - name: frontend
    port: 7233
    targetPort: frontend
  selector:
    app: temporal
    component: server
EOF

# Create the PodDisruptionBudget
echo "7. Creating PodDisruptionBudget..."
cat > "$MANIFESTS_DIR/pdb.yaml" <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: temporal-pdb
  namespace: $NAMESPACE
  labels:
    app: temporal
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: temporal
      component: server
EOF

# Create the NetworkPolicy
echo "8. Creating NetworkPolicy..."
cat > "$MANIFESTS_DIR/networkpolicy.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: temporal-ingress
  namespace: $NAMESPACE
  labels:
    app: temporal
spec:
  podSelector:
    matchLabels:
      app: temporal
      component: server
  policyTypes:
  - Ingress
  ingress:
  # Allow from execution-plane namespace
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: execution-plane
    ports:
    - protocol: TCP
      port: 7233
    - protocol: TCP
      port: 7234
    - protocol: TCP
      port: 7235
  
  # Allow internal communication
  - from:
    - podSelector:
        matchLabels:
          app: temporal
          component: server
    ports:
    - protocol: TCP
      port: 7236
    - protocol: TCP
      port: 7237
    - protocol: TCP
      port: 7238
  
  # Allow metrics scraping from observability-plane
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: observability-plane
    ports:
    - protocol: TCP
      port: 9090
EOF

# Create the ServiceAccount and RBAC
echo "9. Creating ServiceAccount and RBAC..."
cat > "$MANIFESTS_DIR/rbac.yaml" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: temporal-server
  namespace: $NAMESPACE
  labels:
    app: temporal
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: temporal-server
  namespace: $NAMESPACE
  labels:
    app: temporal
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: temporal-server
  namespace: $NAMESPACE
  labels:
    app: temporal
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: temporal-server
subjects:
- kind: ServiceAccount
  name: temporal-server
  namespace: $NAMESPACE
EOF

# Create the ConfigMap from config files
echo "10. Creating ConfigMap from configuration files..."
kubectl create configmap temporal-config -n "$NAMESPACE" \
  --from-file="$MANIFESTS_DIR/config/config.yaml" \
  --from-file="$MANIFESTS_DIR/config/dynamicconfig.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply all manifests
echo "11. Applying Temporal manifests..."
kubectl apply -f "$MANIFESTS_DIR/rbac.yaml"
kubectl apply -f "$MANIFESTS_DIR/service.yaml"
kubectl apply -f "$MANIFESTS_DIR/networkpolicy.yaml"
kubectl apply -f "$MANIFESTS_DIR/pdb.yaml"
kubectl apply -f "$MANIFESTS_DIR/temporal-server.yaml"

echo
echo "=========================================="
echo "Deployment completed!"
echo "=========================================="
echo
echo "Temporal Server components deployed:"
echo "  ✓ ServiceAccount and RBAC"
echo "  ✓ ConfigMap with configuration"
echo "  ✓ Headless and frontend Services"
echo "  ✓ NetworkPolicy (ingress from execution-plane)"
echo "  ✓ PodDisruptionBudget (minAvailable: 1)"
echo "  ✓ StatefulSet with 2 replicas (HA)"
echo
echo "Waiting for pods to be ready..."
echo

# Wait for pods to be ready
TIMEOUT=300
INTERVAL=5
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    READY_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=temporal,component=server -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c True || true)
    TOTAL_PODS=$(kubectl get pods -n "$NAMESPACE" -l app=temporal,component=server --no-headers | wc -l | tr -d ' ')
    
    if [ "$READY_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -eq 2 ]; then
        echo "✓ All $TOTAL_PODS Temporal pods are ready!"
        break
    fi
    
    echo "  Waiting... ($READY_PODS/$TOTAL_PODS pods ready)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "⚠️  Timeout waiting for pods to be ready"
        echo "   Check pod status with: kubectl get pods -n $NAMESPACE -l app=temporal"
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
echo "  2. Test connectivity: kubectl port-forward -n $NAMESPACE svc/temporal 7233:7233"
echo "  3. Use tctl: tctl --address localhost:7233 cluster health"
echo
echo "Note: Ensure PostgreSQL with 'temporal' and 'temporal_visibility' databases"
echo "      is deployed in Data Plane before Temporal can start fully."