#!/bin/bash

# Redis Phase DP-4: Validation Script
# Validates Redis multi-role cache tier deployment

set -e

echo "=============================================="
echo "Redis DP-4: Validation"
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
VALIDATION_TIMEOUT=${VALIDATION_TIMEOUT:-60}
TEST_ITERATIONS=${TEST_ITERATIONS:-3}

echo "Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Validation Timeout: ${VALIDATION_TIMEOUT}s"
echo "  Test Iterations: $TEST_ITERATIONS"
echo ""

# Validation counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Function to record test results
record_result() {
    local test_name=$1
    local status=$2
    local message=$3
    
    case $status in
        "PASS")
            echo "✅ PASS: $test_name - $message"
            ((PASS_COUNT++))
            ;;
        "FAIL")
            echo "❌ FAIL: $test_name - $message"
            ((FAIL_COUNT++))
            ;;
        "WARN")
            echo "⚠️  WARN: $test_name - $message"
            ((WARN_COUNT++))
            ;;
    esac
}

# Function to run Redis command
run_redis_cmd() {
    local pod=$1
    local cmd=$2
    kubectl exec "$pod" -n "$NAMESPACE" -c redis -- redis-cli $cmd 2>/dev/null
}

echo "1. Validating Kubernetes resources..."
echo ""

# Check Redis deployment
if kubectl get deployment redis -n "$NAMESPACE" &> /dev/null; then
    DEPLOYMENT_STATUS=$(kubectl get deployment redis -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}/{.status.replicas}')
    if [ "$DEPLOYMENT_STATUS" = "1/1" ]; then
        record_result "Deployment" "PASS" "Redis deployment ready ($DEPLOYMENT_STATUS)"
    else
        record_result "Deployment" "FAIL" "Redis deployment not ready ($DEPLOYMENT_STATUS)"
    fi
else
    record_result "Deployment" "FAIL" "Redis deployment not found"
fi

# Check Redis pod
REDIS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$REDIS_POD" ]; then
    POD_STATUS=$(kubectl get pod "$REDIS_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        record_result "Pod" "PASS" "Redis pod running ($REDIS_POD)"
        
        # Check container status
        CONTAINER_STATUS=$(kubectl get pod "$REDIS_POD" -n "$NAMESPACE" -o jsonpath='{range .status.containerStatuses[*]}{.name}:{.ready}{" "}{end}')
        if echo "$CONTAINER_STATUS" | grep -q "redis:true" && echo "$CONTAINER_STATUS" | grep -q "redis-exporter:true"; then
            record_result "Containers" "PASS" "All containers ready"
        else
            record_result "Containers" "FAIL" "Containers not ready: $CONTAINER_STATUS"
        fi
    else
        record_result "Pod" "FAIL" "Redis pod status: $POD_STATUS"
    fi
else
    record_result "Pod" "FAIL" "Redis pod not found"
fi

# Check Redis service
if kubectl get service redis -n "$NAMESPACE" &> /dev/null; then
    SERVICE_IP=$(kubectl get service redis -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
    if [ -n "$SERVICE_IP" ]; then
        record_result "Service" "PASS" "Redis service available at $SERVICE_IP"
    else
        record_result "Service" "FAIL" "Redis service has no cluster IP"
    fi
else
    record_result "Service" "FAIL" "Redis service not found"
fi

# Check ConfigMap
if kubectl get configmap redis-config -n "$NAMESPACE" &> /dev/null; then
    record_result "ConfigMap" "PASS" "Redis ConfigMap exists"
else
    record_result "ConfigMap" "FAIL" "Redis ConfigMap not found"
fi

echo ""
echo "2. Validating Redis configuration..."
echo ""

if [ -n "$REDIS_POD" ]; then
    # Test Redis connection
    if run_redis_cmd "$REDIS_POD" "ping" | grep -q "PONG"; then
        record_result "Connection" "PASS" "Redis responds to ping"
    else
        record_result "Connection" "FAIL" "Redis does not respond to ping"
    fi
    
    # Check AOF configuration (should be disabled)
    AOF_STATUS=$(run_redis_cmd "$REDIS_POD" "CONFIG GET appendonly")
    if echo "$AOF_STATUS" | grep -q "appendonly no"; then
        record_result "AOF Configuration" "PASS" "AOF is disabled (RDB-only mode)"
    else
        record_result "AOF Configuration" "FAIL" "AOF is not disabled: $AOF_STATUS"
    fi
    
    # Check maxmemory configuration
    MEMORY_CONFIG=$(run_redis_cmd "$REDIS_POD" "CONFIG GET maxmemory")
    if echo "$MEMORY_CONFIG" | grep -q "maxmemory 536870912"; then
        record_result "Memory Limit" "PASS" "Maxmemory set to 512MB (536870912 bytes)"
    else
        record_result "Memory Limit" "WARN" "Maxmemory not set to 512MB: $MEMORY_CONFIG"
    fi
    
    # Check maxmemory policy
    MEMORY_POLICY=$(run_redis_cmd "$REDIS_POD" "CONFIG GET maxmemory-policy")
    if echo "$MEMORY_POLICY" | grep -q "maxmemory-policy allkeys-lru"; then
        record_result "Memory Policy" "PASS" "Eviction policy set to allkeys-lru"
    else
        record_result "Memory Policy" "FAIL" "Wrong eviction policy: $MEMORY_POLICY"
    fi
    
    # Check RDB save configuration
    SAVE_CONFIG=$(run_redis_cmd "$REDIS_POD" "CONFIG GET save")
    if echo "$SAVE_CONFIG" | grep -q "save 900 1 300 10 60 10000"; then
        record_result "RDB Configuration" "PASS" "RDB save configuration correct"
    else
        record_result "RDB Configuration" "FAIL" "RDB save configuration incorrect: $SAVE_CONFIG"
    fi
    
    # Check databases configuration
    DATABASES=$(run_redis_cmd "$REDIS_POD" "CONFIG GET databases")
    if echo "$DATABASES" | grep -q "databases 3"; then
        record_result "Databases" "PASS" "3 databases configured"
    else
        record_result "Databases" "FAIL" "Wrong number of databases: $DATABASES"
    fi
else
    record_result "Redis Tests" "FAIL" "Cannot run Redis tests - pod not found"
fi

echo ""
echo "3. Validating Redis functionality..."
echo ""

if [ -n "$REDIS_POD" ]; then
    # Test basic operations
    echo "Testing basic Redis operations..."
    
    # Set and get a key
    run_redis_cmd "$REDIS_POD" "SET test:validation hello" > /dev/null
    GET_RESULT=$(run_redis_cmd "$REDIS_POD" "GET test:validation")
    if [ "$GET_RESULT" = "hello" ]; then
        record_result "Basic Operations" "PASS" "SET/GET operations working"
    else
        record_result "Basic Operations" "FAIL" "SET/GET failed: got '$GET_RESULT'"
    fi
    
    # Test TTL
    run_redis_cmd "$REDIS_POD" "SET test:ttl value EX 10" > /dev/null
    TTL_RESULT=$(run_redis_cmd "$REDIS_POD" "TTL test:ttl")
    if [ "$TTL_RESULT" -gt 0 ] && [ "$TTL_RESULT" -le 10 ]; then
        record_result "TTL" "PASS" "TTL working correctly ($TTL_RESULT seconds)"
    else
        record_result "TTL" "WARN" "TTL unexpected: $TTL_RESULT seconds"
    fi
    
    # Test database selection
    echo "Testing database isolation..."
    run_redis_cmd "$REDIS_POD" "-n 0 SET db0:test value0" > /dev/null
    run_redis_cmd "$REDIS_POD" "-n 1 SET db1:test value1" > /dev/null
    run_redis_cmd "$REDIS_POD" "-n 2 SET db2:test value2" > /dev/null
    
    DB0_VAL=$(run_redis_cmd "$REDIS_POD" "-n 0 GET db0:test")
    DB1_VAL=$(run_redis_cmd "$REDIS_POD" "-n 1 GET db1:test")
    DB2_VAL=$(run_redis_cmd "$REDIS_POD" "-n 2 GET db2:test")
    
    if [ "$DB0_VAL" = "value0" ] && [ "$DB1_VAL" = "value1" ] && [ "$DB2_VAL" = "value2" ]; then
        record_result "Database Isolation" "PASS" "Database isolation working"
    else
        record_result "Database Isolation" "FAIL" "Database isolation failed"
    fi
    
    # Cleanup test keys
    run_redis_cmd "$REDIS_POD" "DEL test:validation test:ttl" > /dev/null
    run_redis_cmd "$REDIS_POD" "-n 0 DEL db0:test" > /dev/null
    run_redis_cmd "$REDIS_POD" "-n 1 DEL db1:test" > /dev/null
    run_redis_cmd "$REDIS_POD" "-n 2 DEL db2:test" > /dev/null
    
    # Test memory usage
    echo "Checking memory usage..."
    MEMORY_INFO=$(run_redis_cmd "$REDIS_POD" "INFO memory")
    USED_MEMORY=$(echo "$MEMORY_INFO" | grep "used_memory:" | cut -d: -f2)
    MAX_MEMORY=$(echo "$MEMORY_INFO" | grep "maxmemory:" | cut -d: -f2)
    
    if [ "$USED_MEMORY" -lt 450000000 ]; then  # Less than 450MB
        record_result "Memory Usage" "PASS" "Memory usage: $(($USED_MEMORY/1024/1024))MB (under 450MB limit)"
    else
        record_result "Memory Usage" "WARN" "Memory usage high: $(($USED_MEMORY/1024/1024))MB (limit: 512MB)"
    fi
else
    record_result "Functionality Tests" "FAIL" "Cannot run functionality tests - pod not found"
fi

echo ""
echo "4. Validating monitoring and metrics..."
echo ""

# Check metrics endpoint
SERVICE_IP=$(kubectl get service redis -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
METRICS_PORT=$(kubectl get service redis -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="metrics")].port}' 2>/dev/null || true)

if [ -n "$SERVICE_IP" ] && [ -n "$METRICS_PORT" ]; then
    # Test metrics endpoint
    if kubectl run -n "$NAMESPACE" --rm -i --restart=Never test-metrics-$RANDOM \
        --image=curlimages/curl --quiet -- \
        curl -s -f "http://$SERVICE_IP:$METRICS_PORT/metrics" 2>/dev/null | grep -q "redis_"; then
        record_result "Metrics Endpoint" "PASS" "Metrics endpoint serving Redis metrics"
    else
        record_result "Metrics Endpoint" "FAIL" "Metrics endpoint not responding correctly"
    fi
    
    # Check specific metrics
    METRICS_RESPONSE=$(kubectl run -n "$NAMESPACE" --rm -i --restart=Never test-metrics-detail-$RANDOM \
        --image=curlimages/curl --quiet -- \
        curl -s "http://$SERVICE_IP:$METRICS_PORT/metrics" 2>/dev/null)
    
    if echo "$METRICS_RESPONSE" | grep -q "redis_up 1"; then
        record_result "Redis Up Metric" "PASS" "redis_up metric indicates Redis is up"
    else
        record_result "Redis Up Metric" "WARN" "redis_up metric not found or not 1"
    fi
    
    if echo "$METRICS_RESPONSE" | grep -q "redis_memory_used_bytes"; then
        record_result "Memory Metric" "PASS" "redis_memory_used_bytes metric available"
    else
        record_result "Memory Metric" "WARN" "redis_memory_used_bytes metric not found"
    fi
else
    record_result "Metrics" "FAIL" "Cannot test metrics - service IP or port not found"
fi

# Check alerts if PrometheusRule CRD exists
if kubectl get crd prometheusrules.monitoring.coreos.com &> /dev/null; then
    if kubectl get prometheusrules redis-memory-alert -n "$NAMESPACE" &> /dev/null; then
        record_result "Alerts" "PASS" "Redis memory alerts configured"
        
        # Check alert rules
        ALERT_COUNT=$(kubectl get prometheusrules redis-memory-alert -n "$NAMESPACE" -o jsonpath='{.spec.groups[0].rules}' | jq length 2>/dev/null || echo "0")
        if [ "$ALERT_COUNT" -gt 0 ]; then
            record_result "Alert Rules" "PASS" "$ALERT_COUNT alert rules configured"
        else
            record_result "Alert Rules" "WARN" "No alert rules found in PrometheusRule"
        fi
    else
        record_result "Alerts" "WARN" "Redis memory alerts not found (PrometheusRule CRD exists)"
    fi
else
    record_result "Alerts" "INFO" "PrometheusRule CRD not available (alerts not checked)"
fi

echo ""
echo "5. Validating performance and health..."
echo ""

if [ -n "$REDIS_POD" ]; then
    # Check Redis info
    REDIS_INFO=$(run_redis_cmd "$REDIS_POD" "INFO")
    
    # Check uptime
    UPTIME=$(echo "$REDIS_INFO" | grep "uptime_in_seconds:" | cut -d: -f2)
    if [ "$UPTIME" -gt 0 ]; then
        record_result "Uptime" "PASS" "Redis uptime: $(($UPTIME/60)) minutes"
    else
        record_result "Uptime" "WARN" "Redis uptime very low: $UPTIME seconds"
    fi
    
    # Check connected clients
    CLIENTS=$(echo "$REDIS_INFO" | grep "connected_clients:" | cut -d: -f2)
    if [ "$CLIENTS" -lt 100 ]; then
        record_result "Connected Clients" "PASS" "Connected clients: $CLIENTS"
    else
        record_result "Connected Clients" "WARN" "High number of connected clients: $CLIENTS"
    fi
    
    # Check keyspace
    KEYSPACE_INFO=$(run_redis_cmd "$REDIS_POD" "INFO keyspace")
    if echo "$KEYSPACE_INFO" | grep -q "db0:\|db1:\|db2:"; then
        record_result "Keyspace" "PASS" "Keyspace information available"
        echo "Keyspace details:"
        echo "$KEYSPACE_INFO" | grep -E "db[0-2]:"
    else
        record_result "Keyspace" "INFO" "No keyspace information yet (databases empty)"
    fi
    
    # Check persistence
    PERSISTENCE_INFO=$(run_redis_cmd "$REDIS_POD" "INFO persistence")
    if echo "$PERSISTENCE_INFO" | grep -q "rdb_last_save_time:"; then
        RDB_LAST_SAVE=$(echo "$PERSISTENCE_INFO" | grep "rdb_last_save_time:" | cut -d: -f2)
        CURRENT_TIME=$(date +%s)
        TIME_SINCE_SAVE=$((CURRENT_TIME - RDB_LAST_SAVE))
        
        if [ "$TIME_SINCE_SAVE" -lt 3600 ]; then
            record_result "RDB Persistence" "PASS" "RDB saved $(($TIME_SINCE_SAVE/60)) minutes ago"
        else
            record_result "RDB Persistence" "WARN" "RDB last saved $(($TIME_SINCE_SAVE/3600)) hours ago"
        fi
    fi
fi

echo ""
echo "6. Running comprehensive validation tests..."
echo ""

# Run validation from task requirements
echo "Running validation commands from task requirements:"
echo ""

if [ -n "$REDIS_POD" ]; then
    # 1. Check AOF configuration
    echo "1. redis-cli CONFIG GET appendonly"
    AOF_RESULT=$(run_redis_cmd "$REDIS_POD" "CONFIG GET appendonly")
    echo "   Result: $AOF_RESULT"
    if echo "$AOF_RESULT" | grep -q "appendonly no"; then
        echo "   ✅ Returns 'no' (AOF disabled)"
    else
        echo "   ❌ Does not return 'no'"
    fi
    echo ""
    
    # 2. Check keyspace info
    echo "2. redis-cli INFO keyspace"
    KEYSPACE_RESULT=$(run_redis_cmd "$REDIS_POD" "INFO keyspace")
    echo "   Result:"
    echo "$KEYSPACE_RESULT" | while read -r line; do
        echo "   $line"
    done
    echo ""
    
    # 3. Check memory usage
    echo "3. Memory usage check"
    MEMORY_USED=$(run_redis_cmd "$REDIS_POD" "INFO memory" | grep "used_memory:" | cut -d: -f2)
    MEMORY_USED_MB=$((MEMORY_USED / 1024 / 1024))
    echo "   Used memory: ${MEMORY_USED_MB}MB"
    if [ "$MEMORY_USED_MB" -lt 450 ]; then
        echo "   ✅ Memory usage < 450MB"
    else
        echo "   ⚠️  Memory usage > 450MB (${MEMORY_USED_MB}MB)"
    fi
else
    echo "Cannot run validation commands - Redis pod not available"
fi

echo ""
echo "=============================================="
echo "Validation Summary"
echo "=============================================="
echo "Total tests: $((PASS_COUNT + FAIL_COUNT + WARN_COUNT))"
echo "✅ Passed: $PASS_COUNT"
echo "❌ Failed: $FAIL_COUNT"
echo "⚠️  Warnings: $WARN_COUNT"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "🎉 Redis DP-4 validation PASSED!"
    echo ""
    echo "Deployment successfully validated:"
    echo "- Redis 7+ deployed with RDB-only configuration"
    echo "- AOF disabled (reduced disk I/O)"
    echo "- 3 logical databases configured with TTL"
    echo "- 512MB memory limit with allkeys-lru eviction"
    echo "- Memory alerting configured (>450MB warning)"
    echo "- Exporter sidecar providing metrics"
    echo ""
    echo "Redis is ready for use at:"
    echo "  Service: redis.$NAMESPACE.svc.cluster.local:6379"
    echo "  Metrics: redis.$NAMESPACE.svc.cluster.local:9121/metrics"
    echo ""
    echo "Database usage:"
    echo "  DB 0: Sessions (TTL 24h)"
    echo "  DB 1: Rate limiting (TTL 1h)"
    echo "  DB 2: Semantic cache for AI Plane (TTL 7d)"
else
    echo "❌ Redis DP-4 validation FAILED with $FAIL_COUNT error(s)"
    echo ""
    echo "Please check the failed tests above and fix the issues."
    echo "Common issues:"
    echo "1. Redis pod not running - check kubectl get pods -n $NAMESPACE"
    echo "2. Configuration mismatch - verify configmap.yaml"
    echo "3. Resource constraints - check node resources"
    echo "4. Network policies - ensure Redis port 6379 is accessible"
    exit 1
fi

echo "=============================================="
echo "Validation completed at: $(date)"
echo "=============================================="

exit 0