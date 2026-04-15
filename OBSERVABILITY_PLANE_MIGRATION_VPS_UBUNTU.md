# Observability Plane Migration: VPS Ubuntu Instructions

**Setup:**
- `observability-plane` on: **observability-server** (46.225.154.228)
- **Target**: **VPS Ubuntu cluster** (49.12.37.154)
- **Approach**: SSH to VPS, run migration locally on the cluster

---

## Prerequisites

On your Windows PC:
- SSH key to VPS: `hetzner-cli-key`
- SSH access to root@49.12.37.154

On VPS Ubuntu:
- kubectl installed and connected to local k3s cluster
- kubeconfig already configured (`~/.kube/config`)

---

## Quick Start (Recommended)

### Step 1: Copy Migration Script to VPS

From PowerShell on your Windows PC:

```powershell
$VPS_IP = "49.12.37.154"
$SSH_KEY = "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key"

# Copy migration script to VPS
scp -i $SSH_KEY scripts/migrate-observability-plane.sh root@${VPS_IP}:/root/

# Verify
scp -i $SSH_KEY root@${VPS_IP}:/root/migrate-observability-plane.sh .\test.sh
```

### Step 2: SSH to VPS and Run Migration

```powershell
$VPS_IP = "49.12.37.154"
$SSH_KEY = "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key"

# SSH to VPS
ssh -i $SSH_KEY root@${VPS_IP}
```

Once on VPS (Ubuntu shell):

```bash
# Step 2a: Check current contexts (VPS will only have local cluster)
kubectl config get-contexts

# Step 2b: Run migration script
# On VPS, the default context should already be the VPS cluster
# You need to add the observability-server context or use manual approach

# Option A: Manual approach (simplest - no context switching needed)
# Delete from source (requires external kubectl access)
# OR

# Option B: Use script with contexts (requires kubeconfig from both clusters)
OBS_CONTEXT=obs-server VPS_CONTEXT=default DRY_RUN=1 \
  bash /root/migrate-observability-plane.sh
```

---

## Option 1: Manual Approach (Simplest for VPS)

Since VPS only has access to the local cluster, use SSH commands to delete from source, then apply locally.

### From Windows PC PowerShell:

**Step 1: Delete observability-plane from observability-server**

```powershell
$OBS_IP = "46.225.154.228"
$SSH_KEY = "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key"

ssh -i $SSH_KEY root@${OBS_IP} `
  "kubectl delete -k observability-plane --ignore-not-found"

# Optional: Delete namespace
ssh -i $SSH_KEY root@${OBS_IP} `
  "kubectl delete ns observability-plane --ignore-not-found"
```

**Step 2: Apply to VPS cluster**

```powershell
$VPS_IP = "49.12.37.154"
$SSH_KEY = "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key"

# Create namespace
ssh -i $SSH_KEY root@${VPS_IP} `
  "kubectl create ns observability-plane --dry-run=client -o yaml | kubectl apply -f -"

# Copy observability-plane manifests to VPS
scp -i $SSH_KEY -r observability-plane root@${VPS_IP}:/root/

# Apply
ssh -i $SSH_KEY root@${VPS_IP} `
  "kubectl apply -k /root/observability-plane"
```

**Step 3: Monitor on VPS**

```powershell
$VPS_IP = "49.12.37.154"
$SSH_KEY = "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key"

ssh -i $SSH_KEY root@${VPS_IP} `
  "kubectl get pods -n observability-plane -w"
```

---

## Option 2: Complete Script Approach (With Both Contexts)

If you want to use the automated script on VPS, you need kubeconfigs for both clusters.

### Step 1: Copy Kubeconfigs to VPS

```powershell
$VPS_IP = "49.12.37.154"
$SSH_KEY = "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key"

# Create kubeconfig file with both contexts
# First, merge configs on your Windows PC or create manually

# Copy to VPS
scp -i $SSH_KEY ~/.kube/config root@${VPS_IP}:/root/.kube/config
```

### Step 2: SSH to VPS and Run Script

```powershell
ssh -i $SSH_KEY root@${VPS_IP}
```

On VPS (Ubuntu):

```bash
# Copy repo to VPS if not already there
# Or just run script directly

# Dry run
OBS_CONTEXT=obs-server VPS_CONTEXT=default DRY_RUN=1 \
  bash /root/migrate-observability-plane.sh

# Actual migration
OBS_CONTEXT=obs-server VPS_CONTEXT=default APPLY_PHASE0_IF_MISSING=1 \
  bash /root/migrate-observability-plane.sh
```

---

## Option 3: All-in-One PowerShell Script for Windows

Copy and save this as `migrate-observability-plane.ps1`:

```powershell
param(
    [string]$OBS_IP = "46.225.154.228",
    [string]$VPS_IP = "49.12.37.154",
    [string]$SSH_KEY = "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Migrate Observability Plane to VPS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Source: $OBS_IP"
Write-Host "Target: $VPS_IP"
Write-Host ""

# Step 1: Delete from source
Write-Host "Step 1: Removing observability-plane from observability-server..." -ForegroundColor Yellow
ssh -i $SSH_KEY root@${OBS_IP} `
    "kubectl delete -k observability-plane --ignore-not-found" 2>&1 | Write-Host

Write-Host "Step 1: Deleting namespace from observability-server..." -ForegroundColor Yellow
ssh -i $SSH_KEY root@${OBS_IP} `
    "kubectl delete ns observability-plane --ignore-not-found" 2>&1 | Write-Host

# Step 2: Copy manifests to VPS
Write-Host "Step 2: Copying observability-plane manifests to VPS..." -ForegroundColor Yellow
scp -i $SSH_KEY -r observability-plane root@${VPS_IP}:/root/ 2>&1 | Write-Host

# Step 3: Create namespace on VPS
Write-Host "Step 3: Creating observability-plane namespace on VPS..." -ForegroundColor Yellow
ssh -i $SSH_KEY root@${VPS_IP} `
    "kubectl create ns observability-plane --dry-run=client -o yaml | kubectl apply -f -" 2>&1 | Write-Host

# Step 4: Apply to VPS
Write-Host "Step 4: Applying observability-plane to VPS cluster..." -ForegroundColor Yellow
ssh -i $SSH_KEY root@${VPS_IP} `
    "kubectl apply -k /root/observability-plane" 2>&1 | Write-Host

# Step 5: Monitor
Write-Host "Step 5: Waiting for core components (best-effort)..." -ForegroundColor Yellow
ssh -i $SSH_KEY root@${VPS_IP} `
    "kubectl rollout status statefulset/vmsingle -n observability-plane --timeout=180s" 2>&1 | Write-Host
ssh -i $SSH_KEY root@${VPS_IP} `
    "kubectl rollout status statefulset/loki -n observability-plane --timeout=180s" 2>&1 | Write-Host

# Step 6: Validate
Write-Host "Step 6: Checking pod status on VPS..." -ForegroundColor Yellow
ssh -i $SSH_KEY root@${VPS_IP} `
    "kubectl get pods -n observability-plane -o wide" 2>&1 | Write-Host

Write-Host "========================================" -ForegroundColor Green
Write-Host "✅ Migration Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next: SSH to VPS and monitor:"
Write-Host "  ssh -i '$SSH_KEY' root@${VPS_IP}"
Write-Host "  kubectl get pods -n observability-plane -w"
Write-Host ""
Write-Host "Port-forward Grafana from VPS:"
Write-Host "  ssh -i '$SSH_KEY' -L 3000:localhost:3000 root@${VPS_IP} kubectl port-forward -n observability-plane svc/grafana 3000:3000"
Write-Host "  Open: http://localhost:3000"
```

Run from PowerShell:

```powershell
.\migrate-observability-plane.ps1 -OBS_IP "46.225.154.228" -VPS_IP "49.12.37.154" -SSH_KEY "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key"
```

---

## Troubleshooting

### SSH Connection Failed
```powershell
# Verify key exists
Test-Path "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key"

# Check permissions (should be -rw-------)
ls -la "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key"

# Test SSH connection
ssh -i "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key" -v root@49.12.37.154
```

### kubectl Not Found on VPS
```bash
# SSH to VPS
ssh -i ~/.ssh/hetzner-cli-key root@49.12.37.154

# Check if kubectl exists
which kubectl
which k3s

# If k3s installed, use:
k3s kubectl get pods
# Or export alias:
alias kubectl='k3s kubectl'
```

### Pods Not Starting on VPS
```bash
# Check events
kubectl describe pod -n observability-plane <pod-name>

# Check PVC status
kubectl get pvc -n observability-plane

# Check node resources
kubectl top nodes
kubectl top pods -n observability-plane
```

---

## Validation

After migration, on VPS:

```bash
# All pods running
kubectl get pods -n observability-plane

# PVCs bound
kubectl get pvc -n observability-plane

# Services active
kubectl get svc -n observability-plane

# Check vmagent is scraping
kubectl logs -n observability-plane -l app=vmagent | tail -20

# Check fluent-bit collecting logs
kubectl logs -n observability-plane -l app=fluent-bit | tail -20

# Test Grafana
kubectl port-forward -n observability-plane svc/grafana 3000:3000
# Open http://localhost:3000
```

---

## Cleanup (After Validation)

From Windows PC, verify source cluster is clean:

```powershell
$OBS_IP = "46.225.154.228"
$SSH_KEY = "C:\Users\Daniel\Documents\k3s code v2\hetzner-cli-key"

# Verify observability-plane is gone
ssh -i $SSH_KEY root@${OBS_IP} `
    "kubectl get ns observability-plane" 2>&1
# Should return: "NotFound"
```
