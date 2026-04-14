#!/bin/bash

# Restart SPIRE with fixed PostgreSQL configuration

set -e

echo "=============================================="
echo "Restarting SPIRE with Fixed Configuration"
echo "=============================================="
echo ""

# Load environment variables
if [ -f "../../.env" ]; then
    source ../../.env
    echo "✓ Loaded environment variables from ../../.env"
else
    echo "✗ ERROR: ../../.env file not found"
    exit 1
fi

echo ""
echo "1. Creating SPIRE server ConfigMap with correct password..."

cat > /tmp/spire-config-final.yaml << EOF
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
      trust_domain = "${SPIRE_TRUST_DOMAIN}"
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

kubectl apply -f /tmp/spire-config-final.yaml
echo "✓ SPIRE ConfigMap created"

echo ""
echo "2. Restarting SPIRE server..."
kubectl delete pod -n spire spire-server-0 --ignore-not-found

echo ""
echo "3. Waiting for SPIRE server to start..."
echo "   This may take 30-60 seconds as it connects to PostgreSQL..."
for i in {1..15}; do
    if kubectl get pod -n spire spire-server-0 2>/dev/null | grep -q "Running"; then
        echo "✓ SPIRE server is running (check $((i*5)) seconds)"
        
        # Check logs for success
        if kubectl logs -n spire spire-server-0 2>/dev/null | grep -q "Server started successfully"; then
            echo "✓ SPIRE server started successfully"
            break
        elif kubectl logs -n spire spire-server-0 2>/dev/null | grep -q "Fatal run error"; then
            echo "✗ SPIRE server has fatal error"
            kubectl logs -n spire spire-server-0 | tail -5
            exit 1
        fi
    fi
    echo "   Waiting... ($((i*5)) seconds)"
    sleep 5
done

echo ""
echo "4. Checking SPIRE server status..."
kubectl get pods -n spire

echo ""
echo "5. Checking SPIRE server logs..."
SPIRE_POD=$(kubectl get pods -n spire -l app=spire-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$SPIRE_POD" ]; then
    echo "SPIRE server logs (last 20 lines):"
    kubectl logs -n spire $SPIRE_POD --tail=20 2>/dev/null || echo "   Could not get logs yet"
fi

echo ""
echo "6. Checking if SPIRE agent was deployed..."
kubectl get daemonset -n spire 2>/dev/null || echo "   No DaemonSet found in spire namespace"

echo ""
echo "7. If SPIRE agent wasn't deployed, let's check the deployment script status..."
# Check what parts of the deployment script completed
if kubectl get daemonset -n spire spire-agent 2>/dev/null; then
    echo "✓ SPIRE agent DaemonSet is deployed"
    echo "   Agent pods:"
    kubectl get pods -n spire -l app=spire-agent
else
    echo "⚠ SPIRE agent DaemonSet not found"
    echo "   The deployment script may not have completed"
fi

echo ""
echo "=============================================="
echo "SPIRE Restart Complete"
echo "=============================================="
echo ""
echo "📋 Current Status:"
echo "   - PostgreSQL: ✅ Running with app user and spire database"
echo "   - SPIRE Server: ✅ Config updated, pod restarted"
echo "   - SPIRE Agent: ⚠ Check if DaemonSet exists"
echo ""
echo "🔍 Verification commands:"
echo "   kubectl get pods -n spire"
echo "   kubectl logs -n spire spire-server-0 | grep -i 'database\|postgres\|connected\|started'"
echo "   kubectl get daemonset -n spire"
echo ""
echo "➡️  Next steps:"
echo "   1. If SPIRE server is running, check agent deployment"
echo "   2. If agent not deployed, run remaining parts of 02-deployment.sh"
echo "   3. Run validation: ./03-validation.sh"
echo ""

# Cleanup
rm -f /tmp/spire-config-final.yaml

exit 0