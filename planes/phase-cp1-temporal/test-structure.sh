#!/bin/bash
set -e

echo "Testing Temporal CP-1 deployment structure..."
echo

# Check required files
REQUIRED_FILES=(
    "01-pre-deployment-check.sh"
    "02-deployment.sh"
    "03-validation.sh"
    "README.md"
    "control-plane/temporal/temporal-server.yaml"
    "control-plane/temporal/service.yaml"
    "control-plane/temporal/pdb.yaml"
    "control-plane/temporal/networkpolicy.yaml"
    "control-plane/temporal/rbac.yaml"
    "control-plane/temporal/config/config.yaml"
    "control-plane/temporal/config/dynamicconfig.yaml"
)

echo "Checking required files..."
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file (MISSING)"
        exit 1
    fi
done

echo
echo "Checking script permissions..."
SCRIPTS=("01-pre-deployment-check.sh" "02-deployment.sh" "03-validation.sh")
for script in "${SCRIPTS[@]}"; do
    if [ -x "$script" ]; then
        echo "  ✓ $script is executable"
    else
        echo "  ✗ $script is not executable"
        exit 1
    fi
done

echo
echo "Checking YAML syntax..."
YAML_FILES=(
    "control-plane/temporal/temporal-server.yaml"
    "control-plane/temporal/service.yaml"
    "control-plane/temporal/pdb.yaml"
    "control-plane/temporal/networkpolicy.yaml"
    "control-plane/temporal/rbac.yaml"
)

for yaml in "${YAML_FILES[@]}"; do
    if command -v yq > /dev/null 2>&1; then
        if yq eval '.' "$yaml" > /dev/null 2>&1; then
            echo "  ✓ $yaml (valid YAML)"
        else
            echo "  ✗ $yaml (invalid YAML)"
            exit 1
        fi
    elif command -v python3 > /dev/null 2>&1; then
        if python3 -c "import yaml; yaml.safe_load(open('$yaml'))" 2>/dev/null; then
            echo "  ✓ $yaml (valid YAML)"
        else
            echo "  ✗ $yaml (invalid YAML)"
            exit 1
        fi
    else
        echo "  ⚠️  $yaml (cannot validate - no yq or python3)"
    fi
done

echo
echo "Checking configuration files..."
CONFIG_FILES=(
    "control-plane/temporal/config/config.yaml"
    "control-plane/temporal/config/dynamicconfig.yaml"
)

for config in "${CONFIG_FILES[@]}"; do
    if [ -s "$config" ]; then
        echo "  ✓ $config (non-empty)"
    else
        echo "  ✗ $config (empty)"
        exit 1
    fi
done

echo
echo "Structure validation passed!"
echo
echo "Deployment ready with:"
echo "  - 3 executable scripts"
echo "  - 5 Kubernetes manifests"
echo "  - 2 configuration files"
echo "  - Comprehensive README"
echo
echo "To deploy:"
echo "  1. ./01-pre-deployment-check.sh"
echo "  2. ./02-deployment.sh"
echo "  3. ./03-validation.sh"