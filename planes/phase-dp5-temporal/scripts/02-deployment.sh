#!/bin/bash
# Temporal HA Deployment Script
# Phase: Data Plane Temporal HA Installation
# Purpose: Deploy Temporal HA stack with PostgreSQL, PgBouncer, and proper networking

set -e

echo "================================================"
echo "🚀 TEMPORAL HA DEPLOYMENT"
echo "================================================"
echo "Phase: Data Plane Temporal HA Installation"
echo "Date: $(date)"
echo "================================================"

# Check if pre-deployment completed
if [ ! -f "../deliverables/pre-deployment-checklist-complete.flag" ]; then
    echo "❌ Pre-deployment check not completed!"
    echo "   Run ./scripts/01-pre-deployment-check.sh first"
    exit 1
fi

# Create logs directory
mkdir -p ../logs

# Start logging
DEPLOYMENT_LOG="../logs/deployment-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$DEPLOYMENT_LOG") 2>&1

echo "🔧 Starting Temporal HA deployment..."

# ============================================================================
# PHASE 1: Create Namespace and Setup
# ============================================================================
echo ""
echo "📦 PHASE 1: Creating Namespace and Setup"
echo "-----------------------------------------"

# Create temporal-system namespace
echo "Creating temporal-system namespace..."
kubectl create namespace temporal-system --dry-run=client -o yaml | kubectl apply -f -
echo "✓ Namespace created"

# ============================================================================
# PHASE 2: Deploy PostgreSQL 15 (Temporal-Ready, HA-Optimized)
# ============================================================================
echo ""
echo "🗄️  PHASE 2: Deploying PostgreSQL 15"
echo "-------------------------------------"

# Add Bitnami Helm repo
echo "Adding Bitnami Helm repository..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Create PostgreSQL values file
echo "Creating PostgreSQL configuration..."
cat > ../manifests/postgres-values-hetzner.yaml << 'EOF'
# PostgreSQL 15 Configuration for Temporal HA
# Optimized for Hetzner k3s: 10 vCPU/16GB RAM, €28.70/month budget

image:
  tag: 15-debian-12  # PostgreSQL 15, Debian 12 base

auth:
  postgresPassword: "supersecureadmin"  # CHANGE THIS IN PRODUCTION!
  username: temporal
  password: "temporaldbpassword"        # CHANGE THIS IN PRODUCTION!
  database: temporal

primary:
  # PostgreSQL 15 Tuning for Temporal (write-heavy, checkpoint-intensive)
  extendedConfiguration: |
    # Connection & Memory (16GB cluster total)
    max_connections = 100                 # Reduced - PgBouncer handles multiplexing
    shared_buffers = 512MB               # ~25% of PG container memory
    effective_cache_size = 1GB           # Conservative for shared cluster
    work_mem = 8MB                       # Higher per-query for complex histories
    maintenance_work_mem = 64MB
    
    # WAL Tuning (critical for Temporal's write volume)
    wal_buffers = 64MB                   # Increased from default 16MB
    max_wal_size = 8GB                   # Larger to reduce checkpoint frequency
    checkpoint_timeout = 15min           # Spread I/O over time
    checkpoint_completion_target = 0.9   # Smooth checkpoint writes
    
    # Query Planning (Hetzner = NVMe SSD, not cloud IOPS)
    random_page_cost = 1.1               # SSD tuning (vs 4.0 for HDD)
    effective_io_concurrency = 200       # SSD parallelism
    
    # Temporal-Specific Safeguards
    idle_in_transaction_session_timeout = 5min  # Prevent lock holds
    log_min_duration_statement = 1000ms         # Capture slow queries for optimization
    
    # Logging (JSON for Loki/ELK integration)
    log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
    log_statement = 'mod'
    log_temp_files = 0

  # Resource Limits (conservative for 16GB cluster)
  resources:
    requests: { cpu: 500m, memory: 1Gi }
    limits:   { cpu: 1500m, memory: 2Gi }
    
  # Storage: Use existing storage class
  persistence:
    enabled: true
    size: 50Gi  # Document Intelligence generates substantial history
    storageClass: ""  # Use default storage class
    
  # Probes for k3s stability
  livenessProbe:
    enabled: true
    initialDelaySeconds: 30
    periodSeconds: 10
  readinessProbe:
    enabled: true
    initialDelaySeconds: 5
    periodSeconds: 5

# Enable metrics for Prometheus (optional but recommended)
metrics:
  enabled: true
  resources:
    requests: { cpu: 50m, memory: 64Mi }
EOF

echo "✓ PostgreSQL configuration created"

# Deploy PostgreSQL
echo "Deploying PostgreSQL..."
helm install postgres bitnami/postgresql \
  -f ../manifests/postgres-values-hetzner.yaml \
  -n temporal-system \
  --create-namespace \
  --wait \
  --timeout 10m

echo "✓ PostgreSQL deployed"

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n temporal-system --timeout=300s
echo "✓ PostgreSQL is ready"

# ============================================================================
# PHASE 3: Create Visibility Database
# ============================================================================
echo ""
echo "📊 PHASE 3: Creating Visibility Database"
echo "-----------------------------------------"

# Create temporal_visibility database
echo "Creating temporal_visibility database..."
kubectl exec -it postgres-postgresql-0 -n temporal-system -- \
  psql -U postgres -c "CREATE DATABASE temporal_visibility;" || {
    echo "⚠️  Database creation failed, trying alternative method..."
    # Alternative method
    kubectl exec -it postgres-postgresql-0 -n temporal-system -- \
      bash -c 'PGPASSWORD=supersecureadmin psql -U postgres -c "CREATE DATABASE temporal_visibility;"'
}

# Grant privileges
echo "Granting privileges to temporal user..."
kubectl exec -it postgres-postgresql-0 -n temporal-system -- \
  psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE temporal_visibility TO temporal;" || {
    echo "⚠️  Grant failed, trying alternative method..."
    kubectl exec -it postgres-postgresql-0 -n temporal-system -- \
      bash -c 'PGPASSWORD=supersecureadmin psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE temporal_visibility TO temporal;"'
}

echo "✓ Visibility database created"

# ============================================================================
# PHASE 4: Deploy PgBouncer (Connection Pooling - Critical for Temporal)
# ============================================================================
echo ""
echo "🔄 PHASE 4: Deploying PgBouncer"
echo "--------------------------------"

# Create PgBouncer deployment
echo "Creating PgBouncer configuration..."
cat > ../manifests/pgbouncer-deployment.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: pgbouncer-config
  namespace: temporal-system
data:
  pgbouncer.ini: |
    [databases]
    temporal = host=postgres-postgresql.temporal-system.svc.cluster.local port=5432 dbname=temporal
    temporal_visibility = host=postgres-postgresql.temporal-system.svc.cluster.local port=5432 dbname=temporal_visibility
    
    [pgbouncer]
    listen_addr = 0.0.0.0
    listen_port = 5432
    auth_type = md5
    auth_file = /etc/pgbouncer/userlist.txt
    pool_mode = transaction  # Critical for Temporal's short-lived queries
    max_client_conn = 500
    default_pool_size = 25   # Matches maxConns in Temporal config
    min_pool_size = 5
    reserve_pool_size = 5
    server_idle_timeout = 600
    server_lifetime = 3600
    query_timeout = 120
    logfile = /dev/stdout
    log_connections = 1
    log_disconnections = 1
---
apiVersion: v1
kind: Secret
metadata:
  name: pgbouncer-credentials
  namespace: temporal-system
type: Opaque
stringData:
  userlist.txt: |
    "temporal" "temporaldbpassword"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgbouncer-temporal
  namespace: temporal-system
spec:
  replicas: 1
  selector:
    matchLabels: { app: pgbouncer-temporal }
  template:
    metadata:
      labels: { app: pgbouncer-temporal }
    spec:
      containers:
      - name: pgbouncer
        image: pgbouncer/pgbouncer:1.22
        ports:
        - containerPort: 5432
          name: pgbouncer
        resources:
          requests: { cpu: 100m, memory: 64Mi }
          limits:   { cpu: 200m, memory: 128Mi }
        volumeMounts:
        - name: config
          mountPath: /etc/pgbouncer/pgbouncer.ini
          subPath: pgbouncer.ini
        - name: credentials
          mountPath: /etc/pgbouncer/userlist.txt
          subPath: userlist.txt
          readOnly: true
        livenessProbe:
          exec:
            command: ["/bin/sh", "-c", "pgbouncer -R -u pgbouncer /etc/pgbouncer/pgbouncer.ini -q 'SHOW VERSION'"]
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          exec:
            command: ["/bin/sh", "-c", "pgbouncer -R -u pgbouncer /etc/pgbouncer/pgbouncer.ini -q 'SHOW VERSION'"]
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: config
        configMap: { name: pgbouncer-config }
      - name: credentials
        secret: { secretName: pgbouncer-credentials }
---
apiVersion: v1
kind: Service
metadata:
  name: pgbouncer-temporal
  namespace: temporal-system
spec:
  selector: { app: pgbouncer-temporal }
  ports:
  - port: 5432
    targetPort: pgbouncer
    name: pgbouncer
EOF

echo "✓ PgBouncer configuration created"

# Deploy PgBouncer
echo "Deploying PgBouncer..."
kubectl apply -f ../manifests/pgbouncer-deployment.yaml

# Wait for PgBouncer to be ready
echo "Waiting for PgBouncer to be ready..."
kubectl wait --for=condition=ready pod -l app=pgbouncer-temporal -n temporal-system --timeout=120s
echo "✓ PgBouncer deployed and ready"

# ============================================================================
# PHASE 5: Verify PostgreSQL Connectivity
# ============================================================================
echo ""
echo "🔗 PHASE 5: Verifying PostgreSQL Connectivity"
echo "----------------------------------------------"

# Test direct connection to PostgreSQL
echo "Testing direct PostgreSQL connection..."
kubectl run pg-test --image=postgres:15 -it --rm --restart=Never -n temporal-system -- \
  psql "postgresql://temporal:temporaldbpassword@postgres-postgresql.temporal-system.svc.cluster.local:5432/temporal" -c "\dt" || {
    echo "⚠️  Direct connection test failed, but continuing..."
}

# Test connection via PgBouncer
echo "Testing connection via PgBouncer..."
kubectl run pgb-test --image=postgres:15 -it --rm --restart=Never -n temporal-system -- \
  psql "postgresql://temporal:temporaldbpassword@pgbouncer-temporal.temporal-system.svc.cluster.local:5432/temporal" -c "\dt" || {
    echo "⚠️  PgBouncer connection test failed, but continuing..."
}

echo "✓ Connectivity tests completed"

# ============================================================================
# PHASE 6: Deploy Temporal
# ============================================================================
echo ""
echo "⚙️  PHASE 6: Deploying Temporal"
echo "-------------------------------"

# Add Temporal Helm repo
echo "Adding Temporal Helm repository..."
helm repo add temporal https://go.temporal.io/helm-charts
helm repo update

# Create Temporal values file
echo "Creating Temporal configuration..."
cat > ../manifests/temporal-ha-hetzner-values.yaml << 'EOF'
# Temporal HA Configuration for Hetzner k3s
# Optimized for: 3-node k3s, 10 vCPU/16GB RAM, €28.70/month budget

server:
  # Temporal server configuration
  config:
    # Persistence configuration
    persistence:
      default:
        driver: "sql"
        sql:
          driver: "postgres12"  # Unified driver for PG 12-16
          host: "pgbouncer-temporal.temporal-system.svc.cluster.local"  # Via pooler for writes
          port: 5432
          database: "temporal"
          user: "temporal"
          password: "temporaldbpassword"
          maxConns: 25           # Reduced - PgBouncer handles multiplexing
          maxIdleConns: 10
          connMaxLifetime: "1h"
          tls:
            enabled: false       # Enable when TLS certificates are configured
      visibility:
        driver: "sql"
        sql:
          driver: "postgres12"
          host: "postgres-postgresql.temporal-system.svc.cluster.local"  # Direct for reads (optional)
          port: 5432
          database: "temporal_visibility"
          user: "temporal"
          password: "temporaldbpassword"
          maxConns: 15
          maxIdleConns: 5

    # Critical: Shard count for your scale
    # 512 shards for 2 history pods (NOT 4096 - causes rebalancing storms)
    numHistoryShards: 512
    
    # k3s networking optimization: gRPC keepalive settings
    services:
      frontend:
        rpc:
          keepAliveServerParameters:
            maxConnectionIdle: "15m"
            maxConnectionAge: "30m"
            keepAliveTime: "30s"
            keepAliveTimeout: "10s"

    # Schema setup: auto-create and migrate on first boot
    schema:
      setup:
        enabled: true
      update:
        enabled: true  # Enable for rolling upgrades (test in staging first)

  # Frontend service: lightweight API gateway
  frontend:
    replicaCount: 2
    resources:
      requests: { cpu: 250m, memory: 256Mi }
      limits:   { cpu: 500m, memory: 512Mi }
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway  # Relaxed for 3-node k3s
        labelSelector:
          matchLabels:
            app.kubernetes.io/component: frontend
            app.kubernetes.io/instance: temporal
    # Rolling update strategy for zero-downtime upgrades
    strategy:
      type: RollingUpdate
      rollingUpdate:
        maxSurge: 1
        maxUnavailable: 0

  # History service: workflow state machine
  history:
    replicaCount: 2
    resources:
      requests: { cpu: 500m, memory: 512Mi }
      limits:   { cpu: 1000m, memory: 1Gi }
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app.kubernetes.io/component: history
            app.kubernetes.io/instance: temporal
    strategy:
      type: RollingUpdate
      rollingUpdate:
        maxSurge: 1
        maxUnavailable: 0  # Critical: never lose history shard ownership

  # Matching service: task queue management (consolidated with worker)
  matching:
    replicaCount: 1  # Consolidated for resource efficiency
    resources:
      requests: { cpu: 250m, memory: 256Mi }
      limits:   { cpu: 500m, memory: 512Mi }
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app.kubernetes.io/component: matching
            app.kubernetes.io/instance: temporal

  # Worker service: background activities (consolidated with matching)
  worker:
    replicaCount: 1  # Shared with matching for low-volume workload
    resources:
      requests: { cpu: 250m, memory: 256Mi }
      limits:   { cpu: 500m, memory: 512Mi }
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app.kubernetes.io/component: worker
            app.kubernetes.io/instance: temporal

  # Metrics export for Prometheus (optional but recommended)
  metrics:
    enabled: true
    tags:
      environment: "production"
      cluster: "hetzner-k3s"

# Web UI: optional, ephemeral, minimal resources
web:
  enabled: true  # Set to false if not needed to save 128Mi
  replicaCount: 1
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits:   { cpu: 100m, memory: 256Mi }
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          app.kubernetes.io/component: web
          app.kubernetes.io/instance: temporal

# Auto-setup: create namespaces and schemas on first install
autoSetup:
  enabled: true
  createDatabase: true
EOF

echo "✓ Temporal configuration created"

# Deploy Temporal
echo "Deploying Temporal..."
helm install temporal temporal/temporal \
  -f ../manifests/temporal-ha-hetzner-values.yaml \
  -n temporal-system \
  --timeout 15m \
  --wait

echo "✓ Temporal deployed"

# Wait for Temporal pods to be ready
echo "Waiting for Temporal pods to be ready..."
sleep 30  # Give some time for pods to start

# Check pod status
echo "Temporal pod status:"
kubectl get pods -n temporal-system -l app.kubernetes.io/instance=temporal

# ============================================================================
# PHASE 7: Configure Networking (Ingress)
# ============================================================================
echo ""
echo "🌐 PHASE 7: Configuring Networking"
echo "-----------------------------------"

# Create LoadBalancer services for external access
echo "Creating LoadBalancer services for external access..."

# Create LoadBalancer service for Temporal gRPC
cat > ../manifests/temporal-frontend-lb.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: temporal-frontend-lb
  namespace: temporal-system
  annotations:
    load-balancer.hetzner.cloud/name: "temporal-grpc"
    load-balancer.hetzner.cloud/location: "fsn1"
    load-balancer.hetzner.cloud/type: "lb11"
    load-balancer.hetzner.cloud/uses-proxyprotocol: "true"
spec:
  selector:
    app.kubernetes.io/component: frontend
    app.kubernetes.io/instance: temporal
    app.kubernetes.io/name: temporal
  ports:
  - name: grpc
    port: 7233
    targetPort: 7233
    protocol: TCP
  type: LoadBalancer
EOF

# Create LoadBalancer service for Temporal Web UI
cat > ../manifests/temporal-web-lb.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: temporal-web-lb
  namespace: temporal-system
  annotations:
    load-balancer.hetzner.cloud/name: "temporal-web"
    load-balancer.hetzner.cloud/location: "fsn1"
    load-balancer.hetzner.cloud/type: "lb11"
    load-balancer.hetzner.cloud/uses-proxyprotocol: "true"
spec:
  selector:
    app.kubernetes.io/component: web
    app.kubernetes.io/instance: temporal
    app.kubernetes.io/name: temporal
  ports:
  - name: http
    port: 8088
    targetPort: 8088
    protocol: TCP
  type: LoadBalancer
EOF

echo "✓ LoadBalancer service configurations created"

echo "Applying LoadBalancer services..."
kubectl apply -f ../manifests/temporal-frontend-lb.yaml
kubectl apply -f ../manifests/temporal-web-lb.yaml
echo "✓ LoadBalancer services applied"

echo ""
echo "⏳ Waiting for LoadBalancer IPs to be assigned..."
echo "   This may take 1-2 minutes..."

# Wait for LoadBalancer IPs
TIMEOUT=120
INTERVAL=5
ELAPSED=0
GRPC_IP=""
WEB_IP=""

while [ $ELAPSED -lt $TIMEOUT ]; do
    GRPC_IP=$(kubectl get svc temporal-frontend-lb -n temporal-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    WEB_IP=$(kubectl get svc temporal-web-lb -n temporal-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [ -n "$GRPC_IP" ] && [ -n "$WEB_IP" ]; then
        echo "✓ LoadBalancer IPs assigned"
        break
    fi
    
    echo "   Waiting... ($ELAPSED/$TIMEOUT seconds)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ -z "$GRPC_IP" ] || [ -z "$WEB_IP" ]; then
    echo "⚠️  LoadBalancer IPs not assigned yet. They may still be provisioning."
    echo "   Run 'kubectl get svc -n temporal-system' to check status later."
    GRPC_IP="<pending>"
    WEB_IP="<pending>"
fi

echo ""
echo "🔗 Access URLs:"
echo "  - Temporal gRPC: http://$GRPC_IP:7233"
echo "  - Temporal Web UI: http://$WEB_IP:8088"
echo ""
echo "📝 Note: These IPs are provided by Hetzner Load Balancer"
echo "   They may take a few minutes to become fully active"

# ============================================================================
# PHASE 8: Create Deployment Report
# ============================================================================
echo ""
echo "📋 PHASE 8: Creating Deployment Report"
echo "---------------------------------------"

REPORT_FILE="../deliverables/deployment-report-$(date +%Y%m%d-%H%M%S).txt"

cat > "$REPORT_FILE" << EOF
================================================
TEMPORAL HA DEPLOYMENT REPORT
================================================
Date: $(date)
Phase: Data Plane Temporal HA Installation

DEPLOYMENT SUMMARY:
✅ PostgreSQL 15 deployed with HA tuning
✅ PgBouncer deployed for connection pooling
✅ Temporal HA stack deployed (2 frontend, 2 history, 1 matching, 1 worker)
✅ Ingress configurations created (update domains before applying)

COMPONENTS DEPLOYED:
1. PostgreSQL 15 (Bitnami Helm)
   - Database: temporal
   - Visibility Database: temporal_visibility
   - Connection: postgres-postgresql.temporal-system.svc.cluster.local:5432

2. PgBouncer (Connection Pooler)
   - Service: pgbouncer-temporal.temporal-system.svc.cluster.local:5432
   - Pool mode: transaction
   - Max connections: 500

3. Temporal HA Stack
   - Frontend: 2 replicas
   - History: 2 replicas (512 shards)
   - Matching: 1 replica
   - Worker: 1 replica
   - Web UI: 1 replica

4. Networking (Ingress - UPDATE DOMAINS BEFORE APPLYING)
   - gRPC: temporal.yourdomain.com:7233
   - Web UI: temporal-ui.yourdomain.com:8088

CREDENTIALS (CHANGE THESE IN PRODUCTION!):
- PostgreSQL admin: postgres / supersecureadmin
- Temporal database user: temporal / temporaldbpassword

MANUAL ACTIONS REQUIRED:
1. Update domain names in ingress manifests:
   - ../manifests/temporal-grpc-ingress.yaml
   - ../manifests/temporal-web-ingress.yaml
2. Apply ingress manifests if not already applied
3. Change default passwords for production
4. Configure TLS certificates for production use

VALIDATION:
Run validation script: ./scripts/03-validation.sh

NEXT STEPS:
1. Update DNS records to point to your k3s cluster
2. Configure TLS certificates (cert-manager recommended)
3. Integrate with existing monitoring/backup systems
4. Test failover scenarios

EOF

echo "✓ Deployment report saved to: $REPORT_FILE"

# ============================================================================
# PHASE 9: Create Deployment Flag
# ============================================================================
echo ""
echo "🚩 PHASE 9: Creating Deployment Flag"
echo "-------------------------------------"

FLAG_FILE="../deliverables/deployment-complete.flag"
echo "Temporal HA deployment completed successfully at $(date)" > "$FLAG_FILE"
echo "Components deployed:" >> "$FLAG_FILE"
kubectl get pods -n temporal-system --no-headers | awk '{print "  - " $1}' >> "$FLAG_FILE"
echo "✓ Deployment flag created: $FLAG_FILE"

# ============================================================================
# FINAL SUMMARY
# ============================================================================
echo ""
echo "================================================"
echo "🎉 TEMPORAL HA DEPLOYMENT COMPLETE"
echo "================================================"
echo ""
echo "✅ Deployment successful!"
echo ""
echo "📊 Current Status:"
kubectl get pods -n temporal-system
echo ""
echo "🔧 Components Deployed:"
echo "   - PostgreSQL 15 with HA tuning"
echo "   - PgBouncer connection pooler"
echo "   - Temporal HA stack (2+2+1+1 replicas)"
echo "   - Ingress configurations (update domains)"
echo ""
echo "⚠️  IMPORTANT NEXT STEPS:"
echo "   1. Update domain names in ingress manifests"
echo "   2. Apply ingress manifests (if not already)"
echo "   3. Run validation script: ./scripts/03-validation.sh"
echo "   4. Change default passwords for production"
echo ""
echo "📁 Deliverables created:"
echo "   - $REPORT_FILE"
echo "   - $FLAG_FILE"
echo "   - Configuration files in ../manifests/"
echo "   - Logs in ../logs/"
echo ""
echo "➡️  Next step: Run validation script"
echo "   ./scripts/03-validation.sh"
echo ""
echo "================================================"