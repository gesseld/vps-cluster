#!/bin/bash
# Temporal HA Data Plane - Structure Validation Script
# Validates all files exist and have correct permissions

set -e

echo "================================================"
echo "🔍 TEMPORAL HA DATA PLANE - STRUCTURE VALIDATION"
echo "================================================"
echo "Phase: DP-5 (Data Plane Temporal HA)"
echo "Date: $(date)"
echo "================================================"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
total_files=0
passed_files=0
failed_files=0
warnings=0

# Function to check file
check_file() {
    local file="$1"
    local description="$2"
    local required="${3:-true}"
    
    ((total_files++))
    
    if [ -f "$file" ]; then
        if [ -x "$file" ] && [[ "$file" == *.sh ]]; then
            echo -e "${GREEN}✅ PASS${NC}: $description ($file) - exists and executable"
            ((passed_files++))
        elif [ -r "$file" ]; then
            echo -e "${GREEN}✅ PASS${NC}: $description ($file) - exists and readable"
            ((passed_files++))
        else
            echo -e "${RED}❌ FAIL${NC}: $description ($file) - exists but not readable"
            ((failed_files++))
        fi
    else
        if [ "$required" = "true" ]; then
            echo -e "${RED}❌ FAIL${NC}: $description ($file) - missing (required)"
            ((failed_files++))
        else
            echo -e "${YELLOW}⚠️  WARN${NC}: $description ($file) - missing (optional)"
            ((warnings++))
        fi
    fi
}

# Function to check directory
check_dir() {
    local dir="$1"
    local description="$2"
    local required="${3:-true}"
    
    ((total_files++))
    
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✅ PASS${NC}: $description ($dir) - exists"
        ((passed_files++))
    else
        if [ "$required" = "true" ]; then
            echo -e "${RED}❌ FAIL${NC}: $description ($dir) - missing (required)"
            ((failed_files++))
        else
            echo -e "${YELLOW}⚠️  WARN${NC}: $description ($dir) - missing (optional)"
            ((warnings++))
        fi
    fi
}

echo ""
echo "📁 Checking directory structure..."
echo "---------------------------------"

# Check main directories
check_dir "." "Current directory" true
check_dir "scripts" "Scripts directory" true
check_dir "manifests" "Manifests directory" true
check_dir "deliverables" "Deliverables directory" false
check_dir "logs" "Logs directory" false

echo ""
echo "📄 Checking script files..."
echo "--------------------------"

# Check script files
check_file "scripts/01-pre-deployment-check.sh" "Pre-deployment check script" true
check_file "scripts/02-deployment.sh" "Deployment script" true
check_file "scripts/03-validation.sh" "Validation script" true
check_file "run-all.sh" "Run-all script" true
check_file "test-structure.sh" "Test structure script" true

echo ""
echo "📋 Checking manifest files..."
echo "----------------------------"

# Check manifest files
check_file "manifests/postgres-values-hetzner.yaml" "PostgreSQL values file" true
check_file "manifests/pgbouncer-deployment.yaml" "PgBouncer deployment file" true
check_file "manifests/temporal-ha-hetzner-values.yaml" "Temporal values file" true
check_file "manifests/temporal-grpc-ingress.yaml" "gRPC ingress file" true
check_file "manifests/temporal-web-ingress.yaml" "Web UI ingress file" true

echo ""
echo "📚 Checking documentation files..."
echo "---------------------------------"

# Check documentation files
check_file "README.md" "README documentation" true
check_file "IMPLEMENTATION_SUMMARY.md" "Implementation summary" true

echo ""
echo "🔧 Checking script syntax..."
echo "---------------------------"

# Check script syntax
echo "Checking bash script syntax..."
for script in scripts/*.sh run-all.sh test-structure.sh; do
    if [ -f "$script" ]; then
        if bash -n "$script" 2>/dev/null; then
            echo -e "${GREEN}✅ PASS${NC}: $script - valid bash syntax"
        else
            echo -e "${RED}❌ FAIL${NC}: $script - invalid bash syntax"
            ((failed_files++))
        fi
    fi
done

echo ""
echo "📊 Checking YAML syntax..."
echo "-------------------------"

# Check YAML syntax (basic check)
echo "Checking YAML file structure..."
for yaml in manifests/*.yaml; do
    if [ -f "$yaml" ]; then
        if grep -q "apiVersion:" "$yaml" && grep -q "kind:" "$yaml"; then
            echo -e "${GREEN}✅ PASS${NC}: $yaml - appears to be valid YAML"
        else
            # For values files, check if they have key-value structure
            if [[ "$yaml" == *values* ]]; then
                if grep -q ":" "$yaml"; then
                    echo -e "${GREEN}✅ PASS${NC}: $yaml - appears to be valid YAML values"
                else
                    echo -e "${YELLOW}⚠️  WARN${NC}: $yaml - may not be valid YAML"
                    ((warnings++))
                fi
            else
                echo -e "${YELLOW}⚠️  WARN${NC}: $yaml - may not be valid Kubernetes YAML"
                ((warnings++))
            fi
        fi
    fi
done

echo ""
echo "================================================"
echo "📊 VALIDATION SUMMARY"
echo "================================================"
echo "Total files checked: $total_files"
echo -e "${GREEN}Passed: $passed_files${NC}"
echo -e "${RED}Failed: $failed_files${NC}"
if [ $warnings -gt 0 ]; then
    echo -e "${YELLOW}Warnings: $warnings${NC}"
fi

echo ""
if [ $failed_files -eq 0 ]; then
    echo -e "${GREEN}🎉 All required files are present and valid!${NC}"
    echo "The deployment structure is ready for execution."
    
    echo ""
    echo "📝 Next steps:"
    echo "1. Update domain names in manifests/temporal-*-ingress.yaml"
    echo "2. Change default passwords for production security"
    echo "3. Run ./run-all.sh to deploy Temporal HA"
    
    exit 0
else
    echo -e "${RED}❌ Some required files are missing or invalid.${NC}"
    echo "Please fix the issues above before proceeding."
    exit 1
fi