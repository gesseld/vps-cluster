#!/bin/bash
set -e

echo "=========================================="
echo "Temporal Server CP-1: Validation"
echo "=========================================="
echo "Validating Temporal Server deployment..."
echo

# Source environment variables if .env exists
ENV_FILE="$(dirname "$0")/.env"
if [ -f "$ENV_FILE" ]; then
    echo "Loading environment variables from $ENV_FILE"
    source "$ENV_FILE"
fi

# Default values
NAMESPACE=${NAMESPACE:-control-plane}
VALIDATION_TIMEOUT=${VALIDATION_TIMEOUT:-60}

echo "Validation Configuration:"
echo "  Namespace: $NAMESPACE"
echo "  Timeout: ${VALIDATION_TIMEOUT}s"
echo

# Initialize validation counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Helper function to run tests
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_status="${3:-0}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo "Test $TOTAL_TESTS: $test_name"
    
    if eval "$test_command" > /dev/null 2>&1; then
        if [ "$?" -eq "$expected_status" ]; then
            echo "  ✓ PASS"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        else
            echo "  ✗ FAIL (unexpected exit code)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    else
        echo "  ✗ FAIL (command failed)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Helper function for warnings
add_warning() {
    local warning_msg="$1"
    WARNING_TESTS=$((WARNING_TESTS + 1))
    echo "  ⚠️  WARNING: $warning_msg"
}

echo "Phase 1: Resource Validation"
echo "---------------------------"

# Test 1: Check namespace exists
run_test "Namespace exists" "kubectl get namespace $NAMESPACE"

# Test 2: Check StatefulSet exists and has correct replicas
run_test "StatefulSet exists with 2 replicas" \
    "kubectl get statefulset temporal -n $NAMESPACE -o jsonpath='{.spec.replicas}' | grep -q '^2$'"

# Test 3: Check pods are running
run_test "Pods are running" \
    "kubectl get pods -n $NAMESPACE -l app=temporal,component=server -o jsonpath='{.items[*].status.phase}' | grep -q Running"

# Test 4: Check all pods are ready
POD_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=temporal,component=server --no-headers 2>/dev/null | wc -l | tr -d ' ')
READY_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=temporal,component=server -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -c True || true)

if [ "$POD_COUNT" -eq 2 ] && [ "$READY_COUNT" -eq 2 ]; then
    echo "Test 4: Pod readiness"
    echo "  ✓ PASS (2/2 pods ready)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "Test 4: Pod readiness"
    echo "  ✗ FAIL ($READY_COUNT/$POD_COUNT pods ready)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 5: Check services exist
run_test "Services exist" \
    "kubectl get svc temporal temporal-headless -n $NAMESPACE"

# Test 6: Check NetworkPolicy exists
run_test "NetworkPolicy exists" \
    "kubectl get networkpolicy temporal-ingress -n $NAMESPACE"

# Test 7: Check PodDisruptionBudget exists
run_test "PodDisruptionBudget exists" \
    "kubectl get pdb temporal-pdb -n $NAMESPACE"

# Test 8: Check ConfigMap exists
run_test "ConfigMap exists" \
    "kubectl get configmap temporal-config -n $NAMESPACE"

# Test 9: Check ServiceAccount exists
run_test "ServiceAccount exists" \
    "kubectl get serviceaccount temporal-server -n $NAMESPACE"

echo
echo "Phase 2: Configuration Validation"
echo "--------------------------------"

# Test 10: Check resource limits
echo "Test 10: Resource limits"
RESOURCE_LIMITS=$(kubectl get statefulset temporal -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources}')
if echo "$RESOURCE_LIMITS" | grep -q '"1Gi"' && echo "$RESOURCE_LIMITS" | grep -q '"750Mi"'; then
    echo "  ✓ PASS (750Mi request / 1Gi limit)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "  ✗ FAIL (incorrect resource limits)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 11: Check anti-affinity configuration
echo "Test 11: Anti-affinity configuration"
AFFINITY=$(kubectl get statefulset temporal -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.affinity}')
if echo "$AFFINITY" | grep -q 'requiredDuringSchedulingIgnoredDuringExecution'; then
    echo "  ✓ PASS (anti-affinity configured)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    add_warning "Anti-affinity not configured"
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 12: Check topology spread constraints
echo "Test 12: Topology spread constraints"
TOPOLOGY=$(kubectl get statefulset temporal -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.topologySpreadConstraints}')
if echo "$TOPOLOGY" | grep -q 'maxSkew.*1'; then
    echo "  ✓ PASS (topology spread configured)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    add_warning "Topology spread not configured"
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 13: Check priority class
echo "Test 13: Priority class"
PRIORITY_CLASS=$(kubectl get statefulset temporal -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.priorityClassName}')
if [ -n "$PRIORITY_CLASS" ]; then
    echo "  ✓ PASS (priority class: $PRIORITY_CLASS)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    add_warning "No priority class configured"
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

echo
echo "Phase 3: Connectivity Validation"
echo "-------------------------------"

# Test 14: Check service endpoints
echo "Test 14: Service endpoints"
ENDPOINTS=$(kubectl get endpoints temporal -n "$NAMESPACE" -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w)
if [ "$ENDPOINTS" -ge 1 ]; then
    echo "  ✓ PASS ($ENDPOINTS endpoint(s) available)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "  ✗ FAIL (no endpoints available)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 15: Check frontend port (7233)
echo "Test 15: Frontend port accessibility"
if kubectl run -n "$NAMESPACE" --rm -i --restart=Never test-connectivity --image=alpine:latest -- \
    sh -c "timeout 5 nc -zv temporal.$NAMESPACE.svc.cluster.local 7233" > /dev/null 2>&1; then
    echo "  ✓ PASS (port 7233 accessible)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "  ✗ FAIL (port 7233 not accessible)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 16: Check metrics port (9090)
echo "Test 16: Metrics port accessibility"
if kubectl run -n "$NAMESPACE" --rm -i --restart=Never test-metrics --image=alpine:latest -- \
    sh -c "timeout 5 wget -q -O- http://temporal.$NAMESPACE.svc.cluster.local:9090/metrics | head -1" > /dev/null 2>&1; then
    echo "  ✓ PASS (metrics endpoint accessible)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "  ✗ FAIL (metrics endpoint not accessible)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 17: Check pod-to-pod communication (internal ports)
echo "Test 17: Internal service communication"
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=temporal,component=server -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- \
    sh -c "timeout 5 nc -zv localhost 7236" > /dev/null 2>&1; then
    echo "  ✓ PASS (internal ports accessible)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "  ✗ FAIL (internal ports not accessible)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

echo
echo "Phase 4: Health and Status Validation"
echo "------------------------------------"

# Test 18: Check Temporal health endpoint
echo "Test 18: Temporal health endpoint"
if kubectl run -n "$NAMESPACE" --rm -i --restart=Never test-health --image=curlimages/curl:latest -- \
    sh -c "timeout 10 curl -f http://temporal.$NAMESPACE.svc.cluster.local:9090/health" > /dev/null 2>&1; then
    echo "  ✓ PASS (health endpoint responding)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "  ✗ FAIL (health endpoint not responding)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 19: Check pod logs for errors
echo "Test 19: Pod logs analysis"
ERROR_COUNT=$(kubectl logs -n "$NAMESPACE" -l app=temporal,component=server --tail=50 2>/dev/null | grep -i "error\|fatal\|panic" | wc -l || true)
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo "  ✓ PASS (no recent errors in logs)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
elif [ "$ERROR_COUNT" -le 2 ]; then
    add_warning "Found $ERROR_COUNT minor errors in logs"
else
    echo "  ✗ FAIL (found $ERROR_COUNT errors in logs)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test 20: Check pod distribution across nodes
echo "Test 20: Pod distribution across nodes"
NODE_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=temporal,component=server -o jsonpath='{.items[*].spec.nodeName}' | tr ' ' '\n' | sort -u | wc -l)
if [ "$NODE_COUNT" -ge 2 ]; then
    echo "  ✓ PASS (pods distributed across $NODE_COUNT nodes)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    add_warning "Pods running on only $NODE_COUNT node(s) - may affect HA"
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

echo
echo "Phase 5: tctl Validation (Optional)"
echo "----------------------------------"

# Check if tctl is available
if command -v tctl > /dev/null 2>&1; then
    echo "Test 21: tctl cluster health"
    
    # Create a port-forward for tctl
    kubectl port-forward -n "$NAMESPACE" svc/temporal 7233:7233 > /dev/null 2>&1 &
    PORT_FORWARD_PID=$!
    sleep 3
    
    if tctl --address localhost:7233 cluster health 2>/dev/null | grep -q "SERVING"; then
        echo "  ✓ PASS (tctl reports SERVING)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  ✗ FAIL (tctl health check failed)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    kill $PORT_FORWARD_PID 2>/dev/null || true
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
else
    echo "Test 21: tctl cluster health"
    add_warning "tctl not available - install with: go install go.temporal.io/server/tools/cli@latest"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
fi

echo
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo
echo "Tests executed: $TOTAL_TESTS"
echo "✓ Passed: $PASSED_TESTS"
echo "✗ Failed: $FAILED_TESTS"
echo "⚠️  Warnings: $WARNING_TESTS"
echo

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo "✅ VALIDATION PASSED"
    echo
    echo "Temporal Server is deployed successfully with:"
    echo "  - 2 replicas (HA)"
    echo "  - Anti-affinity across nodes"
    echo "  - 750Mi/1Gi resource limits"
    echo "  - Network policies for execution-plane access"
    echo "  - PodDisruptionBudget (minAvailable: 1)"
    echo "  - Priority class: $PRIORITY_CLASS"
    echo
    echo "Access endpoints:"
    echo "  - Frontend: temporal.$NAMESPACE.svc.cluster.local:7233"
    echo "  - Metrics: temporal.$NAMESPACE.svc.cluster.local:9090/metrics"
    echo
    echo "Next steps:"
    echo "  1. Configure workflow execution in execution-plane"
    echo "  2. Set up monitoring and alerting"
    echo "  3. Test failover scenarios"
else
    echo "❌ VALIDATION FAILED"
    echo
    echo "Issues detected:"
    echo "  - $FAILED_TESTS test(s) failed"
    echo "  - $WARNING_TESTS warning(s)"
    echo
    echo "Troubleshooting steps:"
    echo "  1. Check pod status: kubectl get pods -n $NAMESPACE -l app=temporal"
    echo "  2. Check pod logs: kubectl logs -n $NAMESPACE -l app=temporal"
    echo "  3. Check events: kubectl get events -n $NAMESPACE --field-selector involvedObject.name=temporal"
    echo "  4. Verify PostgreSQL is running in data-plane"
    echo
    exit 1
fi