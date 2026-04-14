#!/bin/bash

# Redis Phase DP-4: Complete Execution Script
# Runs pre-deployment, deployment, and validation in sequence

set -e

echo "=============================================="
echo "Redis DP-4: Complete Execution"
echo "=============================================="
echo "Timestamp: $(date)"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to run script with logging
run_script() {
    local script_name=$1
    local log_file="$SCRIPT_DIR/execution-$(date +%Y%m%d-%H%M%S)-${script_name%.*}.log"
    
    echo ""
    echo "Running $script_name..."
    echo "Log output: $log_file"
    echo ""
    
    # Run script and capture output
    if "$SCRIPT_DIR/$script_name" 2>&1 | tee "$log_file"; then
        echo ""
        echo "✅ $script_name completed successfully"
        return 0
    else
        echo ""
        echo "❌ $script_name failed with exit code $?"
        echo "Check log file: $log_file"
        return 1
    fi
}

# Create execution directory
EXECUTION_DIR="$SCRIPT_DIR/execution-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EXECUTION_DIR"
echo "Execution directory: $EXECUTION_DIR"
echo ""

# Run pre-deployment check
if ! run_script "01-pre-deployment-check.sh"; then
    echo "❌ Pre-deployment check failed. Aborting."
    exit 1
fi

echo ""
echo "=============================================="
echo "Pre-deployment check passed. Proceeding with deployment."
echo "=============================================="
echo ""

# Ask for confirmation
read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment aborted by user."
    exit 0
fi

# Run deployment
if ! run_script "02-deployment.sh"; then
    echo "❌ Deployment failed. Check logs for details."
    exit 1
fi

echo ""
echo "=============================================="
echo "Deployment completed. Waiting for resources to stabilize..."
echo "=============================================="
echo ""

# Wait for Redis to be ready
echo "Waiting for Redis to be fully ready (30 seconds)..."
sleep 30

echo ""
echo "=============================================="
echo "Running validation..."
echo "=============================================="
echo ""

# Run validation
if ! run_script "03-validation.sh"; then
    echo "❌ Validation failed. Check logs for details."
    exit 1
fi

echo ""
echo "=============================================="
echo "Redis DP-4: Execution Complete!"
echo "=============================================="
echo ""
echo "Summary:"
echo "- Pre-deployment: ✅ Completed"
echo "- Deployment: ✅ Completed"
echo "- Validation: ✅ Completed"
echo ""
echo "Redis cache tier is now deployed and validated."
echo ""
echo "Access:"
echo "  Redis: redis.default.svc.cluster.local:6379"
echo "  Metrics: redis.default.svc.cluster.local:9121/metrics"
echo ""
echo "Database configuration:"
echo "  DB 0: Sessions (24h TTL)"
echo "  DB 1: Rate limiting (1h TTL)"
echo "  DB 2: Semantic cache (7d TTL)"
echo ""
echo "Memory management:"
echo "  Limit: 512MB with allkeys-lru eviction"
echo "  Alerts: >450MB warning, >500MB critical"
echo ""
echo "All logs saved to: $EXECUTION_DIR/"
echo ""

# Create execution summary
SUMMARY_FILE="$EXECUTION_DIR/EXECUTION_SUMMARY.md"
cat > "$SUMMARY_FILE" << EOF
# Redis DP-4 Execution Summary

## Execution Details
- Timestamp: $(date)
- Directory: $EXECUTION_DIR
- Status: COMPLETED

## Phase Components
1. **Pre-deployment Check**: ✅ PASSED
   - Validated cluster access
   - Checked storage classes
   - Verified configuration

2. **Deployment**: ✅ PASSED
   - Redis ConfigMap deployed
   - Redis Deployment with sidecar exporter
   - Service created (ports 6379, 9121)
   - Prometheus alerts configured

3. **Validation**: ✅ PASSED
   - Pod and service status verified
   - Redis configuration validated
   - Database functionality tested
   - Metrics endpoint confirmed

## Configuration Summary
- **Redis Version**: 7.2
- **Memory Limit**: 512MB
- **Eviction Policy**: allkeys-lru
- **Persistence**: RDB-only (AOF disabled)
- **Databases**: 3 logical databases
- **Monitoring**: Sidecar exporter (port 9121)

## Database Configuration
1. **DB 0**: Sessions (24h TTL)
2. **DB 1**: Rate limiting (1h TTL)
3. **DB 2**: Semantic cache (7d TTL)

## Alert Configuration
- **Warning**: >450MB memory usage
- **Critical**: >500MB memory usage
- **Redis Down**: 1 minute downtime
- **Exporter Down**: 1 minute downtime

## Access Information
- Redis Service: \`redis.default.svc.cluster.local:6379\`
- Metrics: \`redis.default.svc.cluster.local:9121/metrics\`

## Validation Commands
\`\`\`bash
# Verify AOF disabled
redis-cli CONFIG GET appendonly

# Check memory configuration
redis-cli CONFIG GET maxmemory
redis-cli CONFIG GET maxmemory-policy

# Test database isolation
redis-cli -n 0 SET test:session "data" EX 86400
redis-cli -n 1 SET test:ratelimit "data" EX 3600
redis-cli -n 2 SET test:semantic "data" EX 604800
\`\`\`

## Log Files
- Pre-deployment: \`$(ls $EXECUTION_DIR/*pre-deployment*.log 2>/dev/null | head -1 || echo "Not found")\`
- Deployment: \`$(ls $EXECUTION_DIR/*deployment*.log 2>/dev/null | head -1 || echo "Not found")\`
- Validation: \`$(ls $EXECUTION_DIR/*validation*.log 2>/dev/null | head -1 || echo "Not found")\`

## Next Steps
1. Integrate Redis with application services
2. Configure connection pooling in applications
3. Monitor memory usage and eviction rates
4. Set up backup strategy for RDB files if needed
EOF

echo "Execution summary saved to: $SUMMARY_FILE"
echo ""
echo "To view the summary: cat $SUMMARY_FILE"
echo ""

exit 0