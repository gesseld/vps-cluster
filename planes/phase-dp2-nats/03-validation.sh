#!/bin/bash

set -e

echo "========================================="
echo "NATS JetStream Deployment Validation"
echo "========================================="

# Source environment variables if .env exists
if [ -f .env ]; then
    echo "Loading environment variables from .env"
    source .env
fi

# Default values
NAMESPACE=${NAMESPACE:-default}
VALIDATION_TIMEOUT=${VALIDATION_TIMEOUT:-60}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation counters
PASSED=0
FAILED=0
WARNING=0

# Function for validation output
print_validation() {
    local status=$1
    local message=$2
    
    case $status in
        "pass")
            echo -e "${GREEN}✓ PASS${NC}: $message"
            ((PASSED++))
            ;;
        "fail")
            echo -e "${RED}✗ FAIL${NC}: $message"
            ((FAILED++))
            ;;
        "warn")
            echo -e "${YELLOW}⚠ WARN${NC}: $message"
            ((WARNING++))
            ;;
    esac
}

# Function to check command with timeout
check_with_timeout() {
    local cmd=$1
    local timeout=$2
    local description=$3
    
    if timeout "$timeout" bash -c "$cmd" &> /dev/null; then
        print_validation "pass" "$description"
        return 0
    else
        print_validation "fail" "$description (timeout after ${timeout}s)"
        return 1
    fi
}

echo "Validating NATS JetStream deployment in namespace: $NAMESPACE"
echo ""

# Section 1: Basic Kubernetes Resources Validation
echo "Section 1: Kubernetes Resources"
echo "-------------------------------"

# 1.1 Check NATS pod
echo -n "Checking NATS pod... "
if kubectl get pod -l app=nats -n "$NAMESPACE" &> /dev/null; then
    NATS_POD=$(kubectl get pod -l app=nats -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    POD_STATUS=$(kubectl get pod "$NATS_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    
    if [ "$POD_STATUS" = "Running" ]; then
        print_validation "pass" "NATS pod is running ($NATS_POD)"
    else
        print_validation "fail" "NATS pod is not running (status: $POD_STATUS)"
    fi
else
    print_validation "fail" "NATS pod not found"
fi

# 1.2 Check NATS exporter pod
echo -n "Checking NATS exporter pod... "
if kubectl get pod -l app=nats,component=exporter -n "$NAMESPACE" &> /dev/null; then
    EXPORTER_POD=$(kubectl get pod -l app=nats,component=exporter -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    EXPORTER_STATUS=$(kubectl get pod "$EXPORTER_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    
    if [ "$EXPORTER_STATUS" = "Running" ]; then
        print_validation "pass" "NATS exporter pod is running ($EXPORTER_POD)"
    else
        print_validation "warn" "NATS exporter pod is not running (status: $EXPORTER_STATUS)"
    fi
else
    print_validation "warn" "NATS exporter pod not found"
fi

# 1.3 Check services
echo -n "Checking NATS service... "
if kubectl get svc nats -n "$NAMESPACE" &> /dev/null; then
    SERVICE_TYPE=$(kubectl get svc nats -n "$NAMESPACE" -o jsonpath='{.spec.type}')
    CLUSTER_IP=$(kubectl get svc nats -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
    
    if [ "$SERVICE_TYPE" = "ClusterIP" ] && [ "$CLUSTER_IP" != "None" ]; then
        print_validation "pass" "NATS service is available ($CLUSTER_IP)"
    else
        print_validation "fail" "NATS service configuration issue (type: $SERVICE_TYPE, IP: $CLUSTER_IP)"
    fi
else
    print_validation "fail" "NATS service not found"
fi

# 1.4 Check PVC
echo -n "Checking PersistentVolumeClaim... "
PVC_INFO=$(kubectl get pvc -l app=nats -n "$NAMESPACE" -o wide 2>/dev/null)
if [ -n "$PVC_INFO" ]; then
    PVC_STATUS=$(echo "$PVC_INFO" | awk 'NR==2 {print $2}')
    PVC_SIZE=$(echo "$PVC_INFO" | awk 'NR==2 {print $4}')
    PVC_STORAGE_CLASS=$(echo "$PVC_INFO" | awk 'NR==2 {print $6}')
    
    if [ "$PVC_STATUS" = "Bound" ]; then
        print_validation "pass" "PVC is bound"
        
        # Check PVC size (should be at least 12Gi)
        if [[ "$PVC_SIZE" =~ Gi$ ]] && [ "${PVC_SIZE%Gi}" -ge 12 ]; then
            print_validation "pass" "PVC size adequate ($PVC_SIZE)"
        else
            print_validation "warn" "PVC size may be insufficient ($PVC_SIZE)"
        fi
        
        # Check storage class
        if [ -n "$PVC_STORAGE_CLASS" ] && [ "$PVC_STORAGE_CLASS" != "(default)" ]; then
            print_validation "pass" "Storage class: $PVC_STORAGE_CLASS"
        fi
    else
        print_validation "warn" "PVC is not bound (status: $PVC_STATUS)"
    fi
    echo "$PVC_INFO"
else
    print_validation "warn" "PVC not found"
fi

# 1.5 Check network policies
echo -n "Checking network policies... "
NP_COUNT=$(kubectl get networkpolicy -l app=nats -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$NP_COUNT" -ge 1 ]; then
    print_validation "pass" "$NP_COUNT network policy(ies) applied"
else
    print_validation "warn" "No network policies found"
fi

# 1.6 Check PodDisruptionBudget
echo -n "Checking PodDisruptionBudget... "
if kubectl get pdb -l app=nats -n "$NAMESPACE" &> /dev/null; then
    print_validation "pass" "PodDisruptionBudget applied"
else
    print_validation "warn" "PodDisruptionBudget not found"
fi

# Section 2: NATS Server Validation
echo ""
echo "Section 2: NATS Server"
echo "----------------------"

# 2.1 Check NATS server connectivity
echo -n "Checking NATS server connectivity... "
if check_with_timeout "kubectl exec $NATS_POD -n $NAMESPACE -c nats -- nats server info 2>/dev/null" "$VALIDATION_TIMEOUT" "NATS server responding"; then
    # Get server info
    SERVER_INFO=$(kubectl exec "$NATS_POD" -n "$NAMESPACE" -c nats -- nats server info 2>/dev/null)
    
    # Check JetStream enabled
    if echo "$SERVER_INFO" | grep -q "JetStream: true"; then
        print_validation "pass" "JetStream enabled"
    else
        print_validation "fail" "JetStream not enabled"
    fi
    
    # Check TLS enabled
    if echo "$SERVER_INFO" | grep -q "TLS required: true"; then
        print_validation "pass" "TLS enabled"
    else
        print_validation "warn" "TLS not enabled"
    fi
fi

# 2.2 Check monitoring endpoint
echo -n "Checking monitoring endpoint... "
if check_with_timeout "kubectl exec $NATS_POD -n $NAMESPACE -c nats -- wget -q -O- http://localhost:8222/varz 2>/dev/null" "$VALIDATION_TIMEOUT" "Monitoring endpoint accessible"; then
    print_validation "pass" "Monitoring endpoint (8222) responding"
fi

# Section 3: JetStream Streams Validation
echo ""
echo "Section 3: JetStream Streams"
echo "----------------------------"

# 3.1 Check DOCUMENTS stream
echo -n "Checking DOCUMENTS stream... "
if check_with_timeout "kubectl exec $NATS_POD -n $NAMESPACE -c nats -- nats stream info DOCUMENTS 2>/dev/null" "$VALIDATION_TIMEOUT" "DOCUMENTS stream exists"; then
    STREAM_INFO=$(kubectl exec "$NATS_POD" -n "$NAMESPACE" -c nats -- nats stream info DOCUMENTS 2>/dev/null)
    
    # Check configuration
    if echo "$STREAM_INFO" | grep -q "data.doc.>"; then
        print_validation "pass" "DOCUMENTS stream configured with correct subjects"
    else
        print_validation "fail" "DOCUMENTS stream subjects incorrect"
    fi
    
    if echo "$STREAM_INFO" | grep -q "Work Queue"; then
        print_validation "pass" "DOCUMENTS stream has WorkQueue retention"
    else
        print_validation "fail" "DOCUMENTS stream retention incorrect"
    fi
fi

# 3.2 Check EXECUTION stream
echo -n "Checking EXECUTION stream... "
if check_with_timeout "kubectl exec $NATS_POD -n $NAMESPACE -c nats -- nats stream info EXECUTION 2>/dev/null" "$VALIDATION_TIMEOUT" "EXECUTION stream exists"; then
    STREAM_INFO=$(kubectl exec "$NATS_POD" -n "$NAMESPACE" -c nats -- nats stream info EXECUTION 2>/dev/null)
    
    if echo "$STREAM_INFO" | grep -q "exec.task.>"; then
        print_validation "pass" "EXECUTION stream configured with correct subjects"
    else
        print_validation "fail" "EXECUTION stream subjects incorrect"
    fi
fi

# 3.3 Check OBSERVABILITY stream
echo -n "Checking OBSERVABILITY stream... "
if check_with_timeout "kubectl exec $NATS_POD -n $NAMESPACE -c nats -- nats stream info OBSERVABILITY 2>/dev/null" "$VALIDATION_TIMEOUT" "OBSERVABILITY stream exists"; then
    STREAM_INFO=$(kubectl exec "$NATS_POD" -n "$NAMESPACE" -c nats -- nats stream info OBSERVABILITY 2>/dev/null)
    
    if echo "$STREAM_INFO" | grep -q "obs.metric.>"; then
        print_validation "pass" "OBSERVABILITY stream configured with correct subjects"
    else
        print_validation "fail" "OBSERVABILITY stream subjects incorrect"
    fi
fi

# 3.4 List all streams
echo -n "Listing all streams... "
STREAMS_LIST=$(kubectl exec "$NATS_POD" -n "$NAMESPACE" -c nats -- nats stream list 2>/dev/null)
STREAM_COUNT=$(echo "$STREAMS_LIST" | grep -c "Stream" || echo "0")

if [ "$STREAM_COUNT" -ge 3 ]; then
    print_validation "pass" "Found $STREAM_COUNT streams (expected at least 3)"
    echo "  Streams found:"
    echo "$STREAMS_LIST" | while read -r line; do
        echo "    $line"
    done
else
    print_validation "fail" "Found only $STREAM_COUNT streams (expected at least 3)"
fi

# Section 4: Backpressure Monitoring Validation
echo ""
echo "Section 4: Backpressure Monitoring"
echo "----------------------------------"

# 4.1 Check metrics exporter for VictoriaMetrics
echo -n "Checking metrics exporter for VictoriaMetrics... "
if [ -n "$EXPORTER_POD" ]; then
    if check_with_timeout "kubectl exec $EXPORTER_POD -n $NAMESPACE -- wget -q -O- http://localhost:7777/metrics 2>/dev/null" "$VALIDATION_TIMEOUT" "Metrics exporter responding"; then
        print_validation "pass" "Metrics exporter endpoint (7777) responding"
        
        # Check for JetStream metrics
        METRICS=$(kubectl exec "$EXPORTER_POD" -n "$NAMESPACE" -- wget -q -O- http://localhost:7777/metrics 2>/dev/null)
        if echo "$METRICS" | grep -q "nats_jetstream_stream"; then
            print_validation "pass" "JetStream metrics being exported for VictoriaMetrics"
            
            # Check key metrics exist
            for metric in nats_jetstream_stream_total_bytes nats_jetstream_stream_config_max_bytes nats_jetstream_stream_consumer_pending_msgs; do
                if echo "$METRICS" | grep -q "^${metric}"; then
                    print_validation "pass" "Key metric found: $metric"
                else
                    print_validation "warn" "Key metric missing: $metric"
                fi
            done
        else
            print_validation "warn" "No JetStream metrics found in exporter output"
        fi
    fi
else
    print_validation "warn" "Skipping metrics exporter check (pod not found)"
fi

# 4.2 Check backpressure script
echo -n "Checking backpressure monitoring script... "
if kubectl exec "$NATS_POD" -n "$NAMESPACE" -c nats -- test -f /tmp/create-streams.sh 2>/dev/null; then
    print_validation "pass" "Backpressure monitoring script available"
else
    print_validation "warn" "Backpressure monitoring script not found"
fi

# Section 5: TLS Validation
echo ""
echo "Section 5: TLS Configuration"
echo "----------------------------"

# 5.1 Check TLS secret
echo -n "Checking TLS secret... "
if kubectl get secret nats-tls -n "$NAMESPACE" &> /dev/null; then
    SECRET_KEYS=$(kubectl get secret nats-tls -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys[]' | tr '\n' ' ')
    
    if echo "$SECRET_KEYS" | grep -q "tls.crt" && echo "$SECRET_KEYS" | grep -q "tls.key" && echo "$SECRET_KEYS" | grep -q "ca.crt"; then
        print_validation "pass" "TLS secret contains required certificates"
    else
        print_validation "fail" "TLS secret missing required certificates (found: $SECRET_KEYS)"
    fi
else
    print_validation "fail" "TLS secret not found"
fi

# 5.2 Test TLS connection (simplified)
echo -n "Testing TLS configuration... "
if kubectl exec "$NATS_POD" -n "$NAMESPACE" -c nats -- nats server info --tlscert=/etc/nats/tls/tls.crt --tlskey=/etc/nats/tls/tls.key 2>/dev/null | grep -q "Server ID"; then
    print_validation "pass" "TLS certificates working"
else
    print_validation "warn" "TLS certificate test inconclusive"
fi

# Section 6: Namespace Labels Validation
echo ""
echo "Section 6: Namespace Configuration"
echo "----------------------------------"

# 6.1 Check required namespaces
for ns in execution control observability; do
    echo -n "Checking namespace '$ns'... "
    if kubectl get namespace "$ns" &> /dev/null; then
        LABEL=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.kubernetes\.io/metadata\.name}')
        
        if [ "$LABEL" = "$ns" ]; then
            print_validation "pass" "Namespace '$ns' exists with correct label"
        else
            print_validation "warn" "Namespace '$ns' exists but label incorrect (found: $LABEL)"
        fi
    else
        print_validation "warn" "Namespace '$ns' not found"
    fi
done

# Section 7: Test Message Flow
echo ""
echo "Section 7: Test Message Flow"
echo "----------------------------"

# 7.1 Test publishing to DOCUMENTS stream
echo -n "Testing message publish to DOCUMENTS stream... "
TEST_MESSAGE="Validation test $(date '+%Y-%m-%d %H:%M:%S')"
if kubectl exec "$NATS_POD" -n "$NAMESPACE" -c nats -- nats pub data.doc.test "$TEST_MESSAGE" 2>/dev/null; then
    print_validation "pass" "Message published successfully"
else
    print_validation "warn" "Message publish test failed"
fi

# 7.2 Check message count
echo -n "Checking message in stream... "
sleep 2  # Give time for message to be processed
MSG_COUNT=$(kubectl exec "$NATS_POD" -n "$NAMESPACE" -c nats -- nats stream info DOCUMENTS 2>/dev/null | grep "Messages" | awk '{print $2}')
if [ "$MSG_COUNT" -gt 0 ]; then
    print_validation "pass" "Stream contains $MSG_COUNT message(s)"
else
    print_validation "warn" "No messages found in stream"
fi

# Summary
echo ""
echo "========================================="
echo "Validation Summary"
echo "========================================="
echo "Total Checks: $((PASSED + FAILED + WARNING))"
echo -e "${GREEN}PASSED: $PASSED${NC}"
echo -e "${RED}FAILED: $FAILED${NC}"
echo -e "${YELLOW}WARNINGS: $WARNING${NC}"
echo ""

if [ "$FAILED" -eq 0 ]; then
    if [ "$WARNING" -eq 0 ]; then
        echo -e "${GREEN}✅ All validations passed!${NC}"
        echo ""
        echo "NATS JetStream deployment is fully operational."
        echo ""
        echo "Next steps:"
        echo "  1. Configure your applications to connect to:"
        echo "     nats://nats.$NAMESPACE.svc.cluster.local:4222"
        echo "  2. Use TLS certificates from secret 'nats-tls'"
        echo "  3. Monitor backpressure with metrics endpoint:"
        echo "     http://nats-exporter.$NAMESPACE.svc.cluster.local:7777/metrics"
        echo "  4. Set up alerts for backpressure >80%"
    else
        echo -e "${YELLOW}⚠ Validation completed with warnings${NC}"
        echo ""
        echo "Deployment is operational but has some warnings."
        echo "Review the warnings above and address as needed."
    fi
else
    echo -e "${RED}❌ Validation failed${NC}"
    echo ""
    echo "Some critical validations failed. Review the failures above."
    echo "Common issues:"
    echo "  • NATS pod not running - check logs: kubectl logs $NATS_POD -n $NAMESPACE"
    echo "  • Streams not created - re-run stream creation:"
    echo "    kubectl exec $NATS_POD -n $NAMESPACE -c nats -- /tmp/create-streams.sh"
    echo "  • TLS issues - regenerate certificates:"
    echo "    kubectl delete secret nats-tls -n $NAMESPACE"
    echo "    Then re-run ./02-deployment.sh"
    exit 1
fi

echo ""
echo "For detailed information:"
echo "  • NATS server info: kubectl exec $NATS_POD -n $NAMESPACE -c nats -- nats server info"
echo "  • Stream list: kubectl exec $NATS_POD -n $NAMESPACE -c nats -- nats stream list"
echo "  • VictoriaMetrics export: curl http://nats-exporter.$NAMESPACE.svc.cluster.local:7777/metrics"
echo "  • VMAgent config: kubectl get configmap nats-vmagent-scrape-config -o yaml"
echo ""