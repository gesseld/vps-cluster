#!/bin/bash

# Test SPIRE server with explicit health check configuration

set -e

echo "=============================================="
echo "Testing SPIRE Server with Health Configuration"
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
echo "1. Creating test SPIRE configuration with health checks..."

cat > /tmp/spire-test-health.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-server-test-health
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
      
      # Health check configuration
      health_checks {
        listener_enabled = true
        bind_address = "0.0.0.0"
        bind_port = "8082"
        live_path = "/live"
        ready_path = "/ready"
        live_threshold = "30s"
        ready_threshold = "30s"
      }
    }

    plugins {
      DataStore "sql" {
        plugin_data {
          database_type = "postgres"
          connection_string = "host=${POSTGRES_HOST} port=${POSTGRES_PORT} user=${POSTGRES_USER} password=${POSTGRES_PASSWORD} dbname=${POSTGRES_DB_SPIRE} sslmode=disable"
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
            }
          }
        }
      }
    }
EOF

kubectl apply -f /tmp/spire-test-health.yaml
echo "✓ Test configuration with health checks created"

echo ""
echo "2. Updating SPIRE server to use test configuration..."
kubectl patch statefulset -n spire spire-server --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/volumes/0/configMap/name", "value": "spire-server-test-health"}]'

echo ""
echo "3. Restarting SPIRE server..."
kubectl delete pod -n spire spire-server-0 --ignore-not-found

echo ""
echo "4. Waiting for SPIRE server to start..."
echo "   Monitoring logs for health check initialization..."
sleep 30

for i in {1..12}; do
    echo "   Checking... ($((i*5)) seconds)"
    
    # Check if pod is running
    if kubectl get pod -n spire spire-server-0 2>/dev/null | grep -q "Running"; then
        echo "✓ SPIRE server pod is running"
        
        # Check logs for health check initialization
        if kubectl logs -n spire spire-server-0 2>/dev/null | grep -q "health_checks"; then
            echo "✓ Health checks configured in logs"
            break
        fi
    fi
    
    sleep 5
done

echo ""
echo "5. Checking SPIRE server logs..."
kubectl logs -n spire spire-server-0 --tail=30

echo ""
echo "6. Testing health endpoints..."
# Get pod IP
POD_IP=$(kubectl get pod -n spire spire-server-0 -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")

if [ -n "$POD_IP" ]; then
    echo "   Pod IP: $POD_IP"
    echo "   Testing /live endpoint..."
    kubectl exec -n spire spire-server-0 -- curl -s http://localhost:8082/live || echo "   /live endpoint not accessible"
    
    echo "   Testing /ready endpoint..."
    kubectl exec -n spire spire-server-0 -- curl -s http://localhost:8082/ready || echo "   /ready endpoint not accessible"
else
    echo "⚠ Could not get pod IP"
fi

echo ""
echo "7. Checking pod events..."
kubectl describe pod -n spire spire-server-0 | grep -A10 "Events:" | head -15

echo ""
echo "=============================================="
echo "Health Configuration Test Complete"
echo "=============================================="
echo ""
echo "📋 Results:"
echo "   - Configuration updated with explicit health_checks section"
echo "   - SPIRE server restarted with new config"
echo "   - Check logs for 'health_checks' initialization"
echo ""
echo "🔍 Next checks:"
echo "   1. Look for 'Health checkers initialized' in logs"
echo "   2. Check if liveness/readiness probes are passing"
echo "   3. Monitor if server stays running > 2 minutes"
echo ""
echo "If health endpoints work, the server should remain stable."
echo ""

# Cleanup
rm -f /tmp/spire-test-health.yaml

exit 0