# Observability Plane Migration: observability-server → VPS Cluster

**Current Status:**
- `observability-plane` is deployed on: **observability-server** (46.225.154.228)
- **Target**: Move it to **VPS cluster** (49.12.37.154)
- **Storage Warning**: VictoriaMetrics and Loki use PVCs. Data will be lost unless you snapshot first.

---

## Quick Start (Run on Your Local Mac)

### 1. List Available Contexts
```bash
kubectl config get-contexts
```

Note the context names for:
- **Source** (observability-server cluster)
- **Target** (VPS cluster)

### 2. Run Migration

Replace `<OBS_CONTEXT>` and `<VPS_CONTEXT>` with actual context names from step 1:

```bash
cd /path/to/k3s-code-v2

# Dry run first (no changes)
OBS_CONTEXT=<source-ctx> VPS_CONTEXT=<target-ctx> DRY_RUN=1 \
  bash scripts/migrate-observability-plane.sh

# Actual migration (removes from source, applies to target)
OBS_CONTEXT=<source-ctx> VPS_CONTEXT=<target-ctx> \
  APPLY_PHASE0_IF_MISSING=1 \
  bash scripts/migrate-observability-plane.sh
```

### 3. Monitor Deployment on Target Cluster

```bash
# Watch rollout status
kubectl --context <VPS_CONTEXT> rollout status -n observability-plane

# Check pod status
kubectl --context <VPS_CONTEXT> get pods -n observability-plane -w

# Port-forward Grafana (once Ready)
kubectl --context <VPS_CONTEXT> port-forward -n observability-plane svc/grafana 3000:3000
# Open: http://localhost:3000
```

---

## Manual Steps (If You Don't Want to Use the Script)

### Option A: Delete from Source, Apply to Target

**On Source Cluster (observability-server):**
```bash
kubectl --context <OBS_CONTEXT> delete -k observability-plane/
# Optional: Delete the namespace
kubectl --context <OBS_CONTEXT> delete ns observability-plane
```

**On Target Cluster (VPS):**
```bash
# Create namespace if missing
kubectl --context <VPS_CONTEXT> create ns observability-plane --dry-run=client -o yaml | kubectl apply -f -

# Apply all manifests
kubectl --context <VPS_CONTEXT> apply -k observability-plane/

# Wait for rollout
kubectl --context <VPS_CONTEXT> rollout status -n observability-plane
```

### Option B: Export Data First (Preserve Metrics/Logs)

Before deletion, snapshot VictoriaMetrics and Loki:

```bash
# Port-forward to source VictoriaMetrics
kubectl --context <OBS_CONTEXT> port-forward -n observability-plane svc/vmsingle 8428:8428 &

# Trigger snapshot
curl -X POST http://localhost:8428/api/v1/snapshot

# Download snapshot (check VM pod logs for path)
kubectl --context <OBS_CONTEXT> exec -n observability-plane vmsingle-0 -- \
  tar czf /tmp/vm-snapshot.tar.gz /data/vmsingle/snapshots

kubectl --context <OBS_CONTEXT> cp observability-plane/vmsingle-0:/tmp/vm-snapshot.tar.gz ./vm-snapshot.tar.gz

# Repeat for Loki similarly if needed
```

---

## What Gets Moved

The `observability-plane/` directory contains:

| Component | Type | Storage |
|-----------|------|---------|
| VictoriaMetrics | StatefulSet | 50GB PVC (TSDB) |
| vmagent | DaemonSet | None (metrics scraper) |
| Fluent Bit | DaemonSet | None (log collector) |
| Loki | StatefulSet | 20GB PVC (log index) |
| Grafana | Deployment | ConfigMap (dashboards) |
| Alerting | Deployment | ConfigMap (rules) |

---

## Troubleshooting

### "Cannot connect to context"
```bash
# Verify kubeconfig has both contexts
kubectl config view

# Switch context manually
kubectl config use-context <VPS_CONTEXT>
kubectl cluster-info
```

### "Namespace observability-plane already exists on target"
The script handles this. It will apply/update resources in the existing namespace.

### "PVCs not coming up"
Check StorageClass on target cluster:
```bash
kubectl --context <VPS_CONTEXT> get sc
kubectl --context <VPS_CONTEXT> get pvc -n observability-plane
kubectl --context <VPS_CONTEXT> describe pvc -n observability-plane <pvc-name>
```

### "Pods stuck in Pending"
```bash
kubectl --context <VPS_CONTEXT> describe pod -n observability-plane <pod-name>
# Check: node resources, PVC status, image pull errors
```

---

## Validation After Migration

```bash
# All pods Running
kubectl --context <VPS_CONTEXT> get pods -n observability-plane

# Services accessible
kubectl --context <VPS_CONTEXT> get svc -n observability-plane

# Data collection active (check vmagent and fluent-bit logs)
kubectl --context <VPS_CONTEXT> logs -n observability-plane -l app=vmagent --tail=20
kubectl --context <VPS_CONTEXT> logs -n observability-plane -l app=fluent-bit --tail=20

# Grafana accessible
kubectl --context <VPS_CONTEXT> port-forward svc/grafana 3000:3000 -n observability-plane
# Open http://localhost:3000
```

---

## Cleanup from Source (Optional)

After confirming everything is working on the target:

```bash
# Delete observability-plane namespace from source
kubectl --context <OBS_CONTEXT> delete ns observability-plane

# Verify
kubectl --context <OBS_CONTEXT> get ns observability-plane
# Should return "NotFound"
```
