#!/bin/bash

set -e

echo "=== Phase 0 Budget Scaffolding: Deployment ==="
echo "Deploying PriorityClasses for resource budget enforcement..."

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}▶${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Timestamp for logging
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_FILE="deployment-${TIMESTAMP}.log"

echo "Logging deployment to: $LOG_FILE"
echo "Deployment started at: $(date)" | tee "$LOG_FILE"

echo ""
log_info "1. Running pre-deployment check..."
if ! ./01-pre-deployment-check.sh >> "$LOG_FILE" 2>&1; then
    log_error "Pre-deployment check failed. Check $LOG_FILE for details."
    exit 1
fi
log_success "Pre-deployment check passed"

echo ""
log_info "2. Deploying PriorityClasses..."
echo "Applying priority-classes.yaml..." | tee -a "$LOG_FILE"

if kubectl apply -f priority-classes.yaml >> "$LOG_FILE" 2>&1; then
    log_success "PriorityClasses applied successfully"
else
    log_error "Failed to apply PriorityClasses"
    echo "Check $LOG_FILE for details"
    exit 1
fi

echo ""
log_info "3. Verifying deployment..."
echo "Checking created PriorityClasses..." | tee -a "$LOG_FILE"

# Check each PriorityClass was created
ALL_CREATED=true
for CLASS in foundation-critical foundation-high foundation-medium; do
    if kubectl get priorityclass "$CLASS" >> "$LOG_FILE" 2>&1; then
        log_success "PriorityClass '$CLASS' created"
        
        # Get details
        VALUE=$(kubectl get priorityclass "$CLASS" -o jsonpath='{.value}')
        PREEMPTION=$(kubectl get priorityclass "$CLASS" -o jsonpath='{.preemptionPolicy}')
        echo "   Value: $VALUE, PreemptionPolicy: $PREEMPTION" | tee -a "$LOG_FILE"
    else
        log_error "PriorityClass '$CLASS' not found"
        ALL_CREATED=false
    fi
done

if [ "$ALL_CREATED" = false ]; then
    log_error "Not all PriorityClasses were created successfully"
    exit 1
fi

echo ""
log_info "4. Listing all PriorityClasses..."
echo "Current PriorityClasses in cluster:" | tee -a "$LOG_FILE"
kubectl get priorityclass | tee -a "$LOG_FILE"

echo ""
log_info "5. Creating test pod to verify PriorityClass functionality..."
# Create a simple test pod with foundation-critical priority
TEST_POD_YAML=$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-priority-critical
  namespace: default
spec:
  priorityClassName: foundation-critical
  containers:
  - name: test
    image: busybox:latest
    command: ["sleep", "3600"]
    resources:
      requests:
        memory: "64Mi"
        cpu: "50m"
      limits:
        memory: "128Mi"
        cpu: "100m"
  restartPolicy: Never
EOF
)

echo "Creating test pod with foundation-critical priority..." | tee -a "$LOG_FILE"
if echo "$TEST_POD_YAML" | kubectl apply -f - >> "$LOG_FILE" 2>&1; then
    log_success "Test pod created"
    
    # Wait for pod to be scheduled
    echo "Waiting for pod to be scheduled..." | tee -a "$LOG_FILE"
    sleep 5
    
    # Check pod status
    POD_STATUS=$(kubectl get pod test-priority-critical -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$POD_STATUS" = "Running" ] || [ "$POD_STATUS" = "Pending" ]; then
        log_success "Test pod is in '$POD_STATUS' state"
        echo "Pod details:" | tee -a "$LOG_FILE"
        kubectl get pod test-priority-critical -o wide | tee -a "$LOG_FILE"
        
        # Check priority class assignment
        ASSIGNED_CLASS=$(kubectl get pod test-priority-critical -o jsonpath='{.spec.priorityClassName}' 2>/dev/null || echo "NotAssigned")
        if [ "$ASSIGNED_CLASS" = "foundation-critical" ]; then
            log_success "PriorityClass correctly assigned to pod"
        else
            log_warn "PriorityClass not correctly assigned (got: $ASSIGNED_CLASS)"
        fi
    else
        log_warn "Test pod status: $POD_STATUS"
    fi
    
    # Clean up test pod
    echo "Cleaning up test pod..." | tee -a "$LOG_FILE"
    kubectl delete pod test-priority-critical --grace-period=0 --force >> "$LOG_FILE" 2>&1 || true
    log_success "Test pod cleaned up"
else
    log_warn "Failed to create test pod (may be permission issue)"
fi

echo ""
log_info "6. Creating documentation summary..."
SUMMARY_FILE="DEPLOYMENT_SUMMARY.md"
cat <<EOF > "$SUMMARY_FILE"
# Phase 0 Budget Scaffolding - Deployment Summary

## Deployment Details
- **Timestamp:** $(date)
- **Phase:** 0 - Budget Scaffolding
- **Task:** BS-1 PriorityClasses Deployment

## PriorityClasses Created

| Name | Value | Preemption Policy | Description |
|------|-------|-------------------|-------------|
| foundation-critical | 1000000 | PreemptLowerPriority | Critical foundation: PostgreSQL, NATS, Temporal |
| foundation-high | 900000 | PreemptLowerPriority | High-priority foundation: Kyverno, SPIRE, MinIO |
| foundation-medium | 800000 | PreemptLowerPriority | Medium-priority foundation: Observability components |

## Validation
Run validation script to verify deployment:
\`\`\`bash
./03-validation.sh
\`\`\`

## Next Steps
1. Apply PriorityClasses to foundation workloads as they are deployed
2. Use \`priorityClassName\` field in pod specifications
3. Higher priority pods can preempt lower priority pods during resource contention

## Notes
- These PriorityClasses establish the resource budget hierarchy
- Critical workloads (foundation-critical) have highest scheduling priority
- All classes use \`PreemptLowerPriority\` to ensure resource availability
EOF

log_success "Deployment summary created: $SUMMARY_FILE"

echo ""
log_info "7. Final status check..."
echo "Final PriorityClasses status:" | tee -a "$LOG_FILE"
kubectl get priorityclass | grep -E "NAME|foundation" | tee -a "$LOG_FILE"

echo ""
echo "=== Deployment Complete ===" | tee -a "$LOG_FILE"
log_success "Phase 0 Budget Scaffolding - PriorityClasses deployed successfully"
echo ""
echo "Next steps:"
echo "1. Review deployment summary: $SUMMARY_FILE"
echo "2. Run validation: ./03-validation.sh"
echo "3. Proceed to next phase with resource budget enforcement enabled"
echo ""
echo "Deployment log: $LOG_FILE"