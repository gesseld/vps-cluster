# Observability Plane Migration: Windows PC Instructions

**Current Status:**
- `observability-plane` deployed on: **observability-server** (46.225.154.228)
- **Target**: **VPS cluster** (49.12.37.154)

---

## Prerequisites

Ensure you have on your Windows PC:
- ✅ kubectl installed and working
- ✅ kubeconfig with both cluster contexts
- ✅ Git Bash or WSL (for running bash script)
- ✅ Network access to both clusters

---

## Option 1: Using PowerShell (No Script Needed)

### Step 1: Get Context Names
```powershell
kubectl config get-contexts
```

Look for two contexts - one for observability-server, one for VPS cluster.

### Step 2: Remove from Source (observability-server)
```powershell
$OBS_CONTEXT = "obs-server"  # Replace with actual context name
$MANIFEST = "observability-plane"

# Delete workloads
kubectl --context $OBS_CONTEXT delete -k $MANIFEST --ignore-not-found

# Optional: Delete namespace
kubectl --context $OBS_CONTEXT delete ns observability-plane --ignore-not-found
```

### Step 3: Apply to Target (VPS Cluster)
```powershell
$VPS_CONTEXT = "vps-cluster"  # Replace with actual context name

# Create namespace if missing
kubectl --context $VPS_CONTEXT create ns observability-plane --dry-run=client -o yaml | kubectl apply -f -

# Apply all manifests
kubectl --context $VPS_CONTEXT apply -k $MANIFEST
```

### Step 4: Monitor Rollout
```powershell
# Watch pods come up
kubectl --context $VPS_CONTEXT get pods -n observability-plane -w

# Wait for core statefulsets (VictoriaMetrics, Loki)
kubectl --context $VPS_CONTEXT rollout status statefulset/vmsingle -n observability-plane --timeout=180s
kubectl --context $VPS_CONTEXT rollout status statefulset/loki -n observability-plane --timeout=180s
```

### Step 5: Validate
```powershell
# Check all pods are running
kubectl --context $VPS_CONTEXT get pods -n observability-plane

# Port-forward to Grafana
kubectl --context $VPS_CONTEXT port-forward -n observability-plane svc/grafana 3000:3000

# Open http://localhost:3000 in browser
```

---

## Option 2: Using Git Bash or WSL (With Script)

### Step 1: Open Git Bash or WSL Terminal

**Git Bash:**
- Right-click in repo folder → "Git Bash Here"

**WSL:**
```powershell
wsl
cd /mnt/c/Users/Daniel/Documents/k3s\ code\ v2
```

### Step 2: Get Context Names
```bash
kubectl config get-contexts
```

### Step 3: Run Migration Script (Dry Run First)
```bash
OBS_CONTEXT=obs-server VPS_CONTEXT=vps-cluster DRY_RUN=1 \
  bash scripts/migrate-observability-plane.sh
```

Replace `obs-server` and `vps-cluster` with actual context names from step 2.

### Step 4: Run Actual Migration
```bash
OBS_CONTEXT=obs-server VPS_CONTEXT=vps-cluster \
  APPLY_PHASE0_IF_MISSING=1 \
  bash scripts/migrate-observability-plane.sh
```

### Step 5: Monitor
```bash
kubectl --context vps-cluster get pods -n observability-plane -w
```

---

## Troubleshooting on Windows

### "kubectl: command not found" in PowerShell
```powershell
# Check if kubectl is in PATH
where.exe kubectl

# If not found, add to PATH or use full path:
C:\Program Files\Docker\Docker\resources\bin\kubectl.exe get nodes
```

### "Cannot connect to context"
```powershell
# Verify kubeconfig
kubectl config view

# List all available contexts
kubectl config get-contexts

# Switch context manually
kubectl config use-context vps-cluster
```

### "bash: scripts/migrate-observability-plane.sh: No such file or directory"
```bash
# Verify working directory
pwd

# Should output: /c/Users/Daniel/Documents/k3s code v2
# If not, navigate to repo:
cd /c/Users/Daniel/Documents/k3s\ code\ v2
```

### "Pods stuck in Pending"
```powershell
# Check PVC status
kubectl --context vps-cluster get pvc -n observability-plane

# Check node resources
kubectl --context vps-cluster describe node

# Check pod events
kubectl --context vps-cluster describe pod <pod-name> -n observability-plane
```

---

## What Gets Deleted/Created

### From Source (observability-server):
- ❌ StatefulSets: vmsingle, loki
- ❌ DaemonSets: vmagent, fluent-bit
- ❌ Deployments: grafana, vmalert
- ❌ ConfigMaps, Secrets, Services
- ⚠️ **PVCs (volumes may be deleted depending on StorageClass reclaim policy)**

### On Target (VPS cluster):
- ✅ Namespace: observability-plane
- ✅ All resources listed above
- ✅ New PVCs created (empty, no historical data)

---

## Validation Checklist

After migration, verify:

```powershell
# 1. All pods running
kubectl --context vps-cluster get pods -n observability-plane
# Expected: All pods in "Running" or "Ready" state

# 2. Services accessible
kubectl --context vps-cluster get svc -n observability-plane

# 3. PVCs bound
kubectl --context vps-cluster get pvc -n observability-plane

# 4. Verify source is clean
kubectl --context obs-server get all -n observability-plane
# Expected: "No resources found"

# 5. Test Grafana
kubectl --context vps-cluster port-forward -n observability-plane svc/grafana 3000:3000
# Open: http://localhost:3000 (admin/admin default)
```

---

## Data Preservation

If you need to keep metrics/logs, backup before deletion:

```powershell
# Port-forward to source VictoriaMetrics
kubectl --context obs-server port-forward -n observability-plane svc/vmsingle 8428:8428 &

# Trigger snapshot via PowerShell
Invoke-WebRequest -Uri "http://localhost:8428/api/v1/snapshot" -Method POST

# Check VM logs for snapshot path
kubectl --context obs-server logs -n observability-plane vmsingle-0 | Select-String "snapshot"

# Copy snapshot from pod
kubectl --context obs-server cp `
  observability-plane/vmsingle-0:/data/vmsingle/snapshots `
  ./vm-backup

# Store safely, then delete source
```

---

## Quick Command Reference

```powershell
# List all contexts
kubectl config get-contexts

# Current context
kubectl config current-context

# Delete plane from source
kubectl --context obs-server delete -k observability-plane --ignore-not-found

# Apply plane to target
kubectl --context vps-cluster apply -k observability-plane

# Watch pods
kubectl --context vps-cluster get pods -n observability-plane -w

# Check specific pod
kubectl --context vps-cluster describe pod <pod-name> -n observability-plane

# View logs
kubectl --context vps-cluster logs -n observability-plane <pod-name>

# Port-forward Grafana
kubectl --context vps-cluster port-forward -n observability-plane svc/grafana 3000:3000

# Cleanup source namespace (after validation)
kubectl --context obs-server delete ns observability-plane
```
