#!/bin/bash

# Fix SPIRE server configuration - simple version

set -e

echo "=============================================="
echo "Fixing SPIRE Server Configuration"
echo "=============================================="
echo ""

# Load environment variables
if [ -f "../../.env" ]; then
    source ../../.env
    echo "✓ Loaded environment variables from ../../.env"
    
    # Set defaults if not set
    POSTGRES_HOST=${POSTGRES_HOST:-postgresql-primary.data-plane.svc.cluster.local}
    POSTGRES_PORT=${POSTGRES_PORT:-5432}
    POSTGRES_USER=${POSTGRES_USER:-app}
    POSTGRES_DB_SPIRE=${POSTGRES_DB_SPIRE:-spire}
    SPIRE_TRUST_DOMAIN=${SPIRE_TRUST_DOMAIN:-cluster.local}
    
    echo "   Using PostgreSQL: ${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB_SPIRE}"
    echo "   Trust domain: ${SPIRE_TRUST_DOMAIN}"
else
    echo "⚠ Warning: ../../.env file not found"
    echo "   Using default values"
    POSTGRES_HOST="postgresql-primary.data-plane.svc.cluster.local"
    POSTGRES_PORT="5432"
    POSTGRES_USER="app"
    POSTGRES_PASSWORD=""  # Will fail if not in env
    POSTGRES_DB_SPIRE="spire"
    SPIRE_TRUST_DOMAIN="cluster.local"
fi

echo ""
echo "1. Deleting existing SPIRE server ConfigMap..."
kubectl delete cm -n spire spire-server-config --ignore-not-found

echo ""
echo "2. Creating SPIRE server ConfigMap with actual values..."

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

kubectl apply -f /tmp/spire-server-config-fixed.yaml
echo "✓ Created SPIRE server ConfigMap"

echo ""
echo "3. Restarting SPIRE server..."
kubectl delete pod -n spire spire-server-0 --ignore-not-found

echo ""
echo "4. Waiting for SPIRE server to restart..."
echo "   This may take 30-60 seconds..."
for i in {1..12}; do
    if kubectl get pod -n spire spire-server-0 2>/dev/null | grep -q "Running"; then
        echo "✓ SPIRE server is running"
        break
    fi
    echo "   Waiting... ($((i*5)) seconds)"
    sleep 5
done

echo ""
echo "5. Checking SPIRE server status..."
kubectl get pods -n spire

echo ""
echo "6. Checking SPIRE server logs..."
SPIRE_POD=$(kubectl get pods -n spire -l app=spire-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$SPIRE_POD" ]; then
    echo "SPIRE server logs (last 10 lines):"
    kubectl logs -n spire $SPIRE_POD --tail=10 2>/dev/null || echo "   Could not get logs yet"
fi

echo ""
echo "=============================================="
echo "SPIRE Configuration Fix Applied"
echo "=============================================="
echo ""
echo "📋 Status:"
echo "   - ConfigMap updated with actual PostgreSQL connection"
echo "   - SPIRE server pod restarted"
echo ""
echo "🔍 Next steps:"
echo "   1. Check if SPIRE server is running:"
echo "      kubectl get pods -n spire"
echo "   2. Check logs for database connection:"
echo "      kubectl logs -n spire spire-server-0 | grep -i 'postgres\|database\|connected\|error'"
echo "   3. If running, continue deployment:"
echo "      Check if SPIRE agent was deployed: kubectl get daemonset -n spire"
echo "   4. Run validation:"
echo "      ./03-validation.sh"
echo ""

# Cleanup
rm -f /tmp/spire-server-config-fixed.yaml

exit 0