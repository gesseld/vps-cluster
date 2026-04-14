#!/bin/bash

# Fix SPIRE server configuration with expanded environment variables

set -e

echo "=============================================="
echo "Fixing SPIRE Server Configuration"
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
echo "1. Deleting existing SPIRE server ConfigMap..."
kubectl delete cm -n spire spire-server-config --ignore-not-found

echo ""
echo "2. Creating SPIRE server ConfigMap with expanded environment variables..."

# Create the ConfigMap with actual values
cat > /tmp/spire-server-config-fixed.yaml << EOF
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
      trust_domain = "${SPIRE_TRUST_DOMAIN:-cluster.local}"
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
          connection_string = "host=${POSTGRES_HOST:-postgresql-primary.data-plane.svc.cluster.local} port=${POSTGRES_PORT:-5432} user=${POSTGRES_USER:-app} password=${POSTGRES_PASSWORD} dbname=${POSTGRES_DB_SPIRE:-spire} sslmode=disable"
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

# Expand environment variables in the file
envsubst < /tmp/spire-server-config-fixed.yaml > /tmp/spire-server-config-expanded.yaml

kubectl apply -f /tmp/spire-server-config-expanded.yaml
echo "✓ Created SPIRE server ConfigMap with expanded environment variables"

echo ""
echo "3. Restarting SPIRE server..."
kubectl delete pod -n spire spire-server-0 --ignore-not-found

echo ""
echo "4. Waiting for SPIRE server to restart..."
sleep 10
if kubectl wait --for=condition=Ready pod -n spire -l app=spire-server --timeout=120s 2>/dev/null; then
    echo "✓ SPIRE server is ready"
else
    echo "⚠ SPIRE server taking longer to start"
    echo "   Checking status..."
    kubectl get pods -n spire -l app=spire-server
    echo "   Checking logs..."
    kubectl logs -n spire -l app=spire-server --tail=20
fi

echo ""
echo "5. Checking SPIRE server logs..."
SPIRE_POD=$(kubectl get pods -n spire -l app=spire-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$SPIRE_POD" ]; then
    echo "SPIRE server logs:"
    kubectl logs -n spire $SPIRE_POD --tail=10
fi

echo ""
echo "6. Continuing with SPIRE agent deployment..."

# Check if agent config also needs fixing
echo "Checking SPIRE agent configuration..."
AGENT_CM=$(kubectl get cm -n spire spire-agent-config 2>/dev/null || true)
if [ -n "$AGENT_CM" ]; then
    echo "⚠ SPIRE agent ConfigMap exists, checking if it needs update..."
    # The agent config should be fine as it doesn't have PostgreSQL connection
fi

echo ""
echo "=============================================="
echo "SPIRE Configuration Fix Complete"
echo "=============================================="
echo ""
echo "✅ Fixed:"
echo "   - SPIRE server ConfigMap with expanded environment variables"
echo "   - PostgreSQL connection string now has actual values"
echo ""
echo "🔍 Verification:"
echo "   kubectl get pods -n spire"
echo "   kubectl logs -n spire spire-server-0 | grep -i 'database\|postgres\|connected'"
echo ""
echo "➡️  If SPIRE server is running, continue with validation:"
echo "    ./03-validation.sh"
echo ""

# Cleanup
rm -f /tmp/spire-server-config-fixed.yaml /tmp/spire-server-config-expanded.yaml

exit 0