# ArgoCD GitOps Controller Phase CP-4: Declarative Deployment with Drift Detection

## Objective
Deploy ArgoCD v2.9+ as a GitOps controller for declarative deployment with drift detection and API server protection.

## Architecture
- **ArgoCD v2.9+**: Single replica (non-HA mode for resource constraints)
- **ApplicationSets**: 5-plane structure for automated deployment
- **Sync Policy**: Automated sync with pruning (remove resources not in Git)
- **Webhook Triggers**: GitHub/GitLab webhook → ArgoCD API integration
- **Polling Disabled**: Save CPU cycles by disabling polling
- **Resource Quotas**: 512MB memory limit for ArgoCD namespace
- **API Protection**: Respect Kyverno rate limits with `--kubectl-parallelism-limit=5`

## 5-Plane ApplicationSet Structure
1. **Control Plane ApplicationSet**: `control-plane-appset.yaml`
   - Deploys control plane components (API server, scheduler, etc.)
   
2. **Data Plane ApplicationSet**: `data-plane-appset.yaml`
   - Deploys data plane services (databases, caches, message queues)
   
3. **Observability Plane ApplicationSet**: `observability-plane-appset.yaml`
   - Deploys monitoring, logging, and tracing components
   
4. **Security Plane ApplicationSet**: `security-plane-appset.yaml`
   - Deploys security policies, RBAC, network policies
   
5. **AI Plane ApplicationSet**: `ai-plane-appset.yaml`
   - Deploys AI/ML inference services and models

## Prerequisites
1. Kubernetes cluster with kubectl access
2. Git repository with 5-plane structure
3. Git credentials (SSH key or token)
4. Kyverno installed for rate limiting protection
5. Network policies allowing webhook access

## Deployment Steps

### 1. Pre-deployment Check
```bash
./01-pre-deployment-check.sh
```
Validates cluster access, Git repository, existing resources, and configuration.

### 2. Deployment
```bash
./02-deployment.sh
```
Deploys all components:
- ArgoCD namespace and resource quotas
- ArgoCD installation (non-HA, single replica)
- Git repository secret
- ConfigMap with parallelism limits
- ApplicationSets for 5-plane structure

### 3. Validation
```bash
./03-validation.sh
```
Validates the deployment:
- ArgoCD pod and service status
- ApplicationSet synchronization
- Drift detection functionality
- Webhook configuration
- Resource quota enforcement
- Parallelism limit configuration

## Configuration

### Environment Variables
Create `.env` file or set variables:
```bash
export ARGOCD_NAMESPACE=argocd
export ARGOCD_VERSION=2.9.0
export GIT_REPO_URL=git@github.com:your-org/your-repo.git
export GIT_BRANCH=main
export GIT_PATH=manifests
```

### ArgoCD Configuration (`control-plane/argocd/argocd-cm.yaml`)
- Disable polling: `reposerver.parallelism.limit: 0`
- Enable webhook triggers
- Set kubectl parallelism limit: `kubectl.parallelism.limit: 5`
- Configure automated sync with pruning

### Components

#### 1. ArgoCD Installation (`control-plane/argocd/kustomization.yaml`)
- ArgoCD v2.9+ via official Helm chart
- Single replica (non-HA)
- Resource limits: 512MB RAM, 500m CPU
- Disabled polling
- Webhook server enabled

#### 2. Git Repository Secret (`control-plane/argocd/repository-secret.yaml`)
- SSH private key or token for Git authentication
- Encrypted with SealedSecrets or external-secrets

#### 3. Resource Quota (`control-plane/argocd/resource-quota.yaml`)
- Memory limit: 512MB
- CPU limit: 1000m
- Pod limit: 5

#### 4. ApplicationSets (`control-plane/argocd/applicationsets/`)
- 5 ApplicationSets for each plane
- Automated sync with pruning
- Webhook triggers for Git events
- Cluster destination configuration

## Validation Tests

### ArgoCD Status Validation
```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Check ArgoCD server status
argocd admin dashboard

# Check ApplicationSets
kubectl get applicationsets -n argocd
```

### Drift Detection Test
```bash
# Manually modify a deployed resource
kubectl patch deployment <deployment> -n <namespace> --type='json' -p='[{"op": "replace", "path": "/spec/replicas", "value": 3}]'

# Wait 60 seconds and check ArgoCD UI for "OutOfSync" status
```

### Webhook Test
```bash
# Simulate webhook payload
curl -X POST http://argocd-server.argocd.svc.cluster.local:8080/api/webhook \
  -H "Content-Type: application/json" \
  -d '{"ref": "refs/heads/main", "repository": {"url": "git@github.com:your-org/your-repo.git"}}'
```

### Rate Limit Protection Test
```bash
# Attempt burst sync (should be throttled by Kyverno)
for i in {1..10}; do
  argocd app sync <app-name> &
done
```

## API Protection Configuration

### Kyverno Rate Limit Policy
ArgoCD respects Kyverno rate limits through:
1. `--kubectl-parallelism-limit=5` in argocd-cm.yaml
2. Kyverno `rate-limit-admission` policy
3. Resource quotas for memory protection

### Parallelism Limits
- **kubectl operations**: 5 concurrent operations max
- **Repository operations**: Polling disabled (0)
- **Sync operations**: Webhook-triggered only

## Memory Management

### Resource Quotas
- **Memory**: 512MB limit (prevents OOM crashes)
- **CPU**: 1000m limit (prevents CPU exhaustion)
- **Pods**: 5 max (single replica + sidecars)

### Alert Thresholds
- **Warning**: >400MB memory usage
- **Critical**: >480MB memory usage
- Alert triggers after 2 minutes of sustained high usage

## Performance Considerations

### Polling Disabled
- Saves CPU cycles by disabling repository polling
- Relies on webhook triggers for updates
- Reduces cluster API server load

### Webhook Advantages
- Immediate synchronization on Git changes
- Reduced latency compared to polling
- Event-driven architecture

### Single Replica Mode
- Suitable for resource-constrained environments
- Reduces memory footprint
- Simplified deployment and management

## Troubleshooting

### ArgoCD Not Starting
1. Check resource limits: `kubectl describe pod -n argocd`
2. Check Git credentials: `kubectl get secret -n argocd argocd-repo-secret`
3. Check network policies: `kubectl get networkpolicies -n argocd`

### ApplicationSync Issues
1. Check Git repository access: `argocd repo list`
2. Check ApplicationSet status: `kubectl describe applicationset -n argocd`
3. Check sync logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server`

### Webhook Not Triggering
1. Check webhook server: `kubectl get service -n argocd argocd-server`
2. Check ingress/network policies
3. Verify webhook payload format

### High Memory Usage
1. Check resource usage: `kubectl top pods -n argocd`
2. Check for memory leaks in logs
3. Consider increasing memory limit if needed

## Cleanup
```bash
# Delete all ArgoCD resources
kubectl delete -f control-plane/argocd/
kubectl delete namespace argocd --wait=false
```

## Deliverables Checklist
- [ ] `control-plane/argocd/kustomization.yaml`
- [ ] `control-plane/argocd/applicationsets/control-plane.yaml`
- [ ] `control-plane/argocd/applicationsets/data-plane.yaml`
- [ ] `control-plane/argocd/applicationsets/observability-plane.yaml`
- [ ] `control-plane/argocd/applicationsets/security-plane.yaml`
- [ ] `control-plane/argocd/applicationsets/ai-plane.yaml`
- [ ] `control-plane/argocd/repository-secret.yaml`
- [ ] `control-plane/argocd/resource-quota.yaml`
- [ ] `control-plane/argocd/argocd-cm.yaml`
- [ ] Pre-deployment script (`01-pre-deployment-check.sh`)
- [ ] Deployment script (`02-deployment.sh`)
- [ ] Validation script (`03-validation.sh`)

## Validation Requirements Met
- [ ] Manual deployment change → ArgoCD UI shows "OutOfSync" within 60 seconds
- [ ] Burst sync attempts throttled by Kyverno rate-limit-admission policy
- [ ] ApplicationSets created for all 5 planes
- [ ] Resource quota enforced (512MB limit)
- [ ] Polling disabled, webhooks enabled
- [ ] Parallelism limit configured (kubectl.parallelism.limit: 5)