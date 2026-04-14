# SPIRE Server Stability Troubleshooting Guide

## Issue Summary
SPIRE server starts successfully but stops after ~90 seconds with "Server stopped gracefully" message.

## Symptoms
- Server initializes, connects to PostgreSQL, loads plugins
- Starts API endpoints (8081 TCP, Unix socket)
- After ~90 seconds, stops gracefully
- Liveness/readiness probes fail → pod restarts
- Agents cannot fetch trust bundle → CrashLoopBackOff

## Debug Commands

### 1. Check Current Status
```bash
kubectl get pods -n spire
kubectl describe pod -n spire spire-server-0
kubectl logs -n spire spire-server-0 --previous
```

### 2. Examine Configuration
```bash
# Check ConfigMap
kubectl get cm -n spire spire-server-config -o yaml

# Check environment
kubectl exec -n spire spire-server-0 -- env
```

### 3. Test Connectivity
```bash
# Test PostgreSQL from SPIRE server
kubectl exec -n spire spire-server-0 -- \
  pg_isready -h postgresql-primary.data-plane.svc.cluster.local -U app -d spire

# Test SPIRE server API (when running)
kubectl exec -n spire spire-server-0 -- \
  curl -s http://localhost:8082/ready
```

## Possible Root Causes

### 1. Missing Upstream Authority
SPIRE server might require upstream CA configuration when running in production mode.

**Check**: Look for `upstream_authority` or `upstream_bundle` in configuration.

**Fix**: Add upstream authority or configure as root CA.

### 2. Health Check Configuration
Default health checks might be failing.

**Check**: Look for health check failures in logs.

**Fix**: Adjust health check configuration or fix underlying issue.

### 3. Single Server Leadership
Single server might be losing "leadership" in a cluster configuration.

**Check**: Look for leadership election messages.

**Fix**: Configure as single server or add more servers.

### 4. Plugin Issues
Required plugins might not be loading correctly.

**Check**: Verify all required plugins in logs:
- DataStore (sql)
- KeyManager (disk) 
- NodeAttestor (k8s_psat)

### 5. Database Issues
PostgreSQL connection might be dropping.

**Check**: Look for database disconnection messages.

**Fix**: Adjust PostgreSQL connection parameters or add connection pooling.

## Configuration Fixes to Try

### Option 1: Add Upstream Authority (If Missing)
```yaml
upstream_authority "disk" {
  plugin_data {
    key_file_path = "/run/spire/keys/upstream.key"
    cert_file_path = "/run/spire/certs/upstream.crt"
  }
}
```

### Option 2: Adjust Health Checks
```yaml
health_checks {
  listener_enabled = true
  bind_address = "0.0.0.0"
  bind_port = "8082"
  live_path = "/live"
  ready_path = "/ready"
  live_threshold = "30s"
  ready_threshold = "30s"
}
```

### Option 3: Single Server Mode
```yaml
# Ensure single server mode
# Some configurations might require explicit leader election config
```

### Option 4: Simplify for Testing
Temporarily use SQLite instead of PostgreSQL:
```yaml
DataStore "sql" {
  plugin_data {
    database_type = "sqlite3"
    connection_string = "/run/spire/data/datastore.sqlite3"
  }
}
```

## Step-by-Step Debugging

### Step 1: Increase Logging
```bash
# Update ConfigMap with DEBUG logging
kubectl edit cm -n spire spire-server-config
# Change: log_level = "DEBUG"
```

### Step 2: Check Previous Logs
```bash
kubectl logs -n spire spire-server-0 --previous | grep -A5 -B5 "error\|Error\|ERROR\|fatal\|Fatal\|FATAL"
```

### Step 3: Test Minimal Configuration
Create minimal SPIRE config to isolate issue:
```yaml
server {
  bind_address = "0.0.0.0"
  bind_port = "8081"
  trust_domain = "cluster.local"
  data_dir = "/run/spire/data"
  log_level = "DEBUG"
}

plugins {
  DataStore "sql" {
    plugin_data {
      database_type = "sqlite3"
      connection_string = "/run/spire/data/datastore.sqlite3"
    }
  }
  
  KeyManager "disk" {
    plugin_data {
      keys_path = "/run/spire/data/keys.json"
    }
  }
}
```

### Step 4: Check Resource Limits
```bash
kubectl describe pod -n spire spire-server-0 | grep -A5 "Limits\|Requests"
# Ensure sufficient memory (SPIRE needs ~256-512MB)
```

## Quick Fix Script

```bash
#!/bin/bash
# Quick SPIRE server debug script

echo "1. Stopping SPIRE server..."
kubectl delete pod -n spire spire-server-0 --ignore-not-found

echo "2. Creating test configuration..."
cat > /tmp/spire-test-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: spire-server-test
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
          database_type = "sqlite3"
          connection_string = "/run/spire/data/datastore.sqlite3"
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

kubectl apply -f /tmp/spire-test-config.yaml

echo "3. Updating StatefulSet to use test config..."
kubectl patch statefulset -n spire spire-server --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/volumes/1/configMap/name", "value": "spire-server-test"}]'

echo "4. Waiting for server to start..."
sleep 30
kubectl logs -n spire spire-server-0 --tail=50
```

## Expected Outcome

If SPIRE server runs stably with SQLite but not PostgreSQL:
- Issue is with PostgreSQL connection/configuration

If SPIRE server still stops with SQLite:
- Issue is with SPIRE configuration itself

If SPIRE server runs stably with test config:
- Gradually add back components to find culprit

## Next Steps After Fix

1. **Verify server stability** (runs >5 minutes)
2. **Check agents can connect** and fetch bundle
3. **Test SVID issuance** with sample workload
4. **Re-enable PostgreSQL** (if using SQLite for testing)
5. **Run full validation**: `./03-validation.sh`

## References
- [SPIRE Configuration Reference](https://spiffe.io/docs/latest/deploying/spire_server/)
- [SPIRE Troubleshooting](https://spiffe.io/docs/latest/troubleshooting/)
- [SPIRE with PostgreSQL](https://spiffe.io/docs/latest/deploying/configure_datastore/)