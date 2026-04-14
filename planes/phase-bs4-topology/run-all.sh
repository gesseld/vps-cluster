#!/bin/bash
# BS-4: Node Labeling for Topology Awareness - Complete Execution Script
# Runs all phases in sequence with proper error handling

echo "================================================================"
echo "BS-4: COMPLETE EXECUTION - TOPOLOGY AWARE NODE LABELING"
echo "================================================================"
echo "This script will run all phases of BS-4 implementation:"
echo "  1. Pre-deployment checks"
echo "  2. Node labeling deployment"
echo "  3. Validation"
echo ""
echo "Date: $(date)"
echo ""

# Set error handling
set -e

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}================================================================"
    echo -e "$1"
    echo -e "================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# Create execution directory
EXECUTION_DIR="execution-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EXECUTION_DIR"
print_info "Execution directory: $EXECUTION_DIR"

# Start overall log
OVERALL_LOG="$EXECUTION_DIR/overall-execution.log"
exec > >(tee -a "$OVERALL_LOG") 2>&1

echo "Overall execution log: $OVERALL_LOG"
echo ""

# Function to run phase with timing
run_phase() {
    local phase_number=$1
    local phase_script=$2
    local phase_name=$3
    
    print_header "PHASE $phase_number: $phase_name"
    echo "Starting at: $(date)"
    echo "Script: $phase_script"
    echo ""
    
    local start_time=$(date +%s)
    
    # Run the phase script
    if [ -f "$phase_script" ] && [ -x "$phase_script" ]; then
        "./$phase_script"
        local exit_code=$?
    else
        print_error "Script $phase_script not found or not executable"
        return 1
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "Phase completed in ${duration} seconds"
    
    if [ $exit_code -eq 0 ]; then
        print_success "Phase $phase_number completed successfully"
        return 0
    else
        print_error "Phase $phase_number failed with exit code $exit_code"
        return $exit_code
    fi
}

# Function to create summary report
create_summary() {
    print_header "EXECUTION SUMMARY"
    
    local summary_file="$EXECUTION_DIR/EXECUTION_SUMMARY.md"
    
    cat > "$summary_file" << EOF
# BS-4 Execution Summary

## Execution Details
- **Date:** $(date)
- **Execution ID:** $(basename "$EXECUTION_DIR")
- **Overall Status:** $1

## Phase Results

### Phase 1: Pre-deployment Check
- **Script:** 01-pre-deployment-check.sh
- **Status:** $PHASE1_STATUS
- **Log:** $PHASE1_LOG

### Phase 2: Deployment
- **Script:** 02-deployment.sh
- **Status:** $PHASE2_STATUS
- **Log:** $PHASE2_LOG

### Phase 3: Validation
- **Script:** 03-validation.sh
- **Status:** $PHASE3_STATUS
- **Log:** $PHASE3_LOG

## Cluster State After Execution
\`\`\`bash
$(kubectl get nodes --show-labels 2>/dev/null || echo "Unable to get node information")
\`\`\`

## Files Generated
- Overall execution log: $OVERALL_LOG
- Phase 1 log: $PHASE1_LOG
- Phase 2 log: $PHASE2_LOG  
- Phase 3 log: $PHASE3_LOG
- This summary: $summary_file

## Next Steps
1. Review validation results
2. Check node labels are correctly applied
3. Proceed with workload deployment using nodeSelectors
4. Monitor workload placement

## Issues Encountered
$ISSUES_SUMMARY
EOF
    
    print_success "Summary created: $summary_file"
    echo ""
    cat "$summary_file"
}

# Initialize variables
PHASE1_STATUS="NOT RUN"
PHASE2_STATUS="NOT RUN"
PHASE3_STATUS="NOT RUN"
PHASE1_LOG=""
PHASE2_LOG=""
PHASE3_LOG=""
ISSUES_SUMMARY="None"

# Track overall success
OVERALL_SUCCESS=true

print_header "STARTING BS-4 IMPLEMENTATION"

# Phase 1: Pre-deployment check
if run_phase "1" "01-pre-deployment-check.sh" "Pre-deployment Check"; then
    PHASE1_STATUS="SUCCESS"
    PHASE1_LOG=$(find logs -name "*.log" -type f | sort -r | head -1 2>/dev/null || echo "No log found")
else
    PHASE1_STATUS="FAILED"
    OVERALL_SUCCESS=false
    ISSUES_SUMMARY="Phase 1 (Pre-deployment) failed. Check pre-requisites and cluster connectivity."
    print_error "Stopping execution due to Phase 1 failure"
    create_summary "FAILED - Phase 1 failed"
    exit 1
fi

echo ""
print_info "Waiting 2 seconds before next phase..."
sleep 2

# Phase 2: Deployment
if run_phase "2" "02-deployment.sh" "Node Labeling Deployment"; then
    PHASE2_STATUS="SUCCESS"
    PHASE2_LOG=$(find logs -name "deployment-*.log" -type f | sort -r | head -1 2>/dev/null || echo "No log found")
else
    PHASE2_STATUS="FAILED"
    OVERALL_SUCCESS=false
    ISSUES_SUMMARY="${ISSUES_SUMMARY}\nPhase 2 (Deployment) failed. Check kubectl permissions and node status."
    print_error "Phase 2 failed, but continuing to validation..."
fi

echo ""
print_info "Waiting 3 seconds before validation..."
sleep 3

# Phase 3: Validation
if run_phase "3" "03-validation.sh" "Validation"; then
    PHASE3_STATUS="SUCCESS"
    PHASE3_LOG=$(find logs -name "validation-*.log" -type f | sort -r | head -1 2>/dev/null || echo "No log found")
else
    PHASE3_STATUS="FAILED"
    OVERALL_SUCCESS=false
    ISSUES_SUMMARY="${ISSUES_SUMMARY}\nPhase 3 (Validation) failed. Check node labels and cluster state."
fi

# Final summary
echo ""
print_header "EXECUTION COMPLETE"

if [ "$OVERALL_SUCCESS" = true ]; then
    print_success "ALL PHASES COMPLETED SUCCESSFULLY!"
    FINAL_STATUS="SUCCESS"
else
    print_error "EXECUTION COMPLETED WITH ERRORS"
    FINAL_STATUS="PARTIAL SUCCESS"
fi

# Create final summary
create_summary "$FINAL_STATUS"

echo ""
print_header "NEXT STEPS"

if [ "$FINAL_STATUS" = "SUCCESS" ]; then
    cat << EOF
1. ✅ Review the execution summary above
2. ✅ Verify node labels are correctly applied:
   kubectl get nodes --show-labels
3. ✅ Test workload placement with sample pods
4. ✅ Proceed with deploying:
   - PostgreSQL on storage-heavy nodes
   - MinIO on storage-heavy nodes  
   - Monitoring stack on general nodes
5. ✅ Monitor workload distribution and performance
EOF
else
    cat << EOF
1. ❌ Review errors in the execution summary
2. ❌ Check individual phase logs for details
3. ❌ Fix issues identified in validation
4. ❌ Re-run failed phases:
   $( [ "$PHASE1_STATUS" = "FAILED" ] && echo "   ./01-pre-deployment-check.sh" )
   $( [ "$PHASE2_STATUS" = "FAILED" ] && echo "   ./02-deployment.sh" )
   $( [ "$PHASE3_STATUS" = "FAILED" ] && echo "   ./03-validation.sh" )
5. ❌ Or re-run complete execution: ./run-all.sh
EOF
fi

echo ""
echo "Execution directory: $EXECUTION_DIR"
echo "Overall log: $OVERALL_LOG"
echo ""
echo "================================================================"
echo "BS-4 EXECUTION COMPLETE - $(date)"
echo "================================================================"

exit 0