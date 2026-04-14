# VPS Deployment Guide for Task DP-3

## Overview
This guide explains how to deploy Task DP-3 (Hetzner Object Storage) on your VPS. The scripts are designed to run on the VPS where your Kubernetes cluster is deployed.

## Prerequisites on VPS

### 1. Install Required Tools
```bash
# Update package list
sudo apt-get update

# Install required tools
sudo apt-get install -y curl jq

# Install kubectl (if not already installed)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install mc (MinIO Client)
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Install AWS CLI (alternative for S3 operations)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### 2. Verify Kubernetes Access
```bash
# Test kubectl access
kubectl cluster-info
kubectl get nodes

# Verify namespaces exist
kubectl get namespace data-plane
kubectl get namespace observability-plane
```

### 3. Check Cluster Components
```bash
# Check External Secrets Operator
kubectl get crd externalsecrets.external-secrets.io
kubectl get pods -n external-secrets

# Check Cilium CNI
kubectl get pods -n kube-system -l k8s-app=cilium
```

## Deployment Steps

### 1. Transfer Files to VPS
```bash
# From your local machine, copy files to VPS
scp -r planes/phase-dp3-hetzner-s3/ user@your-vps-ip:/home/user/
scp .env user@your-vps-ip:/home/user/
```

### 2. On VPS: Set Up Environment
```bash
# Navigate to the phase directory
cd /home/user/phase-dp3-hetzner-s3

# Make scripts executable
chmod +x *.sh

# Verify .env file
cat ../.env | grep HETZNER
# Should show:
# HETZNER_S3_ENDPOINT=https://fsn1.your-objectstorage.com
# HETZNER_S3_ACCESS_KEY=YAGEW4STIWFXRWQUS8L8
# HETZNER_S3_SECRET_KEY=1oNMJluHotAFfoBuZhsTf352uWYlOAMiM3GlbHES
```

### 3. Test Credentials (Optional)
```bash
# Test S3 connectivity
./test-credentials.sh

# If mc is not installed, install it first:
# wget https://dl.min.io/client/mc/release/linux-amd64/mc
# chmod +x mc
# sudo mv mc /usr/local/bin/
```

### 4. Run Pre-deployment Check
```bash
./01-pre-deployment-check.sh
```

### 5. Deploy S3 Storage
```bash
./02-deployment.sh
```

### 6. Validate Deployment
```bash
./03-validation.sh
```

## Verification Commands

### Check Deployment Status
```bash
# Check replicator pod
kubectl get pods -n data-plane -l app=s3-replicator

# Check logs
kubectl logs -n data-plane -l app=s3-replicator -c replicator --tail=20

# Check services
kubectl get services -n data-plane -l app=hetzner-s3

# Check secrets
kubectl get secrets -n data-plane -l app=hetzner-s3
```

### Test S3 Connectivity from VPS
```bash
# Configure mc alias
mc alias set hetzner https://fsn1.your-objectstorage.com YAGEW4STIWFXRWQUS8L8 1oNMJluHotAFfoBuZhsTf352uWYlOAMiM3GlbHES --api s3v4 --path off

# List buckets
mc ls hetzner/

# Test upload/download
echo "test" | mc pipe hetzner/documents-processed/test.txt
mc cat hetzner/documents-processed/test.txt
mc rm hetzner/documents-processed/test.txt
```

## Troubleshooting

### Common Issues

#### 1. kubectl not configured
```bash
# Check kubeconfig
ls -la ~/.kube/config

# If missing, copy from master node or set KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

#### 2. External Secrets Operator not installed
```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

#### 3. Cilium not installed
```bash
# Check if Cilium is needed
kubectl get networkpolicies --all-namespaces

# If Cilium is required, install it
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --namespace kube-system
```

#### 4. Namespace doesn't exist
```bash
# Create required namespaces
kubectl create namespace data-plane
kubectl create namespace observability-plane
```

#### 5. Storage class not found
```bash
# List available storage classes
kubectl get storageclass

# If using Hetzner, install CSI driver
helm repo add hcloud https://charts.hetzner.cloud
helm install hcloud-csi hcloud/hcloud-csi \
  -n kube-system \
  --set secret.token=YOUR_HETZNER_API_TOKEN
```

## Post-Deployment Tasks

### 1. Monitor Deployment
```bash
# Watch pod status
kubectl get pods -n data-plane -l app=s3-replicator -w

# Check events
kubectl get events -n data-plane --field-selector involvedObject.name=s3-replicator
```

### 2. Verify Metrics
```bash
# Check metrics exporter
kubectl logs -n data-plane -l app=s3-replicator -c metrics-exporter --tail=10

# Check metrics file
kubectl exec -n data-plane -l app=s3-replicator -c metrics-exporter -- cat /metrics/s3_metrics.prom | head -5
```

### 3. Test Failover Readiness (Optional)
```bash
# Test pod restart
kubectl delete pod -n data-plane -l app=s3-replicator

# Verify recovery
kubectl get pods -n data-plane -l app=s3-replicator
```

## Cost Monitoring

### Check S3 Usage
```bash
# Install and configure awscli for Hetzner
aws configure set aws_access_key_id YAGEW4STIWFXRWQUS8L8
aws configure set aws_secret_access_key 1oNMJluHotAFfoBuZhsTf352uWYlOAMiM3GlbHES
aws configure set default.region fsn1
aws configure set default.s3.endpoint_url https://fsn1.your-objectstorage.com

# Check bucket sizes
aws s3 ls --summarize --human-readable --recursive s3://documents-processed/
```

## Security Notes

### 1. Credential Security
- Never commit `.env` file to git
- Use External Secrets Operator in production
- Rotate credentials regularly (30-day rotation configured)

### 2. Network Security
- Cilium FQDN policies restrict egress
- DNS refresher maintains cache to prevent drops
- Zero-trust model with explicit allow lists

### 3. Compliance
- WORM (Write-Once-Read-Many) enabled on documents-processed
- 7-day retention for compliance
- Heartbeat objects auto-expire after 1 day

## Next Steps

After successful deployment:

1. **Integrate with applications**: Update app configurations to use `s3-endpoint.data-plane.svc.cluster.local`
2. **Set up monitoring**: Configure Grafana dashboards for S3 metrics
3. **Test backup systems**: Ensure backups work with new S3 storage
4. **Plan replication**: Add replication target credentials when ready
5. **Schedule maintenance**: Regular credential rotation and compliance checks

## Support

If you encounter issues:

1. Check logs: `kubectl logs -n data-plane -l app=s3-replicator`
2. Verify credentials: `./test-credentials.sh`
3. Check cluster health: `kubectl get nodes`
4. Review network policies: `kubectl get ciliumnetworkpolicies -n data-plane`

Remember: The deployment is designed to be resilient with atomic health checks, memory-safe buffers, and proper process supervision.