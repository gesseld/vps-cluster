#!/bin/bash

echo "Testing Phase SF-1 directory structure..."
echo ""

# Check if scripts exist and are executable
for script in 01-pre-deployment-check.sh 02-deployment.sh 03-validation.sh; do
    if [ -f "$script" ]; then
        if [ -x "$script" ]; then
            echo "✓ $script exists and is executable"
        else
            echo "✗ $script exists but is not executable"
        fi
    else
        echo "✗ $script missing"
    fi
done

echo ""
echo "Checking directory structure..."
if [ -d "shared/pki" ]; then
    echo "✓ shared/pki directory exists"
else
    echo "⚠ shared/pki directory will be created during deployment"
fi

if [ -d "control-plane/spire" ]; then
    echo "✓ control-plane/spire directory exists"
else
    echo "⚠ control-plane/spire directory will be created during deployment"
fi

echo ""
echo "Checking README..."
if [ -f "README.md" ]; then
    echo "✓ README.md exists"
    echo "  Lines: $(wc -l < README.md)"
else
    echo "✗ README.md missing"
fi

echo ""
echo "Structure test complete."