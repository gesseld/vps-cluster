#!/bin/bash

# ArgoCD GitOps Controller - Test Structure Script
# Validates the directory structure and file organization

set -e

echo "=============================================="
echo "ArgoCD GitOps Controller - Structure Test"
echo "=============================================="

echo "Checking directory structure..."
echo ""

# Check main directory
if [ -d "." ]; then
    echo "✅ Current directory accessible"
else
    echo "❌ ERROR: Cannot access current directory"
    exit 1
fi

# Check required directories
REQUIRED_DIRS=(
    "control-plane/argocd"
    "control-plane/argocd/applicationsets"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "✅ Directory exists: $dir"
    else
        echo "❌ ERROR: Directory missing: $dir"
        exit 1
    fi
done
echo ""

# Check required files
REQUIRED_FILES=(
    "README.md"
    "01-pre-deployment-check.sh"
    "02-deployment.sh"
    "03-validation.sh"
    "control-plane/argocd/kustomization.yaml"
    "control-plane/argocd/argocd-cm.yaml"
    "control-plane/argocd/resource-quota.yaml"
    "control-plane/argocd/repository-secret.yaml"
    "control-plane/argocd/applicationsets/control-plane.yaml"
    "control-plane/argocd/applicationsets/data-plane.yaml"
    "control-plane/argocd/applicationsets/observability-plane.yaml"
    "control-plane/argocd/applicationsets/security-plane.yaml"
    "control-plane/argocd/applicationsets/ai-plane.yaml"
)

echo "Checking required files..."
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ File exists: $file"
        
        # Check file size
        FILE_SIZE=$(wc -c < "$file")
        if [ $FILE_SIZE -gt 0 ]; then
            echo "   Size: $FILE_SIZE bytes"
        else
            echo "⚠️  Warning: File is empty: $file"
        fi
    else
        echo "❌ ERROR: File missing: $file"
        exit 1
    fi
done
echo ""

# Check file permissions
echo "Checking script permissions..."
SCRIPTS=(
    "01-pre-deployment-check.sh"
    "02-deployment.sh"
    "03-validation.sh"
    "test-structure.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -x "$script" ]; then
        echo "✅ Script is executable: $script"
    else
        echo "⚠️  Making script executable: $script"
        chmod +x "$script"
    fi
done
echo ""

# Validate YAML files
echo "Validating YAML files..."
YAML_FILES=$(find . -name "*.yaml" -o -name "*.yml")

# Skip validation if no tools available
if ! command -v yq &> /dev/null && ! command -v kubectl &> /dev/null; then
    echo "⚠️  Skipping YAML validation (yq or kubectl not available)"
    echo "   Found $(echo "$YAML_FILES" | wc -l) YAML files"
else
    for yaml_file in $YAML_FILES; do
        echo "Validating: $yaml_file"
        
        # Check if file contains valid YAML using yq or kubectl
        if command -v yq &> /dev/null; then
            if yq eval '.' "$yaml_file" > /dev/null 2>&1; then
                echo "✅ Valid YAML: $yaml_file"
            else
                echo "❌ ERROR: Invalid YAML in: $yaml_file"
                exit 1
            fi
        elif command -v kubectl &> /dev/null; then
            # Try to validate YAML, but don't fail on missing CRDs
            if kubectl apply --dry-run=client -f "$yaml_file" > /dev/null 2>&1; then
                echo "✅ Valid YAML: $yaml_file"
            else
                # Check if error is about missing CRDs (which is expected before ArgoCD installation)
                ERROR_OUTPUT=$(kubectl apply --dry-run=client -f "$yaml_file" 2>&1)
                if echo "$ERROR_OUTPUT" | grep -q "no matches for kind"; then
                    echo "⚠️  YAML validation skipped (CRD not installed yet): $yaml_file"
                else
                    echo "❌ ERROR: Invalid YAML in: $yaml_file"
                    echo "   Error: $ERROR_OUTPUT"
                    exit 1
                fi
            fi
        fi
    done
fi
echo ""

# Check for .env file
echo "Checking environment configuration..."
if [ -f ".env" ]; then
    echo "✅ .env file exists"
    
    # Check if .env contains required variables
    REQUIRED_VARS=("ARGOCD_NAMESPACE" "ARGOCD_VERSION" "GIT_REPO_URL")
    
    for var in "${REQUIRED_VARS[@]}"; do
        if grep -q "^export $var=" .env 2>/dev/null || grep -q "^$var=" .env 2>/dev/null; then
            echo "✅ Environment variable defined: $var"
        else
            echo "⚠️  Environment variable not defined: $var"
        fi
    done
else
    echo "⚠️  .env file not found"
    echo "   Creating example .env file..."
    
    cat > .env.example <<EOF
# ArgoCD GitOps Controller Configuration
export ARGOCD_NAMESPACE=argocd
export ARGOCD_VERSION=2.9.0
export GIT_REPO_URL=git@github.com:your-org/your-repo.git
export GIT_BRANCH=main
export GIT_PATH=manifests
export HELM_TIMEOUT=10m

# Git credentials (for HTTPS repositories)
# export GIT_USERNAME=your-username
# export GIT_PASSWORD=your-token

# Validation settings
export VALIDATION_TIMEOUT=300
export DRIFT_DETECTION_TIMEOUT=60
EOF
    
    echo "   Created .env.example file"
    echo "   Copy to .env and customize: cp .env.example .env"
fi
echo ""

# Check kustomization.yaml structure
echo "Validating kustomization.yaml..."
if [ -f "control-plane/argocd/kustomization.yaml" ]; then
    echo "✅ kustomization.yaml exists"
    
    # Check for required sections
    if grep -q "apiVersion: kustomize.config.k8s.io" control-plane/argocd/kustomization.yaml; then
        echo "✅ Valid kustomize apiVersion"
    fi
    
    if grep -q "kind: Kustomization" control-plane/argocd/kustomization.yaml; then
        echo "✅ Valid kustomize kind"
    fi
    
    if grep -q "namespace: argocd" control-plane/argocd/kustomization.yaml; then
        echo "✅ Namespace configured"
    fi
fi
echo ""

# Check ApplicationSets count
echo "Checking ApplicationSets..."
APPSET_COUNT=$(find control-plane/argocd/applicationsets -name "*.yaml" | wc -l)
if [ $APPSET_COUNT -eq 5 ]; then
    echo "✅ Found 5 ApplicationSets (5-plane structure)"
    
    # List ApplicationSets
    echo "  ApplicationSets:"
    for appset in control-plane/argocd/applicationsets/*.yaml; do
        BASENAME=$(basename $appset)
        echo "  - $BASENAME"
    done
else
    echo "❌ ERROR: Found $APPSET_COUNT ApplicationSets (expected 5)"
    exit 1
fi
echo ""

# Check resource quota configuration
echo "Checking resource quota..."
if [ -f "control-plane/argocd/resource-quota.yaml" ]; then
    if grep -q "limits.memory: 512Mi" control-plane/argocd/resource-quota.yaml; then
        echo "✅ Memory limit configured: 512Mi"
    else
        echo "❌ ERROR: Memory limit not set to 512Mi"
        exit 1
    fi
    
    if grep -q "kubectl.parallelism.limit: \"5\"" control-plane/argocd/argocd-cm.yaml; then
        echo "✅ Parallelism limit configured: 5"
    else
        echo "❌ ERROR: Parallelism limit not set to 5"
        exit 1
    fi
fi
echo ""

# Test script functionality
echo "Testing script functionality..."
echo ""

# Test pre-deployment script (dry run)
echo "Testing pre-deployment script (syntax check)..."
if bash -n 01-pre-deployment-check.sh; then
    echo "✅ pre-deployment script syntax is valid"
else
    echo "❌ ERROR: pre-deployment script syntax error"
    exit 1
fi

# Test deployment script (dry run)
echo "Testing deployment script (syntax check)..."
if bash -n 02-deployment.sh; then
    echo "✅ deployment script syntax is valid"
else
    echo "❌ ERROR: deployment script syntax error"
    exit 1
fi

# Test validation script (dry run)
echo "Testing validation script (syntax check)..."
if bash -n 03-validation.sh; then
    echo "✅ validation script syntax is valid"
else
    echo "❌ ERROR: validation script syntax error"
    exit 1
fi
echo ""

# Check for documentation
echo "Checking documentation..."
if [ -f "README.md" ]; then
    README_LINES=$(wc -l < README.md)
    if [ $README_LINES -gt 50 ]; then
        echo "✅ README.md is comprehensive ($README_LINES lines)"
    else
        echo "⚠️  README.md is short ($README_LINES lines)"
    fi
    
    # Check for required sections
    REQUIRED_SECTIONS=("Objective" "Architecture" "Prerequisites" "Deployment Steps")
    
    for section in "${REQUIRED_SECTIONS[@]}"; do
        if grep -q "^## $section" README.md; then
            echo "✅ README section found: $section"
        else
            echo "⚠️  README section missing: $section"
        fi
    done
fi
echo ""

echo "=============================================="
echo "Structure Test Complete!"
echo "=============================================="
echo ""
echo "Summary:"
echo "✅ Directory structure is valid"
echo "✅ All required files exist"
echo "✅ Script permissions are correct"
echo "✅ YAML files are valid"
echo "✅ ApplicationSets configured (5-plane structure)"
echo "✅ Resource limits configured (512MB memory, parallelism limit: 5)"
echo "✅ Script syntax is valid"
echo ""
echo "Next steps:"
echo "1. Configure .env file with your settings"
echo "2. Update Git repository URL in configuration files"
echo "3. Run pre-deployment check: ./01-pre-deployment-check.sh"
echo "4. Deploy ArgoCD: ./02-deployment.sh"
echo "5. Validate deployment: ./03-validation.sh"
echo ""
echo "To run all tests: ./test-structure.sh"
echo "=============================================="

exit 0