#!/bin/bash
# Temporal HA Data Plane - Complete Deployment Script
# Runs all three deployment steps in sequence

set -e

echo "================================================"
echo "🚀 TEMPORAL HA DATA PLANE - COMPLETE DEPLOYMENT"
echo "================================================"
echo "Phase: DP-5 (Data Plane Temporal HA)"
echo "Date: $(date)"
echo "================================================"

# Check if scripts directory exists
if [ ! -d "scripts" ]; then
    echo "❌ ERROR: scripts directory not found"
    echo "Please run this script from the phase-dp5-temporal directory"
    exit 1
fi

cd scripts

echo ""
echo "📋 STEP 1: Running pre-deployment check..."
echo "------------------------------------------"
./01-pre-deployment-check.sh

echo ""
echo "🚀 STEP 2: Deploying Temporal HA components..."
echo "---------------------------------------------"
./02-deployment.sh

echo ""
echo "✅ STEP 3: Validating deployment..."
echo "-----------------------------------"
./03-validation.sh

echo ""
echo "================================================"
echo "🎉 DEPLOYMENT COMPLETE!"
echo "================================================"
echo ""
echo "📊 Deployment Summary:"
echo "---------------------"
echo "• PostgreSQL 15 with HA tuning deployed"
echo "• PgBouncer connection pooling deployed"
echo "• Temporal Server with HA configuration deployed"
echo "• Ingress configured for gRPC and Web UI access"
echo ""
echo "🔗 Access Points:"
echo "----------------"
echo "• Temporal gRPC: temporal-frontend.data-plane.svc.cluster.local:7233"
echo "• Temporal Web UI: temporal-web.data-plane.svc.cluster.local:8080"
echo "• PostgreSQL: postgresql.data-plane.svc.cluster.local:5432"
echo "• PgBouncer: pgbouncer.data-plane.svc.cluster.local:6432"
echo ""
echo "📝 Manual Configuration Required:"
echo "--------------------------------"
echo "1. Update domain names in manifests/temporal-*-ingress.yaml"
echo "2. Change default passwords for production security"
echo ""
echo "📁 Logs available in: ../logs/"
echo "📄 Reports available in: ../deliverables/"
echo "================================================"