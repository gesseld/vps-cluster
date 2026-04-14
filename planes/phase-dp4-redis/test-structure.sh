#!/bin/bash

# Test script for Redis DP-4 structure validation

set -e

echo "Testing Redis DP-4 structure..."
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "1. Checking directory structure..."
if [ -d "$PROJECT_ROOT/data-plane/redis" ]; then
    echo "✅ data-plane/redis directory exists"
else
    echo "❌ data-plane/redis directory not found"
    exit 1
fi

echo ""
echo "2. Checking configuration files..."
FILES=(
    "$PROJECT_ROOT/data-plane/redis/configmap.yaml"
    "$PROJECT_ROOT/data-plane/redis/deployment.yaml"
    "$PROJECT_ROOT/data-plane/redis/metrics-alert.yaml"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $(basename "$file") exists"
        
        # Basic YAML syntax check
        if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            echo "   YAML syntax valid"
        else
            echo "   ⚠️  YAML syntax check failed (may still be valid)"
        fi
    else
        echo "❌ $(basename "$file") not found"
    fi
done

echo ""
echo "3. Checking script files..."
SCRIPTS=(
    "$SCRIPT_DIR/01-pre-deployment-check.sh"
    "$SCRIPT_DIR/02-deployment.sh"
    "$SCRIPT_DIR/03-validation.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        echo "✅ $(basename "$script") exists"
        
        if [ -x "$script" ]; then
            echo "   Executable"
        else
            echo "   ⚠️  Not executable (run: chmod +x \"$script\")"
        fi
        
        # Check for shebang
        if head -1 "$script" | grep -q "^#!/bin/bash"; then
            echo "   Shebang correct"
        else
            echo "   ⚠️  Shebang missing or incorrect"
        fi
    else
        echo "❌ $(basename "$script") not found"
    fi
done

echo ""
echo "4. Checking README..."
if [ -f "$SCRIPT_DIR/README.md" ]; then
    echo "✅ README.md exists"
    
    # Check for key sections
    if grep -q "Objective" "$SCRIPT_DIR/README.md"; then
        echo "   Contains Objective section"
    fi
    
    if grep -q "Deployment Steps" "$SCRIPT_DIR/README.md"; then
        echo "   Contains Deployment Steps"
    fi
    
    if grep -q "Validation Tests" "$SCRIPT_DIR/README.md"; then
        echo "   Contains Validation Tests"
    fi
else
    echo "❌ README.md not found"
fi

echo ""
echo "5. Validating Redis configuration..."
if [ -f "$PROJECT_ROOT/data-plane/redis/configmap.yaml" ]; then
    echo "Checking Redis config requirements:"
    
    # Check for AOF disabled
    if grep -q "appendonly no" "$PROJECT_ROOT/data-plane/redis/configmap.yaml"; then
        echo "✅ AOF disabled (appendonly no)"
    else
        echo "❌ AOF not disabled"
    fi
    
    # Check for maxmemory
    if grep -q "maxmemory 512mb" "$PROJECT_ROOT/data-plane/redis/configmap.yaml"; then
        echo "✅ Maxmemory set to 512MB"
    else
        echo "❌ Maxmemory not set to 512MB"
    fi
    
    # Check for RDB save configuration
    if grep -q "save 900 1" "$PROJECT_ROOT/data-plane/redis/configmap.yaml" && \
       grep -q "save 300 10" "$PROJECT_ROOT/data-plane/redis/configmap.yaml" && \
       grep -q "save 60 10000" "$PROJECT_ROOT/data-plane/redis/configmap.yaml"; then
        echo "✅ RDB snapshot configuration correct"
    else
        echo "❌ RDB snapshot configuration incorrect"
    fi
    
    # Check for databases
    if grep -q "databases 3" "$PROJECT_ROOT/data-plane/redis/configmap.yaml"; then
        echo "✅ 3 databases configured"
    else
        echo "❌ Databases not configured correctly"
    fi
fi

echo ""
echo "6. Validating deployment configuration..."
if [ -f "$PROJECT_ROOT/data-plane/redis/deployment.yaml" ]; then
    echo "Checking deployment requirements:"
    
    # Check for Redis image
    if grep -q "image: redis:" "$PROJECT_ROOT/data-plane/redis/deployment.yaml"; then
        echo "✅ Redis image specified"
    else
        echo "❌ Redis image not specified"
    fi
    
    # Check for exporter sidecar
    if grep -q "redis-exporter" "$PROJECT_ROOT/data-plane/redis/deployment.yaml"; then
        echo "✅ Redis exporter sidecar configured"
    else
        echo "❌ Redis exporter not configured"
    fi
    
    # Check for memory limits
    if grep -q "512Mi" "$PROJECT_ROOT/data-plane/redis/deployment.yaml"; then
        echo "✅ 512MB memory limit set"
    else
        echo "❌ 512MB memory limit not set"
    fi
    
    # Check for service ports
    if grep -q "port: 6379" "$PROJECT_ROOT/data-plane/redis/deployment.yaml"; then
        echo "✅ Redis port 6379 configured"
    else
        echo "❌ Redis port not configured"
    fi
    
    if grep -q "port: 9121" "$PROJECT_ROOT/data-plane/redis/deployment.yaml"; then
        echo "✅ Metrics port 9121 configured"
    else
        echo "❌ Metrics port not configured"
    fi
fi

echo ""
echo "7. Validating alert configuration..."
if [ -f "$PROJECT_ROOT/data-plane/redis/metrics-alert.yaml" ]; then
    echo "Checking alert requirements:"
    
    # Check for memory alert
    if grep -q "RedisMemoryHigh" "$PROJECT_ROOT/data-plane/redis/metrics-alert.yaml"; then
        echo "✅ RedisMemoryHigh alert configured"
        
        # Check for 450MB threshold
        if grep -q "450 \* 1024 \* 1024" "$PROJECT_ROOT/data-plane/redis/metrics-alert.yaml"; then
            echo "✅ 450MB warning threshold set"
        else
            echo "❌ 450MB threshold not found"
        fi
    else
        echo "❌ RedisMemoryHigh alert not configured"
    fi
    
    # Check for critical alert
    if grep -q "RedisMemoryCritical" "$PROJECT_ROOT/data-plane/redis/metrics-alert.yaml"; then
        echo "✅ RedisMemoryCritical alert configured"
    else
        echo "❌ RedisMemoryCritical alert not configured"
    fi
fi

echo ""
echo "=============================================="
echo "Structure validation complete!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "1. Review the configuration files"
echo "2. Run pre-deployment check: ./01-pre-deployment-check.sh"
echo "3. Deploy: ./02-deployment.sh"
echo "4. Validate: ./03-validation.sh"
echo ""
echo "Note: This test only validates structure and syntax."
echo "      Actual deployment requires a running Kubernetes cluster."
echo ""

exit 0