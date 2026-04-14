#!/bin/bash

# Phase SF-1: Cert-Manager + SPIRE PKI Bootstrap - Deployment Script
# This script deploys Cert-Manager and SPIRE with all required components

set -e

echo "=============================================="
echo "Phase SF-1: Cert-Manager + SPIRE PKI Bootstrap"
echo "Deployment Script"
echo "=============================================="
echo ""
echo "Starting deployment at: $(date)"
echo ""

# Load environment variables
if [ -f "../.env" ]; then
    source ../.env
    echo "✓ Loaded environment variables from ../.env"
else
    echo "⚠ Warning: ../.env file not found"
    echo "   Using default values"
fi

# Create shared directory for manifests
mkdir -p shared/pki
mkdir -p control-plane/spire

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local label_selector=$2
    local timeout=${3:-300}
    local interval=5
    local elapsed=0
    
    echo "Waiting for pods with label '$label_selector' in namespace '$namespace'..."
    
    while [ $elapsed -lt $timeout ]; do
        local ready_pods=$(kubectl get pods -n $namespace -l $label_selector --no-headers 2>/dev/null | grep -c "Running" || true)
        local total_pods=$(kubectl get pods -n $namespace -l $label_selector --no-headers 2>/dev/null | wc -l || true)
        
        if [ $total_pods -gt 0 ] && [ $ready_pods -eq $total_pods ]; then
            echo "✓ All $total_pods pod(s) are ready"
            return 0
        fi
        
        echo "  $ready_pods/$total_pods pods ready... waiting"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo "✗ Timeout waiting for pods to be ready"
    return 1
}

# Step 1: Create namespaces
echo ""
echo "1. Creating namespaces..."
for ns in cert-manager spire foundation; do
    if ! kubectl get ns $ns > /dev/null 2>&1; then
        kubectl create namespace $ns
        echo "✓ Created namespace: $ns"
    else
        echo "⚠ Namespace '$ns' already exists"
    fi
done

# Create NetworkPolicy for spire namespace to allow egress to data-plane
echo ""
echo "1b. Creating NetworkPolicy for spire namespace..."
cat > shared/spire-network-policy.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-spire-egress
  namespace: spire
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: data-plane
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: UDP
      port: 53
EOF

kubectl apply -f shared/spire-network-policy.yaml
echo "✓ Created spire egress NetworkPolicy (allows PostgreSQL + DNS)"

# Step 2: Deploy Cert-Manager
echo ""
echo "2. Deploying Cert-Manager v1.13+..."

# Add jetstack Helm repo if not already added
if ! helm repo list | grep -q "jetstack"; then
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    echo "✓ Added jetstack Helm repository"
fi

# Install cert-manager
if ! helm list -n cert-manager | grep -q "cert-manager"; then
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version v1.13.0 \
        --set installCRDs=true \
        --set extraArgs={--enable-certificate-owner-ref=true} \
        --wait
    
    echo "✓ Installed cert-manager"
    
    # Wait for cert-manager pods
    wait_for_pods "cert-manager" "app.kubernetes.io/instance=cert-manager" 180
else
    echo "⚠ cert-manager is already installed"
fi

# Step 3: Create self-signed ClusterIssuer
echo ""
echo "3. Creating self-signed ClusterIssuer..."

cat > shared/pki/cert-manager.yaml << 'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: spire-ca
  namespace: spire
spec:
  secretName: spire-ca
  duration: 8760h # 1 year
  renewBefore: 720h # 30 days
  commonName: spire-ca
  isCA: true
  usages:
    - digital signature
    - key encipherment
    - cert sign
    - crl sign
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
EOF

kubectl apply -f shared/pki/cert-manager.yaml
echo "✓ Created self-signed ClusterIssuer and CA certificate"
echo "  Manifest saved to: shared/pki/cert-manager.yaml"

# Step 4: Deploy SPIRE Server
echo ""
echo "4. Deploying SPIRE Server with PostgreSQL backend..."

# Add spiffe Helm repo if not already added
if ! helm repo list | grep -q "spiffe"; then
    helm repo add spiffe https://spiffe.github.io/helm-charts/
    helm repo update
    echo "✓ Added spiffe Helm repository"
fi

# Create SPIRE server configuration
cat > control-plane/spire/server-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-server-config
  namespace: spire
data:
  server.conf: |
    server {
      bind_address = "0.0.0.0"
      bind_port = "8081"
      socket_path = "/tmp/spire-server/private/api.sock"
      trust_domain = "cluster.local"
      data_dir = "/run/spire/data"
      log_level = "DEBUG"
      ca_subject = {
        country = ["US"],
        organization = ["SPIRE"],
        common_name = "",
      }
    }

    plugins {
      DataStore "sql" {
        plugin_data {
          database_type = "postgres"
          connection_string = "host=postgresql-primary.data-plane.svc.cluster.local port=5432 user=app password=${POSTGRES_PASSWORD} dbname=spire sslmode=disable"
        }
      }

      KeyManager "disk" {
        plugin_data {
          keys_path = "/run/spire/data/keys.json"
        }
      }

      NodeAttestor "k8s_psat" {
        plugin_data {
          clusters = {
            "k3s-cluster" = {
              service_account_allow_list = ["spire:spire-agent"]
              audience = ["k3s"]
            }
          }
        }
      }
    }
EOF

# Get PostgreSQL password from secret
POSTGRES_PASSWORD=$(kubectl get secret postgres-app-user -n data-plane -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
if [ -z "$POSTGRES_PASSWORD" ]; then
    POSTGRES_PASSWORD="changeme123"
fi

# Create PostgreSQL secret for SPIRE
kubectl create secret generic postgres-app-secret \
    --namespace spire \
    --from-literal=password="$POSTGRES_PASSWORD" \
    --dry-run=client -o yaml > control-plane/spire/postgres-secret.yaml
kubectl apply -f control-plane/spire/postgres-secret.yaml
echo "✓ Created PostgreSQL secret for SPIRE"

# Create SPIRE database credentials secret
kubectl create secret generic spire-database-creds \
    --namespace spire \
    --from-literal=SPIRE_DB_PASSWORD="$POSTGRES_PASSWORD" \
    --dry-run=client -o yaml > control-plane/spire/spire-creds.yaml
kubectl apply -f control-plane/spire/spire-creds.yaml
echo "✓ Created SPIRE database credentials secret"

# Create SPIRE server StatefulSet manifest
cat > control-plane/spire/server.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: spire-server
  namespace: spire
  labels:
    app: spire-server
spec:
  replicas: 1
  serviceName: spire-server
  selector:
    matchLabels:
      app: spire-server
  template:
    metadata:
      labels:
        app: spire-server
    spec:
      serviceAccountName: spire-server
      containers:
      - name: spire-server
        image: ghcr.io/spiffe/spire-server:1.8.0
        args: ["-config", "/run/spire/config/server.conf"]
        ports:
        - containerPort: 8081
          name: grpc
        - containerPort: 8082
          name: http
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-app-secret
              key: password
        volumeMounts:
        - name: spire-config
          mountPath: /run/spire/config
          readOnly: true
        - name: spire-data
          mountPath: /run/spire/data
        - name: spire-sockets
          mountPath: /tmp/spire-server/private
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /live
            port: http
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 30
          periodSeconds: 30
      volumes:
      - name: spire-config
        configMap:
          name: spire-server-config
      - name: spire-sockets
        emptyDir: {}
  volumeClaimTemplates:
  - metadata:
      name: spire-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
EOF

# Create SPIRE server service
cat > control-plane/spire/server-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: spire-server
  namespace: spire
spec:
  selector:
    app: spire-server
  ports:
  - name: grpc
    port: 8081
    targetPort: 8081
  - name: http
    port: 8082
    targetPort: 8082
  - name: metrics
    port: 9090
    targetPort: 9090
EOF

# Create RBAC for SPIRE
cat > control-plane/spire/roles.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spire-server
  namespace: spire
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spire-agent
  namespace: spire
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: spire-server-token-review
rules:
- apiGroups: ["authentication.k8s.io"]
  resources: ["tokenreviews"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: spire-server-token-review
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: spire-server-token-review
subjects:
- kind: ServiceAccount
  name: spire-server
  namespace: spire
EOF

# Apply SPIRE server configuration
kubectl apply -f control-plane/spire/server-config.yaml
kubectl apply -f control-plane/spire/roles.yaml
kubectl apply -f control-plane/spire/server.yaml
kubectl apply -f control-plane/spire/server-service.yaml

echo "✓ Deployed SPIRE server configuration"
echo "  Manifests saved to control-plane/spire/"

# Wait for SPIRE server to be ready
wait_for_pods "spire" "app=spire-server" 180

# Step 5: Deploy SPIRE Agent
echo ""
echo "5. Deploying SPIRE Agent DaemonSet..."

cat > control-plane/spire/agent-daemonset.yaml << 'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: spire-agent
  namespace: spire
  labels:
    app: spire-agent
spec:
  selector:
    matchLabels:
      app: spire-agent
  template:
    metadata:
      labels:
        app: spire-agent
    spec:
      serviceAccountName: spire-agent
      hostPID: true
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: spire-agent
        image: ghcr.io/spiffe/spire-agent:1.8.0
        args: ["-config", "/run/spire/config/agent.conf"]
        volumeMounts:
        - name: spire-config
          mountPath: /run/spire/config
          readOnly: true
        - name: spire-sockets
          mountPath: /tmp/spire-sockets
        - name: spire-bundle
          mountPath: /run/spire/bundle
        - name: spire-agent-socket
          mountPath: /run/spire/sockets
        securityContext:
          privileged: true
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          exec:
            command:
            - /opt/spire/bin/spire-agent
            - healthcheck
            - -socketPath
            - /run/spire/sockets/agent.sock
          initialDelaySeconds: 30
          periodSeconds: 30
      volumes:
      - name: spire-config
        configMap:
          name: spire-agent-config
      - name: spire-sockets
        hostPath:
          path: /tmp/spire-sockets
          type: DirectoryOrCreate
      - name: spire-bundle
        hostPath:
          path: /run/spire/bundle
          type: DirectoryOrCreate
      - name: spire-agent-socket
        hostPath:
          path: /run/spire/sockets
          type: DirectoryOrCreate
EOF

# Create agent config
cat > control-plane/spire/agent-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-agent-config
  namespace: spire
data:
  agent.conf: |
    agent {
      data_dir = "/run/spire"
      log_level = "DEBUG"
      server_address = "spire-server.spire.svc"
      server_port = 8081
      socket_path = "/run/spire/sockets/agent.sock"
      trust_bundle_path = "/run/spire/bundle/bundle.crt"
      trust_domain = "cluster.local"
    }

    plugins {
      NodeAttestor "k8s_psat" {
        plugin_data {
          cluster = "k3s-cluster"
          service_account_allow_list = ["spire:spire-agent"]
        }
      }

      WorkloadAttestor "k8s" {
        plugin_data {
          skip_kubelet_verification = true
        }
      }

      WorkloadAttestor "unix" {
        plugin_data {}
      }

      KeyManager "disk" {
        plugin_data {
          directory = "/run/spire/data"
        }
      }
    }
EOF

kubectl apply -f control-plane/spire/agent-config.yaml
kubectl apply -f control-plane/spire/agent-daemonset.yaml

echo "✓ Deployed SPIRE agent"
echo "  Manifest saved to: control-plane/spire/agent-daemonset.yaml"

# Wait for agents to be ready
echo "Waiting for SPIRE agents to be scheduled on all nodes..."
sleep 30
AGENT_PODS=$(kubectl get pods -n spire -l app=spire-agent --no-headers | wc -l)
NODES=$(kubectl get nodes --no-headers | wc -l)
echo "  SPIRE agents running: $AGENT_PODS/$NODES nodes"

# Step 6: Create registration entries
echo ""
echo "6. Creating registration entries for foundation namespaces..."

cat > control-plane/spire/entries.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-registration-entries
  namespace: spire
  annotations:
    spire-registration: "true"
data:
  entries: |
    # Foundation namespace: default
    - entry_id: foundation-default
      spiffe_id: spiffe://example.org/ns/default/sa/default
      parent_id: spiffe://example.org/spire/agent/k8s_psat/k3s-cluster/*
      selectors:
        - k8s:ns:default
        - k8s:sa:default
      ttl: 3600
    
    # Foundation namespace: kube-system
    - entry_id: foundation-kube-system
      spiffe_id: spiffe://example.org/ns/kube-system/sa/default
      parent_id: spiffe://example.org/spire/agent/k8s_psat/k3s-cluster/*
      selectors:
        - k8s:ns:kube-system
        - k8s:sa:default
      ttl: 3600
    
    # Foundation namespace: cert-manager
    - entry_id: foundation-cert-manager
      spiffe_id: spiffe://example.org/ns/cert-manager/sa/default
      parent_id: spiffe://example.org/spire/agent/k8s_psat/k3s-cluster/*
      selectors:
        - k8s:ns:cert-manager
        - k8s:sa:default
      ttl: 3600
    
    # SPIRE agent registration
    - entry_id: spire-agent
      spiffe_id: spiffe://example.org/spire/agent
      parent_id: spiffe://example.org/spire/server
      selectors:
        - k8s:ns:spire
        - k8s:sa:spire-agent
      ttl: 3600
EOF

kubectl apply -f control-plane/spire/entries.yaml
echo "✓ Created registration entries"
echo "  Manifest saved to: control-plane/spire/entries.yaml"

# Step 7: Create fallback configuration
echo ""
echo "7. Creating fallback configuration for cert-manager TLS..."

cat > control-plane/spire/fallback-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-fallback-config
  namespace: spire
data:
  enabled: "false"
  fallback-issuer: "selfsigned-issuer"
  annotation-key: "spire-fallback/enabled"
EOF

kubectl apply -f control-plane/spire/fallback-config.yaml
echo "✓ Created fallback configuration"
echo "  Manifest saved to: control-plane/spire/fallback-config.yaml"

# Step 8: Deploy metrics exporter
echo ""
echo "8. Deploying metrics exporter..."

cat > control-plane/spire/metrics-exporter.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: spire-server-metrics
  namespace: spire
  labels:
    app: spire-server
spec:
  selector:
    app: spire-server
  ports:
  - name: metrics
    port: 9090
    targetPort: 9090
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spire-server
  namespace: spire
  labels:
    release: prometheus-stack
spec:
  selector:
    matchLabels:
      app: spire-server
  endpoints:
  - port: metrics
    interval: 30s
    scrapeTimeout: 10s
    path: /metrics
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-metrics-alerts
  namespace: monitoring
data:
  spire-alerts.yaml: |
    groups:
    - name: spire
      rules:
      - alert: SPIRESVIDIssuanceLatencyHigh
        expr: histogram_quantile(0.95, rate(spire_server_svid_issuance_latency_seconds_bucket[5m])) > 5
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "SPIRE SVID issuance latency is high"
          description: "SPIRE SVID issuance latency p95 is {{ $value }}s (threshold: 5s)"
      - alert: SPIREServerDown
        expr: up{job="spire-server"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "SPIRE server is down"
          description: "SPIRE server has been down for more than 1 minute"
      - alert: SPIREAgentDown
        expr: count(up{job="spire-agent"}) < count(kube_node_info)
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "SPIRE agents missing on nodes"
          description: "{{ $value }} SPIRE agents are missing (expected: {{ count(kube_node_info) }})"
EOF

kubectl apply -f control-plane/spire/metrics-exporter.yaml
echo "✓ Deployed metrics exporter and alerts"
echo "  Manifest saved to: control-plane/spire/metrics-exporter.yaml"

# Step 9: Create SDS (Secret Discovery Service) configuration
echo ""
echo "9. Configuring SDS for Envoy/NGINX mTLS integration..."

cat > shared/pki/sds-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-sds-config
  namespace: spire
data:
  envoy-sds.yaml: |
    resources:
    - "@type": type.googleapis.com/envoy.config.core.v3.ConfigSource
      resource_api_version: V3
      api_config_source:
        api_type: GRPC
        transport_api_version: V3
        grpc_services:
        - envoy_grpc:
            cluster_name: spire_agent
    static_resources:
      clusters:
      - name: spire_agent
        type: STATIC
        connect_timeout: 1s
        lb_policy: ROUND_ROBIN
        load_assignment:
          cluster_name: spire_agent
          endpoints:
          - lb_endpoints:
            - endpoint:
                address:
                  pipe:
                    path: /tmp/spire-sockets/agent.sock
        typed_extension_protocol_options:
          envoy.extensions.upstreams.http.v3.HttpProtocolOptions:
            "@type": type.googleapis.com/envoy.extensions.upstreams.http.v3.HttpProtocolOptions
            explicit_http_config:
              http2_protocol_options: {}
  nginx-sds.conf: |
    # NGINX SDS configuration for SPIRE
    # This requires NGINX Plus or NGINX with appropriate modules
    
    sds {
        # SPIRE agent socket path
        sdspath unix:/tmp/spire-sockets/agent.sock;
        
        # Certificate and key updates
        cert auto;
        key auto;
        
        # Trust bundle updates  
        trusted_certificate auto;
        
        # Update interval (seconds)
        timeout 30s;
    }
EOF

kubectl apply -f shared/pki/sds-config.yaml
echo "✓ Created SDS configuration for Envoy/NGINX"
echo "  Manifest saved to: shared/pki/sds-config.yaml"

# Final summary
echo ""
echo "=============================================="
echo "DEPLOYMENT COMPLETE"
echo "=============================================="
echo ""
echo "Components deployed:"
echo "  1. ✓ Cert-Manager v1.13+ with self-signed ClusterIssuer"
echo "  2. ✓ SPIRE Server (StatefulSet with PostgreSQL backend)"
echo "  3. ✓ SPIRE Agent (DaemonSet on all nodes)"
echo "  4. ✓ RBAC for TokenReview"
echo "  5. ✓ Registration entries for foundation namespaces"
echo "  6. ✓ Fallback configuration (cert-manager toggle)"
echo "  7. ✓ Metrics exporter with Prometheus alerts"
echo "  8. ✓ SDS configuration for Envoy/NGINX mTLS"
echo ""
echo "Manifests created in:"
echo "  - shared/pki/"
echo "  - control-plane/spire/"
echo ""
echo "Next steps:"
echo "  1. Run validation script: ./03-validation.sh"
echo "  2. Verify PostgreSQL connection for SPIRE (if not already configured)"
echo "  3. Test SVID issuance with a sample workload"
echo ""
echo "Deployment completed at: $(date)"
echo ""

exit 0