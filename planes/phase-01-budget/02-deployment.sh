#!/bin/bash
# BS-2: ResourceQuotas + LimitRanges Deployment Script
# Implements namespace resource budgeting on VPS cluster

set -euo pipefail

echo "================================================================"
echo "BS-2: RESOURCEQUOTAS + LIMITRANGES DEPLOYMENT"
echo "================================================================"
echo "Date: $(date)"
echo "Task: Deploy foundation namespaces with resource budgeting"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DEPLOYMENT_START=$(date +%s)
SUCCESS=0
FAILURE=0

print_success() { echo -e "${GREEN}✓ SUCCESS${NC}: $1"; SUCCESS=$((SUCCESS + 1)); }
print_error() { echo -e "${RED}✗ ERROR${NC}: $1"; FAILURE=$((FAILURE + 1)); }
print_info() { echo -e "${YELLOW}ℹ️  INFO${NC}: $1"; }

# Function to check if a command succeeded
check_cmd() {
    if [ $? -eq 0 ]; then
        print_success "$1"
        return 0
    else
        print_error "$1"
        return 1
    fi
}

echo "=== DEPLOYMENT PHASE 1: PRE-DEPLOYMENT VALIDATION ==="
echo ""

# Run pre-deployment check
if [ -f "scripts/planes/01-pre-deployment-check.sh" ]; then
    echo "Running pre-deployment validation..."
    if bash "scripts/planes/01-pre-deployment-check.sh"; then
        print_success "Pre-deployment validation passed"
    else
        print_error "Pre-deployment validation failed"
        echo "Deployment aborted due to validation failures."
        exit 1
    fi
else
    print_error "Pre-deployment script not found"
    echo "Continuing with deployment anyway..."
fi

echo ""
echo "=== DEPLOYMENT PHASE 2: CREATE FOUNDATION NAMESPACES ==="
echo ""

# Create foundation namespaces
print_info "Creating foundation namespaces..."
if [ -f "shared/foundation-namespaces.yaml" ]; then
    kubectl apply -f shared/foundation-namespaces.yaml
    check_cmd "Applied foundation namespaces"
    
    # Wait for namespaces to be ready
    sleep 2
    for ns in control-plane data-plane observability-plane; do
        if kubectl get namespace "$ns" &> /dev/null; then
            print_success "Namespace '$ns' created successfully"
        else
            print_error "Namespace '$ns' creation failed"
        fi
    done
else
    print_error "foundation-namespaces.yaml not found"
    # Try to create namespaces manually
    for ns in control-plane data-plane observability-plane; do
        if ! kubectl get namespace "$ns" &> /dev/null; then
            kubectl create namespace "$ns"
            check_cmd "Created namespace '$ns'"
        else
            print_info "Namespace '$ns' already exists"
        fi
    done
fi

echo ""
echo "=== DEPLOYMENT PHASE 3: APPLY RESOURCEQUOTAS ==="
echo ""

# Apply ResourceQuotas
print_info "Applying ResourceQuotas..."
if [ -f "shared/resource-quotas.yaml" ]; then
    kubectl apply -f shared/resource-quotas.yaml
    check_cmd "Applied ResourceQuotas"
    
    # Verify ResourceQuotas were created
    for ns in control-plane data-plane observability-plane; do
        if kubectl get resourcequota -n "$ns" &> /dev/null; then
            print_success "ResourceQuota created in namespace '$ns'"
        else
            print_error "ResourceQuota not found in namespace '$ns'"
        fi
    done
else
    print_error "resource-quotas.yaml not found"
fi

echo ""
echo "=== DEPLOYMENT PHASE 4: APPLY LIMITRANGES ==="
echo ""

# Apply LimitRanges
print_info "Applying LimitRanges..."
if [ -f "shared/limit-ranges.yaml" ]; then
    kubectl apply -f shared/limit-ranges.yaml
    check_cmd "Applied LimitRanges"
    
    # Verify LimitRanges were created
    for ns in control-plane data-plane observability-plane; do
        if kubectl get limitrange -n "$ns" &> /dev/null; then
            print_success "LimitRange created in namespace '$ns'"
        else
            print_error "LimitRange not found in namespace '$ns'"
        fi
    done
else
    print_error "limit-ranges.yaml not found"
fi

echo ""
echo "=== DEPLOYMENT PHASE 5: VERIFICATION ==="
echo ""

# Verify all resources are properly deployed
print_info "Verifying deployment..."

# Check namespace labels
for ns in control-plane data-plane observability-plane; do
    LABELS=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels}' 2>/dev/null)
    if [ -n "$LABELS" ] && [ "$LABELS" != "null" ]; then
        print_success "Namespace '$ns' has labels: $LABELS"
    else
        print_error "Namespace '$ns' missing labels"
    fi
done

# Check ResourceQuota details
print_info "Checking ResourceQuota details..."
for ns in control-plane data-plane observability-plane; do
    if kubectl describe resourcequota -n "$ns" &> /dev/null; then
        print_success "ResourceQuota details available for '$ns'"
    else
        print_error "Cannot describe ResourceQuota in '$ns'"
    fi
done

# Check LimitRange details
print_info "Checking LimitRange details..."
for ns in control-plane data-plane observability-plane; do
    if kubectl describe limitrange -n "$ns" &> /dev/null; then
        print_success "LimitRange details available for '$ns'"
    else
        print_error "Cannot describe LimitRange in '$ns'"
    fi
done

echo ""
echo "=== DEPLOYMENT PHASE 6: TEST DEPLOYMENT ==="
echo ""

# Test deployment with a simple pod
print_info "Testing deployment with a test pod..."

# Create a test pod in control-plane namespace
TEST_POD_YAML=$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-quota-pod
  namespace: control-plane
spec:
  containers:
  - name: test-container
    image: busybox:latest
    command: ["sh", "-c", "sleep 3600"]
    resources:
      requests:
        memory: "128Mi"
        cpu: "50m"
      limits:
        memory: "256Mi"
        cpu: "100m"
EOF
)

echo "$TEST_POD_YAML" | kubectl apply -f - > /dev/null 2>&1
if [ $? -eq 0 ]; then
    print_success "Test pod created successfully (respects quotas)"
    
    # Wait for pod to be running
    sleep 3
    POD_STATUS=$(kubectl get pod test-quota-pod -n control-plane -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$POD_STATUS" = "Running" ]; then
        print_success "Test pod is running"
    else
        print_error "Test pod not running (status: $POD_STATUS)"
    fi
    
    # Clean up test pod
    kubectl delete pod test-quota-pod -n control-plane --force --grace-period=0 > /dev/null 2>&1
    print_info "Test pod cleaned up"
else
    print_error "Failed to create test pod (may be due to quota restrictions)"
fi

echo ""
echo "=== DEPLOYMENT SUMMARY ==="
echo "================================================================"
DEPLOYMENT_END=$(date +%s)
DEPLOYMENT_TIME=$((DEPLOYMENT_END - DEPLOYMENT_START))

echo "Deployment completed in ${DEPLOYMENT_TIME} seconds"
echo -e "${GREEN}Successful operations: $SUCCESS${NC}"
echo -e "${RED}Failed operations: $FAILURE${NC}"
echo ""

# List all created resources
echo "Created resources summary:"
echo "--------------------------"
kubectl get namespaces -l plane=foundation 2>/dev/null || true
echo ""
for ns in control-plane data-plane observability-plane; do
    echo "Resources in $ns:"
    kubectl get resourcequota,limitrange -n "$ns" 2>/dev/null || echo "  No resources found"
    echo ""
done

if [ "$FAILURE" -eq 0 ]; then
    echo -e "${GREEN}✅ DEPLOYMENT COMPLETED SUCCESSFULLY${NC}"
    echo "All ResourceQuotas and LimitRanges deployed to foundation namespaces."
    echo "Next step: Run validation script to verify implementation."
    exit 0
else
    echo -e "${YELLOW}⚠️  DEPLOYMENT COMPLETED WITH ERRORS${NC}"
    echo "Some operations failed. Review errors above."
    echo "Run validation script to assess deployment status."
    exit 1
fi