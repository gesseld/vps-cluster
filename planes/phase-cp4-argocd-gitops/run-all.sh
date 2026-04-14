#!/bin/bash

# ArgoCD GitOps Controller - Complete Deployment Script
# Runs all steps: pre-deployment check, deployment, and validation

set -e

echo "=============================================="
echo "ArgoCD GitOps Controller - Complete Deployment"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function for colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_color $RED "❌ ERROR: $1 is not installed or not in PATH"
        return 1
    fi
}

# Function to run step with error handling
run_step() {
    local step_name=$1
    local script_name=$2
    
    print_color $BLUE "=============================================="
    print_color $BLUE "Step: $step_name"
    print_color $BLUE "Script: $script_name"
    print_color $BLUE "=============================================="
    
    if [ -f "$script_name" ]; then
        if [ -x "$script_name" ]; then
            print_color $YELLOW "Running $script_name..."
            echo ""
            
            # Run the script
            if ./$script_name; then
                print_color $GREEN "✅ $step_name completed successfully"
                echo ""
                return 0
            else
                print_color $RED "❌ $step_name failed with exit code $?"
                echo ""
                return 1
            fi
        else
            print_color $YELLOW "Making $script_name executable..."
            chmod +x $script_name
            
            if ./$script_name; then
                print_color $GREEN "✅ $step_name completed successfully"
                echo ""
                return 0
            else
                print_color $RED "❌ $step_name failed with exit code $?"
                echo ""
                return 1
            fi
        fi
    else
        print_color $RED "❌ ERROR: Script not found: $script_name"
        return 1
    fi
}

# Function to ask for confirmation
ask_confirmation() {
    local message=$1
    
    print_color $YELLOW "$message"
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_color $RED "Operation cancelled by user"
        exit 1
    fi
}

# Function to check environment
check_environment() {
    print_color $BLUE "=============================================="
    print_color $BLUE "Environment Check"
    print_color $BLUE "=============================================="
    
    # Check required commands
    print_color $YELLOW "Checking required commands..."
    REQUIRED_COMMANDS=("kubectl" "helm")
    
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        check_command $cmd
        if [ $? -eq 0 ]; then
            print_color $GREEN "✅ $cmd is available"
        fi
    done
    echo ""
    
    # Check Kubernetes access
    print_color $YELLOW "Checking Kubernetes cluster access..."
    if kubectl cluster-info &> /dev/null; then
        print_color $GREEN "✅ Kubernetes cluster is accessible"
        
        # Get cluster info
        CLUSTER_NAME=$(kubectl config current-context)
        print_color $YELLOW "  Cluster context: $CLUSTER_NAME"
        
        # Check nodes
        NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        print_color $YELLOW "  Number of nodes: $NODE_COUNT"
    else
        print_color $RED "❌ ERROR: Cannot connect to Kubernetes cluster"
        exit 1
    fi
    echo ""
    
    # Check .env file
    print_color $YELLOW "Checking environment configuration..."
    if [ -f ".env" ]; then
        print_color $GREEN "✅ .env file found"
        
        # Load .env file
        source .env
        
        # Check required variables
        REQUIRED_VARS=("ARGOCD_NAMESPACE" "ARGOCD_VERSION" "GIT_REPO_URL")
        for var in "${REQUIRED_VARS[@]}"; do
            if [ -z "${!var}" ]; then
                print_color $RED "❌ ERROR: Required variable not set: $var"
                exit 1
            else
                print_color $GREEN "✅ $var is set"
            fi
        done
    else
        print_color $YELLOW "⚠️  .env file not found"
        
        if [ -f ".env.example" ]; then
            print_color $YELLOW "  Found .env.example file"
            ask_confirmation "Please create .env file from .env.example and configure it before continuing."
        else
            print_color $RED "❌ ERROR: No .env or .env.example file found"
            exit 1
        fi
    fi
    echo ""
}

# Main execution
main() {
    # Check environment first
    check_environment
    
    # Ask for confirmation
    ask_confirmation "This will deploy ArgoCD GitOps Controller with the following configuration:
    - Namespace: ${ARGOCD_NAMESPACE:-argocd}
    - Version: ${ARGOCD_VERSION:-2.9.0}
    - Git Repository: ${GIT_REPO_URL:-not set}
    - Single replica mode (non-HA)
    - Resource quota: 512MB memory limit
    - Parallelism limit: 5 concurrent operations"
    
    # Step 1: Test structure
    if ! run_step "Structure Test" "test-structure.sh"; then
        print_color $RED "❌ Structure test failed. Please fix the issues before continuing."
        exit 1
    fi
    
    # Step 2: Pre-deployment check
    if ! run_step "Pre-deployment Check" "01-pre-deployment-check.sh"; then
        print_color $RED "❌ Pre-deployment check failed. Please fix the issues before continuing."
        exit 1
    fi
    
    # Ask for confirmation before deployment
    ask_confirmation "Pre-deployment check passed. Ready to deploy ArgoCD GitOps Controller?"
    
    # Step 3: Deployment
    if ! run_step "Deployment" "02-deployment.sh"; then
        print_color $RED "❌ Deployment failed. Check the logs for errors."
        exit 1
    fi
    
    # Wait for deployment to stabilize
    print_color $YELLOW "Waiting 30 seconds for ArgoCD to stabilize..."
    sleep 30
    echo ""
    
    # Step 4: Validation
    if ! run_step "Validation" "03-validation.sh"; then
        print_color $RED "❌ Validation failed. Check the deployment and fix any issues."
        exit 1
    fi
    
    # Final summary
    print_color $BLUE "=============================================="
    print_color $GREEN "✅ ArgoCD GitOps Controller Deployment Complete!"
    print_color $BLUE "=============================================="
    echo ""
    
    print_color $YELLOW "Summary:"
    print_color $GREEN "  ✅ Structure test passed"
    print_color $GREEN "  ✅ Pre-deployment check passed"
    print_color $GREEN "  ✅ Deployment completed"
    print_color $GREEN "  ✅ Validation passed"
    echo ""
    
    print_color $YELLOW "ArgoCD Configuration:"
    print_color $BLUE "  Namespace: ${ARGOCD_NAMESPACE:-argocd}"
    print_color $BLUE "  Version: ${ARGOCD_VERSION:-2.9.0}"
    print_color $BLUE "  Git Repository: ${GIT_REPO_URL:-not set}"
    print_color $BLUE "  Single replica mode (non-HA)"
    print_color $BLUE "  Resource quota: 512MB memory limit"
    print_color $BLUE "  Parallelism limit: 5 concurrent operations"
    echo ""
    
    print_color $YELLOW "Access Instructions:"
    print_color $BLUE "  1. Get admin password:"
    print_color $BLUE "     kubectl -n ${ARGOCD_NAMESPACE:-argocd} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    echo ""
    print_color $BLUE "  2. Port forward for local access:"
    print_color $BLUE "     kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE:-argocd} 8080:443"
    echo ""
    print_color $BLUE "  3. Access UI at: https://localhost:8080"
    print_color $BLUE "     Username: admin"
    print_color $BLUE "     Password: [from step 1]"
    echo ""
    
    print_color $YELLOW "Next Steps:"
    print_color $BLUE "  1. Change the admin password immediately"
    print_color $BLUE "  2. Configure webhook in your Git repository"
    print_color $BLUE "  3. Test drift detection functionality"
    print_color $BLUE "  4. Monitor resource usage"
    echo ""
    
    print_color $YELLOW "Webhook Configuration:"
    print_color $BLUE "  URL: https://[argocd-server]:[port]/api/webhook"
    print_color $BLUE "  Content-Type: application/json"
    print_color $BLUE "  Secret: [configure in argocd-cm.yaml]"
    echo ""
    
    print_color $GREEN "✅ All tasks completed successfully!"
    print_color $BLUE "=============================================="
}

# Run main function
main

exit 0