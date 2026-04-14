#!/bin/bash

set -e

echo "=========================================="
echo "PostgreSQL Phase DP-1: Complete Deployment"
echo "=========================================="
echo "Date: $(date)"
echo ""

# Step 1: Pre-deployment check
echo "Step 1: Running pre-deployment checks..."
./01-pre-deployment-check.sh
if [ $? -ne 0 ]; then
    echo "Pre-deployment checks failed. Please fix issues before proceeding."
    exit 1
fi

echo ""
echo "Step 2: Deploying PostgreSQL components..."
./02-deployment.sh
if [ $? -ne 0 ]; then
    echo "Deployment failed. Check logs for errors."
    exit 1
fi

echo ""
echo "Step 3: Validating deployment..."
./03-validation.sh
VALIDATION_RESULT=$?

echo ""
echo "=========================================="
echo "Deployment Complete"
echo "=========================================="
if [ $VALIDATION_RESULT -eq 0 ]; then
    echo "✅ PostgreSQL Phase DP-1 successfully deployed and validated!"
    echo ""
    echo "Summary:"
    echo "- PostgreSQL 15 primary with RLS deployed"
    echo "- PostgreSQL 15 async read replica deployed"
    echo "- pgBouncer connection pooling configured"
    echo "- Automated backups scheduled"
    echo "- Tenant isolation via RLS enabled"
    echo "- Topology spread across nodes"
    echo ""
    echo "Connection endpoints:"
    echo "- Application: pgbouncer:6432"
    echo "- Direct primary: postgres-primary:5432"
    echo "- Direct replica: postgres-replica:5432"
else
    echo "⚠ Deployment completed but some validations failed."
    echo "Check the validation output above for details."
    echo ""
    echo "To debug:"
    echo "kubectl logs -l app=postgresql,role=primary"
    echo "kubectl logs -l app=postgresql,role=replica"
    echo "kubectl logs -l app=pgbouncer"
fi

echo "=========================================="