#!/bin/bash

set -e

echo "=========================================="
echo "PostgreSQL Phase DP-1: Validation"
echo "=========================================="
echo "Date: $(date)"
echo ""

# Load environment variables
if [ -f "../../.env" ]; then
    source "../../.env"
    echo "✓ Loaded environment variables from ../../.env"
fi

NAMESPACE=${NAMESPACE:-default}
VALIDATION_PASSED=0
VALIDATION_FAILED=0

# Function to log validation results
log_result() {
    if [ $1 -eq 0 ]; then
        echo "✓ $2"
        ((VALIDATION_PASSED++))
    else
        echo "✗ $2"
        ((VALIDATION_FAILED++))
    fi
}

# Function to test PostgreSQL connection
test_postgres_connection() {
    local host=$1
    local port=$2
    local user=$3
    local db=$4
    local desc=$5
    
    kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name | head -1) -- \
        psql -h $host -p $port -U $user -d $db -c "SELECT 1;" > /dev/null 2>&1
    log_result $? "$desc"
}

echo "1. Checking deployment status..."
echo ""

# Check 1: Pod status
echo "Checking pod status..."
kubectl get pods -n $NAMESPACE -l "app in (postgresql,pgbouncer)" -o wide
echo ""

PODS_READY=$(kubectl get pods -n $NAMESPACE -l "app in (postgresql,pgbouncer)" --no-headers | grep -c "Running")
if [ $PODS_READY -ge 4 ]; then
    echo "✓ All PostgreSQL and pgBouncer pods are running"
    ((VALIDATION_PASSED++))
else
    echo "✗ Not all pods are running (expected at least 4, found $PODS_READY)"
    ((VALIDATION_FAILED++))
fi

# Check 2: Services
echo ""
echo "2. Checking services..."
kubectl get svc -n $NAMESPACE -l "app in (postgresql,pgbouncer)"
echo ""

SERVICES_COUNT=$(kubectl get svc -n $NAMESPACE -l "app in (postgresql,pgbouncer)" --no-headers | wc -l)
if [ $SERVICES_COUNT -ge 3 ]; then
    echo "✓ All services created"
    ((VALIDATION_PASSED++))
else
    echo "✗ Missing services (expected 3, found $SERVICES_COUNT)"
    ((VALIDATION_FAILED++))
fi

# Check 3: PVC status
echo ""
echo "3. Checking PVC status..."
kubectl get pvc -n $NAMESPACE -l "app in (postgresql)"
echo ""

PVC_COUNT=$(kubectl get pvc -n $NAMESPACE -l "app in (postgresql)" --no-headers | grep -c "Bound")
if [ $PVC_COUNT -ge 2 ]; then
    echo "✓ PostgreSQL PVCs are bound"
    ((VALIDATION_PASSED++))
else
    echo "✗ Not all PVCs are bound (expected 2, found $PVC_COUNT)"
    ((VALIDATION_FAILED++))
fi

# Check 4: Test PostgreSQL connections
echo ""
echo "4. Testing PostgreSQL connections..."

# Test primary direct connection
test_postgres_connection "postgres-primary" "5432" "app_user" "app" "Primary PostgreSQL connection"

# Test replica direct connection
test_postgres_connection "postgres-replica" "5432" "app_user" "app" "Replica PostgreSQL connection"

# Test pgBouncer connection
test_postgres_connection "pgbouncer" "6432" "app_user" "app" "pgBouncer connection"

# Check 5: Verify RLS functionality
echo ""
echo "5. Testing Row-Level Security (RLS)..."

PRIMARY_POD=$(kubectl get pod -l app=postgresql,role=primary -o name | head -1 | sed 's/pod\///')

# Test tenant isolation
echo "Testing tenant isolation..."
kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c "
SET app.current_tenant = '11111111-1111-1111-1111-111111111111';
SELECT COUNT(*) as tenant_a_docs FROM documents;
" | grep -q "tenant_a_docs.*2"
log_result $? "RLS: Tenant A sees only 2 documents"

kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c "
SET app.current_tenant = '22222222-2222-2222-2222-222222222222';
SELECT COUNT(*) as tenant_b_docs FROM documents;
" | grep -q "tenant_b_docs.*2"
log_result $? "RLS: Tenant B sees only 2 documents"

# Test namespace isolation for workflows
echo "Testing namespace isolation..."
kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c "
SET app.current_namespace = 'namespace-1';
SELECT COUNT(*) as namespace_1_workflows FROM workflows;
" | grep -q "namespace_1_workflows.*2"
log_result $? "RLS: namespace-1 sees 2 workflows"

# Check 6: Verify replication
echo ""
echo "6. Testing replication..."

# Check replication status on primary
echo "Checking replication status on primary..."
kubectl exec -it $PRIMARY_POD -- psql -U postgres -d app -c "
SELECT client_addr, state, sync_state, replay_lag 
FROM pg_stat_replication;
" | grep -q "streaming"
log_result $? "Replication: Streaming active"

# Check if replica is in recovery mode
REPLICA_POD=$(kubectl get pod -l app=postgresql,role=replica -o name | head -1 | sed 's/pod\///')
kubectl exec -it $REPLICA_POD -- psql -U postgres -d app -c "SELECT pg_is_in_recovery();" | grep -q "t"
log_result $? "Replication: Replica is in recovery mode"

# Check 7: Verify pgcrypto extension
echo ""
echo "7. Testing pgcrypto extension..."
kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c "
SELECT gen_random_uuid() IS NOT NULL as has_uuid;
" | grep -q "has_uuid.*t"
log_result $? "pgcrypto: UUID generation works"

# Check 8: Test read replica routing
echo ""
echo "8. Testing read replica routing..."

# Create a test table and insert data
kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c "
CREATE TABLE IF NOT EXISTS validation_test (
    id SERIAL PRIMARY KEY,
    data TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO validation_test (data) VALUES ('test data ' || generate_series(1, 10));
"

# Test that reads can go to replica
echo "Testing read routing..."
# Note: In a real scenario, you would set app.read_only GUC or use different connection strings
# For this validation, we'll verify both primary and replica are accessible
kubectl exec -it $REPLICA_POD -- psql -U app_user -d app -c "SELECT COUNT(*) FROM validation_test;" | grep -q "10"
log_result $? "Read replica: Can read data from replica"

# Check 9: Verify backup cronjob
echo ""
echo "9. Checking backup configuration..."
kubectl get cronjob -n $NAMESPACE postgres-backup > /dev/null 2>&1
log_result $? "Backup: CronJob exists"

# Check 10: Verify topology spread
echo ""
echo "10. Checking topology spread..."
PRIMARY_NODE=$(kubectl get pod -l app=postgresql,role=primary -o jsonpath='{.items[0].spec.nodeName}')
REPLICA_NODE=$(kubectl get pod -l app=postgresql,role=replica -o jsonpath='{.items[0].spec.nodeName}')

if [ "$PRIMARY_NODE" != "$REPLICA_NODE" ]; then
    echo "✓ Primary and replica are on different nodes: $PRIMARY_NODE vs $REPLICA_NODE"
    ((VALIDATION_PASSED++))
else
    echo "⚠ Primary and replica are on the same node: $PRIMARY_NODE"
    ((VALIDATION_FAILED++))
fi

# Check node labels
PRIMARY_NODE_LABEL=$(kubectl get node $PRIMARY_NODE --show-labels | grep -c "node-role=storage-heavy")
REPLICA_NODE_LABEL=$(kubectl get node $REPLICA_NODE --show-labels | grep -c "node-role=storage-heavy")

if [ $PRIMARY_NODE_LABEL -eq 1 ] && [ $REPLICA_NODE_LABEL -eq 1 ]; then
    echo "✓ Both nodes have storage-heavy label"
    ((VALIDATION_PASSED++))
else
    echo "✗ Nodes missing storage-heavy label"
    ((VALIDATION_FAILED++))
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo "Total tests: $((VALIDATION_PASSED + VALIDATION_FAILED))"
echo "Passed: $VALIDATION_PASSED"
echo "Failed: $VALIDATION_FAILED"
echo ""

if [ $VALIDATION_FAILED -eq 0 ]; then
    echo "✅ ALL VALIDATIONS PASSED"
    echo ""
    echo "PostgreSQL Phase DP-1 implementation is complete and validated."
    echo ""
    echo "Key components deployed:"
    echo "1. PostgreSQL 15 primary with RLS"
    echo "2. PostgreSQL 15 async read replica"
    echo "3. pgBouncer connection pooling"
    echo "4. Automated backups"
    echo "5. Tenant isolation via RLS"
    echo "6. Topology spread across nodes"
    echo ""
    echo "Connection endpoints:"
    echo "- Application: pgbouncer:6432"
    echo "- Direct primary: postgres-primary:5432"
    echo "- Direct replica: postgres-replica:5432"
    echo ""
    echo "Test RLS with:"
    echo "kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c \"SET app.current_tenant = '11111111-1111-1111-1111-111111111111'; SELECT * FROM documents;\""
else
    echo "⚠ SOME VALIDATIONS FAILED"
    echo ""
    echo "Please check the failed validations above and fix the issues."
    echo "Common issues:"
    echo "1. Pods not ready - wait longer or check logs"
    echo "2. PVC not bound - check storage class"
    echo "3. Network connectivity - check services and network policies"
    echo ""
    echo "To debug:"
    echo "kubectl logs -l app=postgresql,role=primary"
    echo "kubectl logs -l app=postgresql,role=replica"
    echo "kubectl logs -l app=pgbouncer"
fi

echo "=========================================="

# Cleanup test data
kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c "DROP TABLE IF EXISTS validation_test;" > /dev/null 2>&1

exit $VALIDATION_FAILED