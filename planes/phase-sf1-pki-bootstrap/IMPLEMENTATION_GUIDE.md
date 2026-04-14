# Phase SF-1: Implementation Guide

## Quick Start

### Prerequisites
1. Running k3s cluster with kubectl access
2. Helm installed (`helm` command available)
3. PostgreSQL deployed (in `postgresql` namespace) or plan to deploy it

### Deployment Steps

```bash
# 1. Navigate to the phase directory
cd planes/phase-sf1-pki-bootstrap

# 2. Run pre-deployment checks
./01-pre-deployment-check.sh

# 3. If checks pass, deploy the components
./02-deployment.sh

# 4. Validate the deployment
./03-validation.sh
```

## Detailed Implementation

### Step 1: Environment Setup

Create or update `.env` file in the parent directory:
```bash
# PostgreSQL connection details (required for SPIRE)
POSTGRES_PASSWORD=your_postgres_password
POSTGRES_HOST=postgresql.postgresql.svc
POSTGRES_PORT=5432
POSTGRES_DB=spire_db
POSTGRES_USER=spire

# SPIRE configuration
SPIRE_TRUST_DOMAIN=example.org
SPIRE_SVID_TTL=3600  # 1 hour in seconds

# Cert-Manager configuration
CERT_MANAGER_VERSION=v1.13.0
```

### Step 2: Pre-deployment Validation

The pre-deployment script checks:
- ✅ Kubernetes cluster connectivity
- ✅ Required tools (kubectl, helm, jq, curl)
- ✅ Helm repositories
- ✅ PostgreSQL availability (warning if not found)
- ✅ Node resources and labels
- ✅ Storage classes
- ✅ RBAC permissions

**Common issues and fixes:**

1. **Missing Helm repositories**:
   ```bash
   helm repo add jetstack https://charts.jetstack.io
   helm repo add spiffe https://spiffe.github.io/helm-charts/
   helm repo update
   ```

2. **PostgreSQL not found**:
   ```bash
   # Deploy PostgreSQL if needed
   helm repo add bitnami https://charts.bitnami.com/bitnami
   helm install postgresql bitnami/postgresql \
     --namespace postgresql \
     --create-namespace \
     --set auth.username=spire \
     --set auth.password=your_password \
     --set auth.database=spire_db
   ```

3. **Insufficient RBAC permissions**:
   ```bash
   # Ensure you have cluster-admin role
   kubectl create clusterrolebinding cluster-admin-binding \
     --clusterrole=cluster-admin \
     --user=$(kubectl config current-context)
   ```

### Step 3: Deployment Execution

The deployment script performs these actions sequentially:

#### 3.1 Namespace Creation
- `cert-manager`: For cert-manager components
- `spire`: For SPIRE server and agent
- `foundation`: For foundation workloads (optional)

#### 3.2 Cert-Manager Installation
- Installs cert-manager v1.13.0
- Creates CRDs automatically
- Sets up self-signed ClusterIssuer
- Creates CA certificate with 1-year validity

#### 3.3 SPIRE Server Deployment
- Creates ConfigMap with server configuration
- Sets up StatefulSet with PVC (1Gi storage)
- Configures PostgreSQL backend connection
- Enables `k8s_psat` node attestor
- Exposes metrics on port 9090

#### 3.4 SPIRE Agent Deployment
- Creates DaemonSet for all nodes
- Uses hostPID and hostNetwork for attestation
- Mounts `/tmp/spire-sockets` for workload access
- Configures `k8s` and `unix` workload attestors

#### 3.5 RBAC Configuration
- ServiceAccounts for server and agent
- ClusterRole for TokenReview
- ClusterRoleBinding for server permissions

#### 3.6 Registration Entries
- Pre-defined entries for foundation namespaces:
  - `default`
  - `kube-system`
  - `cert-manager`
  - `spire` (for agent identity)

#### 3.7 Fallback Configuration
- ConfigMap to toggle fallback mode
- When enabled, uses cert-manager TLS instead of SPIRE
- Controlled via annotation: `spire-fallback/enabled: "true"`

#### 3.8 Metrics and Monitoring
- Service for metrics exposure
- ServiceMonitor for Prometheus scraping
- Pre-configured alerts for:
  - High SVID issuance latency (>5s)
  - SPIRE server downtime
  - Missing SPIRE agents

#### 3.9 SDS Configuration
- ConfigMap with Envoy SDS configuration
- NGINX SDS configuration included
- Ready for mTLS integration

### Step 4: Post-deployment Validation

The validation script checks:

#### 4.1 File Deliverables
- All required YAML files exist
- ConfigMaps are created
- Secrets are properly configured

#### 4.2 Component Health
- Cert-Manager pods are running
- SPIRE server is ready
- SPIRE agents are running on all nodes
- Services are accessible

#### 4.3 Functionality Tests
- Certificate requests can be approved
- Agent socket is created within 5 seconds
- Metrics endpoint returns data
- SVID issuance latency metric exists

#### 4.4 Integration Readiness
- SDS configuration is valid
- Registration entries are applied
- Fallback mode can be toggled

## Customization Options

### Trust Domain
Edit `control-plane/spire/server-config.yaml`:
```yaml
trust_domain: "your-domain.org"
```

### SVID TTL
Edit registration entries in `control-plane/spire/entries.yaml`:
```yaml
ttl: 1800  # 30 minutes in seconds
```

### PostgreSQL Connection
Update `control-plane/spire/server-config.yaml`:
```yaml
connection_string: "host=your-postgres-host port=5432 user=your-user password=your-password dbname=your-db sslmode=disable"
```

### Storage Configuration
Modify `control-plane/spire/server.yaml`:
```yaml
volumeClaimTemplates:
- metadata:
    name: spire-data
  spec:
    accessModes: [ "ReadWriteOnce" ]
    storageClassName: "your-storage-class"  # Specify if needed
    resources:
      requests:
        storage: 2Gi  # Increase size if needed
```

## Testing the Deployment

### Test 1: Basic Connectivity
```bash
# Check all components are running
kubectl get pods -n cert-manager
kubectl get pods -n spire

# Check services
kubectl get svc -n spire
```

### Test 2: Certificate Issuance
```bash
# Create a test certificate request
cat > test-cert.yaml << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: default
spec:
  secretName: test-cert-tls
  duration: 2160h
  renewBefore: 360h
  commonName: test.example.com
  dnsNames:
  - test.example.com
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
EOF

kubectl apply -f test-cert.yaml
kubectl get certificaterequest -A
```

### Test 3: SPIRE Functionality
```bash
# Check SPIRE server health
kubectl exec -n spire deployment/spire-server -- curl http://localhost:8082/ready

# Check agent socket
kubectl exec -n spire $(kubectl get pods -n spire -l app=spire-agent -o name | head -1) -- ls -la /tmp/spire-sockets/

# Check metrics
kubectl port-forward -n spire svc/spire-server-metrics 9090:9090 &
curl http://localhost:9090/metrics | grep spire_
```

### Test 4: Workload Integration
```bash
# Create a test workload
cat > test-workload.yaml << EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-spire-workload
  namespace: default
spec:
  serviceAccountName: default
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: spire-sockets
      mountPath: /tmp/spire-sockets
      readOnly: true
  volumes:
  - name: spire-sockets
    hostPath:
      path: /tmp/spire-sockets
      type: Directory
EOF

kubectl apply -f test-workload.yaml
kubectl exec test-spire-workload -- ls -la /tmp/spire-sockets/
```

## Troubleshooting Common Issues

### Issue 1: PostgreSQL Connection Failed
**Symptoms**: SPIRE server logs show connection errors
**Solution**:
```bash
# Verify PostgreSQL is running
kubectl get pods -n postgresql

# Check connection string
kubectl get cm -n spire spire-server-config -o yaml | grep connection_string

# Test connection manually
kubectl run postgres-test --rm -i --tty --image postgres:15 --env="PGPASSWORD=$POSTGRES_PASSWORD" -- psql -h postgresql.postgresql.svc -U spire -d spire_db
```

### Issue 2: SPIRE Agent Not Creating Socket
**Symptoms**: `/tmp/spire-sockets/agent.sock` not found
**Solution**:
```bash
# Check agent logs
kubectl logs -n spire -l app=spire-agent

# Verify hostPath mount
kubectl describe daemonset -n spire spire-agent | grep -A5 Mounts

# Check node has directory
kubectl get nodes -o name | head -1 | xargs -I {} kubectl debug {} -it --image=busybox -- chroot /host ls -la /tmp/spire-sockets/
```

### Issue 3: Certificate Requests Pending
**Symptoms**: `kubectl get certificaterequest` shows `Pending`
**Solution**:
```bash
# Check cert-manager controller logs
kubectl logs -n cert-manager -l app=cert-manager -c cert-manager-controller

# Verify ClusterIssuer
kubectl get clusterissuer selfsigned-issuer -o yaml

# Check for RBAC issues
kubectl auth can-i create certificaterequest --all-namespaces
```

### Issue 4: Metrics Not Scraping
**Symptoms**: No SPIRE metrics in Prometheus
**Solution**:
```bash
# Check ServiceMonitor
kubectl get servicemonitor -n spire

# Verify service endpoints
kubectl get endpoints -n spire spire-server-metrics

# Test metrics endpoint directly
kubectl port-forward -n spire svc/spire-server-metrics 9090:9090 &
curl http://localhost:9090/metrics
```

## Maintenance

### Updating SPIRE Configuration
```bash
# Edit the ConfigMap
kubectl edit cm -n spire spire-server-config

# Restart SPIRE server to apply changes
kubectl rollout restart statefulset -n spire spire-server
```

### Scaling SPIRE Server
```bash
# Increase replicas (for HA)
kubectl scale statefulset -n spire spire-server --replicas=3

# Update resource limits
kubectl edit statefulset -n spire spire-server
```

### Backup and Restore
```bash
# Backup PostgreSQL database
kubectl exec -n postgresql $(kubectl get pods -n postgresql -l app=postgresql -o name | head -1) -- pg_dump -U spire spire_db > spire_backup.sql

# Backup SPIRE server data
kubectl cp -n spire $(kubectl get pods -n spire -l app=spire-server -o name | head -1):/run/spire/data ./spire-data-backup/
```

## Cleanup

To remove the deployment:
```bash
# Delete SPIRE components
kubectl delete -f control-plane/spire/ --recursive

# Delete Cert-Manager
helm uninstall -n cert-manager cert-manager
kubectl delete crd -l app.kubernetes.io/managed-by=Helm

# Delete namespaces
kubectl delete ns spire cert-manager foundation

# Remove local files
rm -rf shared/pki control-plane/spire
```

## Support

For issues not covered in this guide:
1. Check component logs: `kubectl logs -n <namespace> <pod-name>`
2. Verify Kubernetes events: `kubectl get events -n <namespace>`
3. Check resource status: `kubectl describe <resource> -n <namespace>`
4. Review validation script output for specific failures