# VPS Deployment Guide for Temporal HA Data Plane

## Overview
This guide explains how to deploy Temporal HA on the VPS cluster using WSL (Windows Subsystem for Linux).

## Prerequisites

### 1. WSL Setup
- Windows Subsystem for Linux (WSL) installed
- Ubuntu or Debian distribution recommended
- SSH client installed (`sudo apt install openssh-client`)

### 2. SSH Access to VPS
- SSH private key: `C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key`
- SSH public key: `C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key.pub`
- VPS IP: `49.12.37.154`

### 3. Required Tools on VPS
- kubectl (Kubernetes CLI)
- helm (Helm package manager)
- git (for cloning repository)

## Deployment Steps

### Step 1: Connect to VPS via WSL

```bash
# Copy SSH key to WSL
cp /mnt/c/Users/Daniel/Documents/k3s\ code\ v2/hetzner-cli-key ~/.ssh/
chmod 600 ~/.ssh/hetzner-cli-key

# Connect to VPS
ssh -i ~/.ssh/hetzner-cli-key root@49.12.37.154
```

### Step 2: Clone Repository on VPS

```bash
# Clone the repository
git clone https://github.com/gesseld/vps-cluster.git
cd vps-cluster

# Navigate to Temporal HA directory
cd planes/phase-dp5-temporal
```

### Step 3: Verify Cluster Access

```bash
# Check k3s cluster status
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
```

### Step 4: Run Deployment Scripts

```bash
# Option A: Run individual scripts
cd scripts
./01-pre-deployment-check.sh
./02-deployment.sh
./03-validation.sh

# Option B: Use run-all script (from phase-dp5-temporal directory)
./run-all.sh
```

## Expected Deployment Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| Pre-deployment check | 2-3 minutes | Verifies prerequisites |
| PostgreSQL deployment | 5-7 minutes | Deploys PostgreSQL 15 with HA |
| PgBouncer deployment | 2-3 minutes | Deploys connection pooling |
| Temporal deployment | 5-7 minutes | Deploys Temporal HA stack |
| Validation | 3-5 minutes | Runs comprehensive tests |
| **Total** | **15-25 minutes** | Complete deployment |

## Access Points After Deployment

### Internal Services
- **Temporal gRPC**: `temporal-frontend.temporal-system.svc.cluster.local:7233`
- **Temporal Web UI**: `temporal-web.temporal-system.svc.cluster.local:8088`
- **PostgreSQL**: `postgresql-postgresql.temporal-system.svc.cluster.local:5432`
- **PgBouncer**: `pgbouncer-temporal.temporal-system.svc.cluster.local:5432`

### External Access (via VPS IP)
- **Temporal gRPC**: `http://49.12.37.154/temporal`
- **Temporal Web UI**: `http://49.12.37.154/temporal-ui`

## Verification

### Quick Health Check
```bash
# Check all pods
kubectl get pods -n temporal-system

# Check services
kubectl get svc -n temporal-system

# Test PostgreSQL connectivity
kubectl run pg-test --image=postgres:15 -it --rm --restart=Never -n temporal-system -- psql "postgresql://temporal:temporaldbpassword@postgresql-postgresql.temporal-system.svc.cluster.local:5432/temporal" -c "\dt"

# Test Temporal gRPC
kubectl run temporal-test --image=curlimages/curl -it --rm --restart=Never -n temporal-system -- curl -v http://temporal-frontend:7233
```

### Comprehensive Validation
Run the full validation script:
```bash
./03-validation.sh
```

## Troubleshooting

### Common Issues

#### 1. SSH Connection Failed
```bash
# Check SSH key permissions
chmod 600 ~/.ssh/hetzner-cli-key

# Test connection
ssh -i ~/.ssh/hetzner-cli-key -v root@49.12.37.154
```

#### 2. kubectl Not Configured
```bash
# Check k3s kubeconfig
ls -la /etc/rancher/k3s/k3s.yaml

# Set KUBECONFIG environment variable
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

#### 3. Helm Not Installed
```bash
# Install helm on VPS
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

#### 4. Resource Constraints
```bash
# Check available resources
kubectl describe nodes

# Check pod resource usage
kubectl top pods -A
```

### Deployment Failures

#### PostgreSQL Pod Pending
```bash
# Check events
kubectl describe pod -n temporal-system -l app.kubernetes.io/name=postgresql

# Check storage class
kubectl get storageclass
kubectl get pvc -n temporal-system
```

#### Temporal Pods Not Ready
```bash
# Check logs
kubectl logs -n temporal-system deployment/temporal-frontend
kubectl logs -n temporal-system deployment/temporal-history

# Check database connectivity
kubectl exec -n temporal-system deployment/temporal-frontend -- temporal cluster health
```

## Post-Deployment Tasks

### 1. Change Default Passwords
```bash
# Generate new passwords
openssl rand -base64 32  # PostgreSQL password
openssl rand -base64 32  # Temporal password

# Update in manifests (if needed)
# Note: Passwords are generated as Kubernetes Secrets during deployment
# To change them, delete and recreate the secrets
```

### 2. Configure TLS (Recommended)
```bash
# Install cert-manager (if not already installed)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

# Update ingress manifests to use TLS
# Edit manifests/temporal-grpc-ingress.yaml and manifests/temporal-web-ingress.yaml
# Uncomment TLS section and configure certificates
```

### 3. Set Up Monitoring
```bash
# Install Prometheus stack (if not already installed)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack

# Configure Temporal metrics scraping
# Add Prometheus annotations to Temporal services
```

### 4. Configure Backups
```bash
# Install Velero for backups (if not already installed)
# Configure PostgreSQL backups
# Configure Temporal workflow backups
```

## Resource Monitoring

### Expected Resource Usage
| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|-------------|-----------|----------------|--------------|
| PostgreSQL | 500m | 1000m | 512Mi | 1024Mi |
| PgBouncer | 100m | 200m | 128Mi | 256Mi |
| Temporal Frontend | 250m | 500m | 512Mi | 768Mi |
| Temporal History | 500m | 1000m | 768Mi | 1024Mi |
| Temporal Matching | 250m | 500m | 512Mi | 768Mi |
| Temporal Worker | 250m | 500m | 512Mi | 768Mi |
| **Total** | **1.85 vCPU** | **3.7 vCPU** | **2.94GB** | **4.61GB** |

### Monitoring Commands
```bash
# Check resource usage
kubectl top pods -n temporal-system
kubectl top nodes

# Check pod status
kubectl get pods -n temporal-system -w

# Check events
kubectl get events -n temporal-system --sort-by='.lastTimestamp'
```

## Rollback Procedure

If deployment fails, you can rollback:

```bash
# Delete all Temporal resources
kubectl delete namespace temporal-system

# Wait for cleanup
sleep 60

# Re-run deployment
./02-deployment.sh
```

## Support

### Logs Location
- Deployment logs: `logs/deployment-*.log`
- Validation logs: `logs/validation-*.log`
- Script logs: `logs/` directory

### Reports
- Deployment report: `deliverables/deployment-report-*.txt`
- Validation report: `deliverables/validation-report-*.txt`

### Issues
If you encounter issues:
1. Check logs in `logs/` directory
2. Review validation report
3. Check Kubernetes events: `kubectl get events -n temporal-system`
4. Verify resource availability: `kubectl describe nodes`

## Success Criteria

Deployment is successful when:
- All pods in `temporal-system` namespace are in `Running` state
- PostgreSQL connectivity test passes
- Temporal gRPC endpoint responds
- Temporal Web UI is accessible
- Validation script reports "VALIDATION PASSED"

## Next Steps

After successful deployment:
1. Integrate Temporal with Document Intelligence workflows
2. Set up monitoring dashboards
3. Configure alerting for critical issues
4. Test failover scenarios
5. Implement backup strategy
6. Performance tuning based on actual usage