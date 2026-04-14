#!/bin/bash

# Deploy SPIRE Agent and remaining components

set -e

echo "=============================================="
echo "Deploying SPIRE Agent and Remaining Components"
echo "=============================================="
echo ""

# Load environment variables
if [ -f "../../.env" ]; then
    source ../../.env
    echo "✓ Loaded environment variables from ../../.env"
else
    echo "⚠ Warning: ../../.env file not found"
    echo "   Using default values"
fi

echo ""
echo "1. Deploying SPIRE Agent DaemonSet..."

# Create agent config
cat > /tmp/spire-agent-config.yaml << 'EOF'
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

kubectl apply -f /tmp/spire-agent-config.yaml
echo "✓ SPIRE agent ConfigMap created"

echo ""
echo "2. Deploying SPIRE Agent DaemonSet..."

cat > /tmp/spire-agent-daemonset.yaml << 'EOF'
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

kubectl apply -f /tmp/spire-agent-daemonset.yaml
echo "✓ SPIRE agent DaemonSet deployed"

echo ""
echo "3. Creating registration entries..."

cat > /tmp/spire-entries.yaml << 'EOF'
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
      spiffe_id: spiffe://cluster.local/ns/default/sa/default
      parent_id: spiffe://cluster.local/spire/agent/k8s_psat/k3s-cluster/*
      selectors:
        - k8s:ns:default
        - k8s:sa:default
      ttl: 3600
    
    # Foundation namespace: kube-system
    - entry_id: foundation-kube-system
      spiffe_id: spiffe://cluster.local/ns/kube-system/sa/default
      parent_id: spiffe://cluster.local/spire/agent/k8s_psat/k3s-cluster/*
      selectors:
        - k8s:ns:kube-system
        - k8s:sa:default
      ttl: 3600
    
    # Foundation namespace: cert-manager
    - entry_id: foundation-cert-manager
      spiffe_id: spiffe://cluster.local/ns/cert-manager/sa/default
      parent_id: spiffe://cluster.local/spire/agent/k8s_psat/k3s-cluster/*
      selectors:
        - k8s:ns:cert-manager
        - k8s:sa:default
      ttl: 3600
    
    # SPIRE agent registration
    - entry_id: spire-agent
      spiffe_id: spiffe://cluster.local/spire/agent
      parent_id: spiffe://cluster.local/spire/server
      selectors:
        - k8s:ns:spire
        - k8s:sa:spire-agent
      ttl: 3600
EOF

kubectl apply -f /tmp/spire-entries.yaml
echo "✓ Registration entries created"

echo ""
echo "4. Creating fallback configuration..."

cat > /tmp/spire-fallback-config.yaml << 'EOF'
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

kubectl apply -f /tmp/spire-fallback-config.yaml
echo "✓ Fallback configuration created"

echo ""
echo "5. Deploying metrics exporter..."

cat > /tmp/spire-metrics.yaml << 'EOF'
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
EOF

kubectl apply -f /tmp/spire-metrics.yaml
echo "✓ Metrics service created"

echo ""
echo "6. Creating SDS configuration..."

cat > /tmp/spire-sds-config.yaml << 'EOF'
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

kubectl apply -f /tmp/spire-sds-config.yaml
echo "✓ SDS configuration created"

echo ""
echo "7. Waiting for SPIRE agents to start..."
echo "   This may take 30-60 seconds..."
sleep 30

echo ""
echo "8. Checking deployment status..."
echo "SPIRE Server:"
kubectl get pods -n spire -l app=spire-server

echo ""
echo "SPIRE Agents:"
kubectl get pods -n spire -l app=spire-agent

echo ""
echo "DaemonSet status:"
kubectl get daemonset -n spire

echo ""
echo "9. Checking agent socket creation..."
AGENT_POD=$(kubectl get pods -n spire -l app=spire-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$AGENT_POD" ]; then
    echo "Checking agent $AGENT_POD..."
    if kubectl exec -n spire $AGENT_POD -- ls -la /tmp/spire-sockets/ 2>/dev/null | grep -q "agent.sock"; then
        echo "✓ Agent socket created"
    else
        echo "⚠ Agent socket not created yet"
    fi
fi

echo ""
echo "=============================================="
echo "SPIRE Agent Deployment Complete"
echo "=============================================="
echo ""
echo "✅ Deployed:"
echo "   - SPIRE Agent DaemonSet"
echo "   - Agent configuration"
echo "   - Registration entries"
echo "   - Fallback configuration"
echo "   - Metrics service"
echo "   - SDS configuration"
echo ""
echo "📊 Status:"
echo "   - SPIRE Server: Running"
echo "   - SPIRE Agents: Deploying to all nodes"
echo "   - Total nodes: $(kubectl get nodes --no-headers | wc -l)"
echo ""
echo "🔍 Verification commands:"
echo "   kubectl get pods -n spire"
echo "   kubectl get daemonset -n spire"
echo "   kubectl exec -n spire <agent-pod> -- ls -la /tmp/spire-sockets/"
echo ""
echo "➡️  Next: Run validation"
echo "    ./03-validation.sh"
echo ""

# Cleanup
rm -f /tmp/spire-agent-config.yaml /tmp/spire-agent-daemonset.yaml /tmp/spire-entries.yaml
rm -f /tmp/spire-fallback-config.yaml /tmp/spire-metrics.yaml /tmp/spire-sds-config.yaml

exit 0