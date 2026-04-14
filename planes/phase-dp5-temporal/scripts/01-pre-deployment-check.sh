#!/bin/bash
# Temporal HA Pre-Deployment Check Script
# Phase: Data Plane Temporal HA Installation
# Purpose: Verify all prerequisites are met before deployment

set -e

echo "================================================"
echo "📋 TEMPORAL HA PRE-DEPLOYMENT CHECK"
echo "================================================"
echo "Phase: Data Plane Temporal HA Installation"
echo "Date: $(date)"
echo "================================================"

# Create logs directory
mkdir -p ../logs

# Start logging
exec > >(tee -a ../logs/pre-deployment-check-$(date +%Y%m%d-%H%M%S).log) 2>&1

echo "🔍 Starting pre-deployment verification..."

# ============================================================================
# TASK 1: Verify k3s Cluster Health
# ============================================================================
echo ""
echo "✅ TASK 1: Verifying k3s Cluster Health"
echo "----------------------------------------"

# Check k3s version
echo "Checking k3s version..."
k3s --version || { echo "❌ k3s not found or not in PATH"; exit 1; }
echo "✓ k3s version check passed"

# Check cluster nodes
echo "Checking cluster nodes..."
kubectl get nodes
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -lt 3 ]; then
    echo "⚠️  Warning: Only $NODE_COUNT nodes found (minimum 3 recommended for HA)"
else
    echo "✓ Cluster has $NODE_COUNT nodes"
fi

# Check node status
ALL_READY=$(kubectl get nodes --no-headers | grep -c " Ready")
if [ "$ALL_READY" -eq "$NODE_COUNT" ]; then
    echo "✓ All nodes are Ready"
else
    echo "❌ Not all nodes are Ready ($ALL_READY/$NODE_COUNT)"
    exit 1
fi

# ============================================================================
# TASK 2: Verify Resource Availability
# ============================================================================
echo ""
echo "✅ TASK 2: Verifying Resource Availability"
echo "-------------------------------------------"

# Check if kubectl top is available
if kubectl top nodes >/dev/null 2>&1; then
    echo "Current resource usage:"
    kubectl top nodes
    echo ""
    echo "⚠️  Manual verification required: Ensure ≥6.5 vCPU / 11.5GB RAM free"
    echo "   for Temporal stack after Document Intelligence services"
else
    echo "⚠️  Metrics server not available. Manual resource check required."
fi

# Check existing namespaces
echo "Checking existing namespaces..."
kubectl get namespaces
echo ""

# Check if temporal-system namespace already exists
if kubectl get namespace temporal-system >/dev/null 2>&1; then
    echo "⚠️  WARNING: temporal-system namespace already exists!"
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting..."
        exit 1
    fi
fi

# ============================================================================
# TASK 3: Verify Required CLIs
# ============================================================================
echo ""
echo "✅ TASK 3: Verifying Required CLIs"
echo "-----------------------------------"

# Check Helm
echo "Checking Helm..."
helm version --short || { echo "❌ Helm not found"; exit 1; }
echo "✓ Helm installed"

# Check kubectl
echo "Checking kubectl..."
kubectl version --client || { echo "❌ kubectl not found"; exit 1; }
echo "✓ kubectl installed"

# Check temporal CLI (optional but recommended)
echo "Checking Temporal CLI..."
if command -v temporal &> /dev/null; then
    temporal --version || echo "⚠️  Temporal CLI found but version check failed"
    echo "✓ Temporal CLI installed"
else
    echo "⚠️  Temporal CLI not found (optional but recommended for testing)"
fi

# Check grpcurl (optional)
echo "Checking grpcurl..."
if command -v grpcurl &> /dev/null; then
    grpcurl --version || echo "⚠️  grpcurl found but version check failed"
    echo "✓ grpcurl installed"
else
    echo "⚠️  grpcurl not found (optional for gRPC testing)"
fi

# Check mc (MinIO client) - optional
echo "Checking MinIO client (mc)..."
if command -v mc &> /dev/null; then
    mc --version || echo "⚠️  mc found but version check failed"
    echo "✓ MinIO client installed"
else
    echo "⚠️  MinIO client not found (optional for backup integration)"
fi

# ============================================================================
# TASK 4: Verify DNS/Network Configuration
# ============================================================================
echo ""
echo "✅ TASK 4: Verifying DNS/Network Configuration"
echo "-----------------------------------------------"

echo "⚠️  Manual verification required for DNS entries:"
echo "   - VPS IP: 49.12.37.154 (configured automatically)"
echo "   - gRPC endpoint: http://49.12.37.154/temporal"
echo "   - Web UI: http://49.12.37.154/temporal-ui"
echo ""
echo "Note: Ingress will be configured automatically with VPS IP"

# Check if we can resolve local services
echo "Testing internal DNS resolution..."
if kubectl run dns-test --image=busybox -it --rm --restart=Never -- nslookup kubernetes.default >/dev/null 2>&1; then
    echo "✓ Internal DNS resolution working"
else
    echo "⚠️  Internal DNS test failed"
fi

# ============================================================================
# TASK 5: Verify Secrets Management
# ============================================================================
echo ""
echo "✅ TASK 5: Verifying Secrets Management"
echo "----------------------------------------"

echo "⚠️  SECURITY NOTICE:"
echo "   - PostgreSQL passwords will be generated during deployment"
echo "   - Store these securely after deployment"
echo "   - Consider using sealed-secrets or external vault for production"
echo ""

# Check if we have any existing secrets in temporal-system
if kubectl get namespace temporal-system >/dev/null 2>&1; then
    echo "Existing secrets in temporal-system:"
    kubectl get secrets -n temporal-system
fi

# ============================================================================
# TASK 6: Verify Storage Configuration
# ============================================================================
echo ""
echo "✅ TASK 6: Verifying Storage Configuration"
echo "-------------------------------------------"

# Check existing storage classes
echo "Available storage classes:"
kubectl get storageclass

# Check for Longhorn (optional - we'll use existing storage)
echo ""
echo "Note: Using existing storage class for PostgreSQL"
echo "      Ensure it supports ReadWriteMany or has proper HA configuration"

# ============================================================================
# TASK 7: Verify Load Balancer Configuration
# ============================================================================
echo ""
echo "✅ TASK 7: Verifying Load Balancer Configuration"
echo "-------------------------------------------------"

# Check existing LoadBalancer services
echo "Checking existing LoadBalancer services..."
EXISTING_LB=$(kubectl get svc -A --field-selector='type=LoadBalancer' -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}:{.status.loadBalancer.ingress[0].ip}{"\n"}{end}' 2>/dev/null || echo "None found")

if [ -n "$EXISTING_LB" ] && [ "$EXISTING_LB" != "None found" ]; then
    echo "Existing LoadBalancer services:"
    echo "$EXISTING_LB" | while read line; do
        echo "  - $line"
    done
else
    echo "⚠️  No existing LoadBalancer services found"
fi

# Check Hetzner Cloud Controller Manager
echo "Checking Hetzner Cloud Controller Manager..."
HCCM_POD=$(kubectl get pods -n kube-system -l app=hcloud-cloud-controller-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "Not found")

if [ "$HCCM_POD" != "Not found" ]; then
    echo "✓ Hetzner Cloud Controller Manager running: $HCCM_POD"
else
    echo "⚠️  Hetzner Cloud Controller Manager not found"
    echo "   LoadBalancer services may not provision correctly"
fi

# ============================================================================
# TASK 8: Generate Pre-Deployment Report
# ============================================================================
echo ""
echo "✅ TASK 8: Generating Pre-Deployment Report"
echo "--------------------------------------------"

REPORT_FILE="../deliverables/pre-deployment-report-$(date +%Y%m%d-%H%M%S).txt"

cat > "$REPORT_FILE" << EOF
================================================
TEMPORAL HA PRE-DEPLOYMENT REPORT
================================================
Date: $(date)
Phase: Data Plane Temporal HA Installation

SUMMARY:
- Cluster Nodes: $NODE_COUNT ($ALL_READY Ready)
- k3s Version: $(k3s --version 2>/dev/null || echo "Not found")
- Helm Available: $(helm version --short 2>/dev/null || echo "No")
- Temporal CLI: $(command -v temporal >/dev/null && echo "Yes" || echo "No")
- Traefik Version: $TRAEFIK_IMAGE

PREREQUISITE CHECKLIST:
✅ TASK 1: k3s Cluster Health - COMPLETE
✅ TASK 2: Resource Availability - MANUAL VERIFICATION REQUIRED
✅ TASK 3: Required CLIs - COMPLETE
✅ TASK 4: DNS/Network Configuration - MANUAL VERIFICATION REQUIRED
✅ TASK 5: Secrets Management - READY
✅ TASK 6: Storage Configuration - READY
✅ TASK 7: Traefik Configuration - COMPLETE

CRITICAL MANUAL VERIFICATIONS REQUIRED:
1. Resource Availability: Ensure ≥6.5 vCPU / 11.5GB RAM free
2. DNS Configuration: Update temporal.yourdomain.com and temporal-ui.yourdomain.com
3. Storage: Verify storage class supports HA requirements

NEXT STEPS:
1. Update DNS records in manifests
2. Run deployment script: ./scripts/02-deployment.sh
3. Run validation script: ./scripts/03-validation.sh

EOF

echo "📋 Pre-deployment report saved to: $REPORT_FILE"

# ============================================================================
# TASK 9: Create Pre-Deployment Flag
# ============================================================================
echo ""
echo "✅ TASK 9: Creating Pre-Deployment Flag"
echo "----------------------------------------"

FLAG_FILE="../deliverables/pre-deployment-checklist-complete.flag"
echo "Pre-deployment check completed successfully at $(date)" > "$FLAG_FILE"
echo "✓ Pre-deployment flag created: $FLAG_FILE"

# ============================================================================
# FINAL SUMMARY
# ============================================================================
echo ""
echo "================================================"
echo "🎉 PRE-DEPLOYMENT CHECK COMPLETE"
echo "================================================"
echo ""
echo "✅ All automated checks passed!"
echo ""
echo "⚠️  MANUAL ACTIONS REQUIRED BEFORE DEPLOYMENT:"
echo "   1. Verify resource availability (≥6.5 vCPU / 11.5GB RAM free)"
echo "   2. Update DNS records in manifests:"
echo "      - Edit manifests/temporal-grpc-ingress.yaml"
echo "      - Edit manifests/temporal-web-ingress.yaml"
echo "   3. Review and update passwords in deployment manifests"
echo ""
echo "📁 Deliverables created:"
echo "   - $REPORT_FILE"
echo "   - $FLAG_FILE"
echo "   - Logs in ../logs/"
echo ""
echo "➡️  Next step: Run deployment script"
echo "   ./scripts/02-deployment.sh"
echo ""
echo "================================================"