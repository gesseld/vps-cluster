# ArgoCD GitOps Controller - Quick Deployment Guide

## Quick Start

### 1. Clone and Configure
```bash
# Navigate to the phase directory
cd planes/phase-cp4-argocd-gitops

# Copy environment template
cp .env.example .env

# Edit .env with your configuration
nano .env  # or use your preferred editor
```

### 2. Update Required Variables in `.env`
```bash
# Required variables
export ARGOCD_NAMESPACE=argocd
export ARGOCD_VERSION=2.9.0
export GIT_REPO_URL=git@github.com:your-org/your-repo.git
export GIT_BRANCH=main
export GIT_PATH=manifests

# Optional: For HTTPS repositories
# export GIT_USERNAME=your-username
# export GIT_PASSWORD=your-token
```

### 3. Update Git Repository URLs
Update the following files with your Git repository URL:
- `control-plane/argocd/kustomization.yaml` (line 47)
- `control-plane/argocd/argocd-cm.yaml` (line 17, 21)
- All ApplicationSet files in `control-plane/argocd/applicationsets/`

### 4. Run Complete Deployment
```bash
# Run the complete pipeline
./run-all.sh
```

## Alternative: Step-by-Step Deployment

### Step 1: Test Structure
```bash
./test-structure.sh
```

### Step 2: Pre-deployment Check
```bash
./01-pre-deployment-check.sh
```

### Step 3: Deploy ArgoCD
```bash
./02-deployment.sh
```

### Step 4: Validate Deployment
```bash
./03-validation.sh
```

## Access ArgoCD UI

### 1. Get Admin Password
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

### 2. Port Forward for Local Access
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 3. Access UI
- URL: https://localhost:8080
- Username: `admin`
- Password: [from step 1]

## Webhook Configuration

### GitHub Webhook
1. Go to your repository → Settings → Webhooks
2. Add webhook:
   - Payload URL: `https://[argocd-server]:[port]/api/webhook`
   - Content type: `application/json`
   - Secret: [from `argocd-cm.yaml` webhook.github.secret]
   - Events: `Push` and `Pull request`

### GitLab Webhook
1. Go to your project → Settings → Webhooks
2. Add webhook:
   - URL: `https://[argocd-server]:[port]/api/webhook`
   - Secret token: [from `argocd-cm.yaml` webhook.gitlab.secret]
   - Trigger: `Push events` and `Merge request events`

## Testing Drift Detection

### 1. Create Test Application
```bash
# Create a test deployment
kubectl create deployment test-app --image=nginx:1.21 -n default

# Create Application in ArgoCD pointing to this deployment
# (Configure via ArgoCD UI or CLI)
```

### 2. Modify Deployment
```bash
# Change replicas from 1 to 3
kubectl patch deployment test-app -n default \
  --type='json' -p='[{"op": "replace", "path": "/spec/replicas", "value": 3}]'
```

### 3. Verify Drift Detection
- Wait 60 seconds
- Check ArgoCD UI for "OutOfSync" status
- ArgoCD should automatically revert to 1 replica (if auto-sync enabled)

## Monitoring

### Check Resource Usage
```bash
# Check pod resource usage
kubectl top pods -n argocd

# Check resource quota usage
kubectl describe resourcequota argocd-resource-quota -n argocd
```

### Check Application Status
```bash
# List all applications
argocd app list

# Get application details
argocd app get <app-name>

# Check sync status
argocd app sync-status <app-name>
```

## Troubleshooting

### Common Issues

#### 1. ArgoCD Pods Not Starting
```bash
# Check pod status
kubectl get pods -n argocd

# Check pod logs
kubectl logs -n argocd deploy/argocd-server

# Check events
kubectl get events -n argocd
```

#### 2. Git Repository Connection Issues
```bash
# Check repository connection
argocd repo list

# Test repository access
argocd repo add <repo-url> --username <user> --password <token>
```

#### 3. Sync Failures
```bash
# Check sync operation logs
argocd app get <app-name> --operation

# Check application events
argocd app get <app-name> --events
```

## Cleanup

### Remove ArgoCD
```bash
# Delete all ArgoCD resources
kubectl delete -f control-plane/argocd/

# Delete namespace (optional)
kubectl delete namespace argocd
```

### Remove Test Resources
```bash
# Remove test deployment
kubectl delete deployment test-app -n default
```

## Support

### Documentation
- `README.md` - Comprehensive documentation
- `IMPLEMENTATION_SUMMARY.md` - Implementation details
- This guide - Quick deployment reference

### Scripts
- `run-all.sh` - Complete deployment pipeline
- Individual scripts for each phase
- Validation and testing scripts

### Configuration
- `.env.example` - Environment variable template
- YAML files in `control-plane/argocd/`
- ApplicationSets for 5-plane structure