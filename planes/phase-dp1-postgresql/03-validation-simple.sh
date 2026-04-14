#!/bin/bash

set -e

echo "=========================================="
echo "PostgreSQL Phase DP-1: Simple Validation"
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

echo "1. Checking deployment status..."
echo ""

# Check 1: Pod status
echo "Checking pod status..."
kubectl get pods -n $NAMESPACE -l "app=postgresql" -o wide
echo ""

PODS_READY=$(kubectl get pods -n $NAMESPACE -l "app=postgresql" --no-headers | grep -c "Running")
if [ $PODS_READY -ge 1 ]; then
    echo "✓ PostgreSQL pod is running"
    ((VALIDATION_PASSED++))
else
    echo "✗ PostgreSQL pod is not running (found $PODS_READY)"
    ((VALIDATION_FAILED++))
fi

# Check 2: Services
echo ""
echo "2. Checking services..."
kubectl get svc -n $NAMESPACE -l "app=postgresql"
echo ""

SERVICES_COUNT=$(kubectl get svc -n $NAMESPACE -l "app=postgresql" --no-headers | wc -l)
if [ $SERVICES_COUNT -ge 1 ]; then
    echo "✓ PostgreSQL service created"
    ((VALIDATION_PASSED++))
else
    echo "✗ Missing PostgreSQL service"
    ((VALIDATION_FAILED++))
fi

# Check 3: PVC status
echo ""
echo "3. Checking PVC status..."
kubectl get pvc -n $NAMESPACE -l "app=postgresql"
echo ""

PVC_COUNT=$(kubectl get pvc -n $NAMESPACE -l "app=postgresql" --no-headers | grep -c "Bound")
if [ $PVC_COUNT -ge 1 ]; then
    echo "✓ PostgreSQL PVC is bound"
    ((VALIDATION_PASSED++))
else
    echo "✗ PostgreSQL PVC is not bound"
    ((VALIDATION_FAILED++))
fi

# Check 4: Test PostgreSQL connection
echo ""
echo "4. Testing PostgreSQL connections..."

# Test connection
kubectl exec -it $(kubectl get pod -l app=postgresql,role=primary -o name) -- \
    psql -U app_user -d app -c "SELECT 1;" > /dev/null 2>&1
log_result $? "PostgreSQL connection"

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

# Test that without tenant set, access is blocked
echo "Testing RLS blocks access without tenant..."
kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c "
SELECT COUNT(*) as no_tenant_docs FROM documents;
" 2>&1 | grep -q "unrecognized configuration parameter"
if [ $? -eq 0 ]; then
    echo "✓ RLS: Blocks access without tenant (GUC not set)"
    ((VALIDATION_PASSED++))
else
    # Check if it returns 0 rows
    kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c "
    SELECT COUNT(*) as no_tenant_docs FROM documents;
    " | grep -q "no_tenant_docs.*0"
    if [ $? -eq 0 ]; then
        echo "✓ RLS: Returns 0 rows without tenant"
        ((VALIDATION_PASSED++))
    else
        echo "✗ RLS: Does not block access without tenant"
        ((VALIDATION_FAILED++))
    fi
fi

# Check 6: Verify user is not superuser
echo ""
echo "6. Verifying user privileges..."
kubectl exec -it $PRIMARY_POD -- psql -U postgres -d app -c "
SELECT usename, usesuper, usebypassrls FROM pg_user WHERE usename = 'app_user';
" | grep -q "app_user.*f.*f"
log_result $? "User is not superuser and cannot bypass RLS"

# Check 7: Verify pgcrypto extension
echo ""
echo "7. Testing pgcrypto extension..."
kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c "
SELECT gen_random_uuid() IS NOT NULL as has_uuid;
" | grep -q "has_uuid.*t"
log_result $? "pgcrypto: UUID generation works"

# Check 8: Verify tables and indexes
echo ""
echo "8. Verifying tables and indexes..."
kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c "
SELECT COUNT(*) as tenants_count FROM tenants;
SELECT COUNT(*) as documents_count FROM documents;
SELECT COUNT(*) as workflows_count FROM workflows;
" | grep -q -E "(3|2|3)"
if [ $? -eq 0 ]; then
    echo "✓ Tables created with sample data"
    ((VALIDATION_PASSED++))
else
    echo "✗ Tables not properly created"
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
    echo "1. PostgreSQL 15 primary with RLS ✓"
    echo "2. Row-Level Security enabled and working ✓"
    echo "3. Tenant isolation via RLS ✓"
    echo "4. Non-superuser app_user without BYPASSRLS ✓"
    echo "5. pgcrypto extension for UUID generation ✓"
    echo "6. Sample data for testing ✓"
    echo ""
    echo "Note: Due to resource quota constraints, some components were skipped:"
    echo "- PostgreSQL replica (requires additional resources)"
    echo "- pgBouncer connection pooling"
    echo "- Automated backups"
    echo ""
    echo "Connection endpoint:"
    echo "- PostgreSQL: postgres-primary:5432"
    echo "- User: app_user"
    echo "- Password: appuser123"
    echo "- Database: app"
    echo ""
    echo "RLS is working correctly. Test with:"
    echo "kubectl exec -it $PRIMARY_POD -- psql -U app_user -d app -c \"SET app.current_tenant = '11111111-1111-1111-1111-111111111111'; SELECT * FROM documents;\""
else
    echo "⚠ SOME VALIDATIONS FAILED"
    echo ""
    echo "Please check the failed validations above."
fi

echo "=========================================="

exit $VALIDATION_FAILED