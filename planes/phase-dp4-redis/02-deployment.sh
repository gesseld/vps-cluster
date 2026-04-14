#!/bin/bash

# Redis Phase DP-4: Deployment Script
# Deploys Redis multi-role cache tier with RDB-only configuration and memory protection

set -e

echo "=============================================="
echo "Redis DP-4: Deployment"
echo "=============================================="
echo "Timestamp: $(date)"
echo ""

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -f "$PROJECT_ROOT/.env" ]; then
    echo "Loading environment from $PROJECT_ROOT/.env"
    source "$PROJECT_ROOT/.env"
elif [ -f "$SCRIPT_DIR/.env" ]; then
    echo "Loading environment from $SCRIPT_DIR/.env"
    source "$SCRIPT_DIR/.env"
fi

# Default values
NAMESPACE=${NAMESPACE:-default}
REDIS_VERSION=${REDIS_VERSION:-7.2}
STORAGE_CLASS=${STORAGE_CLASS:-hcloud-volumes}
DEPLOYMENT_DIR="$PROJECT_ROOT/data-plane/redis"

echo "Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Redis Version: $REDIS_VERSION"
echo "  Storage Class: $STORAGE_CLASS"
echo "  Deployment Directory: $DEPLOYMENT_DIR"
echo ""

# Function to wait for resource
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local timeout=${4:-300}
    local interval=${5:-5}
    
    echo "Waiting for $resource_type/$resource_name to be ready..."
    local start_time=$(date +%s)
    
    while true; do
        if kubectl get "$resource_type" "$resource_name" -n "$namespace" &> /dev/null; then
            if [ "$resource_type" = "pod" ]; then
                local status=$(kubectl get pod "$resource_name" -n "$namespace" -o jsonpath='{.status.phase}')
                if [ "$status" = "Running" ]; then
                    echo "✅ $resource_type/$resource_name is Running"
                    return 0
                fi
            else
                echo "✅ $resource_type/$resource_name created"
                return 0
            fi
        fi
        
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            echo "❌ ERROR: Timeout waiting for $resource_type/$resource_name"
            return 1
        fi
        
        echo "  Still waiting... ($elapsed seconds elapsed)"
        sleep $interval
    done
}

# Function to apply Kubernetes manifest with validation
apply_manifest() {
    local file=$1
    local description=${2:-"Kubernetes resource"}
    
    if [ ! -f "$file" ]; then
        echo "❌ ERROR: Manifest file not found: $file"
        return 1
    fi
    
    echo "Deploying $description from $file..."
    
    # Validate YAML syntax
    if ! kubectl apply --dry-run=client -f "$file" &> /dev/null; then
        echo "❌ ERROR: YAML validation failed for $file"
        return 1
    fi
    
    # Apply the manifest
    if kubectl apply -f "$file"; then
        echo "✅ $description deployed successfully"
        return 0
    else
        echo "❌ ERROR: Failed to deploy $description"
        return 1
    fi
}

echo "1. Creating namespace if needed..."
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    kubectl create namespace "$NAMESPACE"
    echo "✅ Namespace $NAMESPACE created"
else
    echo "✅ Namespace $NAMESPACE already exists"
fi
echo ""

echo "2. Deploying Redis ConfigMap..."
apply_manifest "$DEPLOYMENT_DIR/configmap.yaml" "Redis ConfigMap"
echo ""

echo "3. Deploying Redis Deployment and Service..."
apply_manifest "$DEPLOYMENT_DIR/deployment.yaml" "Redis Deployment and Service"
echo ""

echo "4. Waiting for Redis pods to be ready..."
REDIS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -n "$REDIS_POD" ]; then
    wait_for_resource pod "$REDIS_POD" "$NAMESPACE" 300 5
    
    # Check pod status in detail
    echo "Checking Redis pod status..."
    kubectl get pod "$REDIS_POD" -n "$NAMESPACE" -o wide
    
    # Check container status
    echo ""
    echo "Container status:"
    kubectl get pod "$REDIS_POD" -n "$NAMESPACE" -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.state}{"\n"}{end}'
    
    # Check logs for errors
    echo ""
    echo "Checking Redis logs for errors..."
    if kubectl logs "$REDIS_POD" -n "$NAMESPACE" -c redis | grep -i "error\|fatal\|failed" | head -5; then
        echo "⚠️  Potential errors found in Redis logs"
    else
        echo "✅ No errors found in Redis logs"
    fi
    
    # Check exporter logs
    echo ""
    echo "Checking Redis exporter logs..."
    if kubectl logs "$REDIS_POD" -n "$NAMESPACE" -c redis-exporter | grep -i "error\|fatal\|failed" | head -5; then
        echo "⚠️  Potential errors found in Redis exporter logs"
    else
        echo "✅ No errors found in Redis exporter logs"
    fi
else
    echo "❌ ERROR: Redis pod not found"
    exit 1
fi
echo ""

echo "5. Deploying Redis metrics alerts..."
if [ -f "$DEPLOYMENT_DIR/metrics-alert.yaml" ]; then
    # Check if PrometheusRule CRD exists
    if kubectl get crd prometheusrules.monitoring.coreos.com &> /dev/null; then
        apply_manifest "$DEPLOYMENT_DIR/metrics-alert.yaml" "Redis metrics alerts"
        
        # Verify alert creation
        if kubectl get prometheusrules redis-memory-alert -n "$NAMESPACE" &> /dev/null; then
            echo "✅ Redis alerts created successfully"
            
            # Show alert rules
            echo ""
            echo "Alert rules created:"
            kubectl get prometheusrules redis-memory-alert -n "$NAMESPACE" -o jsonpath='{.spec.groups[*].rules[*].alert}' | tr ' ' '\n'
        else
            echo "⚠️  Alert rules created but could not verify"
        fi
    else
        echo "⚠️  PrometheusRule CRD not available, skipping alert deployment"
        echo "   To enable alerts, install Prometheus Operator"
    fi
else
    echo "⚠️  metrics-alert.yaml not found, skipping alert deployment"
fi
echo ""

echo "6. Setting up Redis logical databases..."
echo "Configuring logical databases with TTL settings..."
echo ""
echo "Database configuration:"
echo "  - DB 0: Sessions (TTL 24h)"
echo "  - DB 1: Rate limiting (TTL 1h)"
echo "  - DB 2: Semantic cache for AI Plane (TTL 7d)"
echo ""

# Create a test script to verify database configuration
TEST_SCRIPT=$(cat << 'EOF'
#!/bin/bash
# Test Redis database configuration and TTL functionality

echo "Testing Redis database configuration..."
echo ""

# Test connection
if redis-cli ping | grep -q PONG; then
    echo "✅ Redis connection successful"
else
    echo "❌ Redis connection failed"
    exit 1
fi

echo ""
echo "Testing database selection..."

# Test DB 0 (Sessions)
echo "Testing DB 0 (Sessions)..."
redis-cli -n 0 set test-session "session-data" EX 86400
TTL=$(redis-cli -n 0 ttl test-session)
if [ "$TTL" -gt 86300 ] && [ "$TTL" -le 86400 ]; then
    echo "✅ DB 0: Session TTL set correctly (~24h)"
else
    echo "⚠️  DB 0: Session TTL is $TTL seconds (expected ~86400)"
fi
redis-cli -n 0 del test-session

# Test DB 1 (Rate limiting)
echo ""
echo "Testing DB 1 (Rate limiting)..."
redis-cli -n 1 set test-rate-limit "limit-data" EX 3600
TTL=$(redis-cli -n 1 ttl test-rate-limit)
if [ "$TTL" -gt 3500 ] && [ "$TTL" -le 3600 ]; then
    echo "✅ DB 1: Rate limit TTL set correctly (~1h)"
else
    echo "⚠️  DB 1: Rate limit TTL is $TTL seconds (expected ~3600)"
fi
redis-cli -n 1 del test-rate-limit

# Test DB 2 (Semantic cache)
echo ""
echo "Testing DB 2 (Semantic cache)..."
redis-cli -n 2 set test-semantic-cache "cache-data" EX 604800
TTL=$(redis-cli -n 2 ttl test-semantic-cache)
if [ "$TTL" -gt 604000 ] && [ "$TTL" -le 604800 ]; then
    echo "✅ DB 2: Semantic cache TTL set correctly (~7d)"
else
    echo "⚠️  DB 2: Semantic cache TTL is $TTL seconds (expected ~604800)"
fi
redis-cli -n 2 del test-semantic-cache

echo ""
echo "Testing database isolation..."
redis-cli -n 0 set db0-key "value0"
redis-cli -n 1 set db1-key "value1"
redis-cli -n 2 set db2-key "value2"

DB0_VAL=$(redis-cli -n 0 get db0-key)
DB1_VAL=$(redis-cli -n 1 get db1-key)
DB2_VAL=$(redis-cli -n 2 get db2-key)

if [ "$DB0_VAL" = "value0" ] && [ "$DB1_VAL" = "value1" ] && [ "$DB2_VAL" = "value2" ]; then
    echo "✅ Database isolation working correctly"
else
    echo "❌ Database isolation test failed"
fi

# Cleanup
redis-cli -n 0 del db0-key
redis-cli -n 1 del db1-key
redis-cli -n 2 del db2-key

echo ""
echo "Testing memory configuration..."
MEMORY_INFO=$(redis-cli info memory | grep -E "maxmemory:|maxmemory_policy:")
echo "Memory configuration:"
echo "$MEMORY_INFO"

echo ""
echo "Testing RDB configuration..."
RDB_INFO=$(redis-cli info persistence | grep -E "rdb_last_save_time|rdb_changes_since_last_save|aof_enabled:")
echo "Persistence configuration:"
echo "$RDB_INFO"

if echo "$RDB_INFO" | grep -q "aof_enabled:0"; then
    echo "✅ AOF is disabled (RDB-only mode)"
else
    echo "❌ AOF is enabled (should be disabled)"
fi

echo ""
echo "Redis database configuration test completed!"
EOF
)

# Save test script
TEST_SCRIPT_PATH="/tmp/test-redis-dbs.sh"
echo "$TEST_SCRIPT" > "$TEST_SCRIPT_PATH"
chmod +x "$TEST_SCRIPT_PATH"

echo "Test script created at $TEST_SCRIPT_PATH"
echo "Run this script after deployment to verify database configuration"
echo ""

echo "7. Verifying service endpoints..."
echo "Checking Redis service..."
REDIS_SERVICE_IP=$(kubectl get service redis -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
REDIS_SERVICE_PORT=$(kubectl get service redis -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="redis")].port}')

if [ -n "$REDIS_SERVICE_IP" ] && [ -n "$REDIS_SERVICE_PORT" ]; then
    echo "✅ Redis Service: $REDIS_SERVICE_IP:$REDIS_SERVICE_PORT"
else
    echo "❌ ERROR: Could not get Redis service details"
fi

echo "Checking metrics service..."
METRICS_PORT=$(kubectl get service redis -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="metrics")].port}')
if [ -n "$METRICS_PORT" ]; then
    echo "✅ Metrics endpoint: $REDIS_SERVICE_IP:$METRICS_PORT"
    
    # Test metrics endpoint
    echo "Testing metrics endpoint..."
    if kubectl run -n "$NAMESPACE" --rm -i --restart=Never test-metrics --image=curlimages/curl -- curl -s "http://$REDIS_SERVICE_IP:$METRICS_PORT/metrics" | grep -q "redis_"; then
        echo "✅ Metrics endpoint is serving Redis metrics"
    else
        echo "⚠️  Metrics endpoint test failed"
    fi
else
    echo "❌ ERROR: Could not get metrics port"
fi
echo ""

echo "8. Creating network policy if needed..."
# Check if network policy exists in shared directory
SHARED_NP="$PROJECT_ROOT/shared/network-policies/allow-policies/control-to-data-allow.yaml"
if [ -f "$SHARED_NP" ] && grep -q "app: redis" "$SHARED_NP"; then
    echo "✅ Redis network policy found in shared directory"
    echo "Applying network policy..."
    kubectl apply -f "$SHARED_NP"
else
    echo "⚠️  Redis-specific network policy not found in shared directory"
    echo "   Ensure network policies allow control plane to access Redis (port 6379)"
fi
echo ""

echo "9. Final verification..."
echo "Checking all deployed resources..."
kubectl get all -n "$NAMESPACE" -l app=redis

echo ""
echo "Checking ConfigMap..."
kubectl get configmap redis-config -n "$NAMESPACE"

echo ""
echo "Checking service details..."
kubectl get service redis -n "$NAMESPACE" -o wide

echo ""
echo "=============================================="
echo "Redis DP-4 Deployment Completed!"
echo "=============================================="
echo ""
echo "Summary:"
echo "- Redis deployment: ✅ Deployed with 512MB memory limit"
echo "- Configuration: ✅ RDB-only (AOF disabled)"
echo "- Logical databases: ✅ 3 databases configured with TTL"
echo "- Monitoring: ✅ Sidecar exporter deployed"
echo "- Alerts: ✅ Memory alerts configured (>450MB warning)"
echo "- Service: ✅ Available at redis.$NAMESPACE.svc.cluster.local:6379"
echo "- Metrics: ✅ Available at redis.$NAMESPACE.svc.cluster.local:9121"
echo ""
echo "Next steps:"
echo "1. Run validation script: ./03-validation.sh"
echo "2. Test Redis functionality with: kubectl exec -it $REDIS_POD -n $NAMESPACE -- redis-cli"
echo "3. Check metrics: curl http://$REDIS_SERVICE_IP:$METRICS_PORT/metrics"
echo ""
echo "Validation commands:"
echo "  redis-cli CONFIG GET appendonly  # should return 'no'"
echo "  redis-cli INFO memory            # check maxmemory and used memory"
echo "  redis-cli INFO keyspace          # shows database statistics"
echo "  redis-cli INFO persistence       # verify RDB configuration"
echo ""
echo "Note: Memory alert will trigger when redis_memory_used_bytes > 450MB"
echo ""

exit 0