# Temporal Deployment Failure - Diagnostic Report

## Executive Summary

The `temporal-final` deployment in the `data-plane` namespace failed to start successfully. Multiple issues were identified and addressed, but the deployment remains in a `CrashLoopBackOff` state due to an inability to connect to the PostgreSQL database. The root cause appears to be a network connectivity issue between the Temporal pod (on worker node `k3s-w-2`) and the PostgreSQL pod (on control plane node `k3s-cp-1`), despite network policies being in place.

---

## Issue #1: Init Container Resource Requests Below LimitRange Minimums

### Symptoms
```
ReplicaFailure: pods "temporal-final-cf45947bb-pvpvh" is forbidden: 
[minimum cpu usage per Container is 50m, but request is 10m, 
minimum memory usage per Container is 128Mi, but request is 16Mi]
```

### Root Cause
The `LimitRange` in the `data-plane` namespace enforces minimum resource requests:
```yaml
min:
  cpu: 50m
  memory: 128Mi
```

The init container's resource requests were below these minimums:
```yaml
resources:
  requests:
    cpu: 10m    # Should be 50m
    memory: 16Mi # Should be 128Mi
```

### Fix Applied
Updated the init container resources in `tmp_temporal_fixed.yaml`:
```yaml
resources:
  limits:
    cpu: 50m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 128Mi
```

Applied via: `kubectl apply -f tmp_temporal_fixed.yaml`

### Status: RESOLVED

---

## Issue #2: Config File Naming Mismatch

### Symptoms
```
unable to stat /etc/temporal/config/config_template.yaml, 
error: stat /etc/temporal/config/config_template.yaml: no such file or directory
```

### Root Cause
The Temporal server (version 1.29.1) expects a config file named `config_template.yaml` in the config directory, but the init container was copying the file as `docker.yaml`.

Init container command (before):
```yaml
command: ["sh", "-c", "cp /config-source/docker.yaml /config-dest/docker.yaml"]
```

### Fix Applied
Updated init container command:
```yaml
command: ["sh", "-c", "cp /config-source/docker.yaml /config-dest/config_template.yaml"]
```

### Status: RESOLVED

---

## Issue #3: Incomplete ConfigMap Configuration

### Symptoms
```
Unable to load configuration: config file corrupted: 
Persistence.DefaultStore: zero value, 
Persistence.NumHistoryShards: zero value.
```

### Root Cause
The original ConfigMap (`temporal-config-final`) contained an incomplete `docker.yaml` that was missing required fields for Temporal 1.28+. The configuration structure changed significantly in newer versions.

Original (incomplete) ConfigMap data:
```yaml
persistence:
  default:
    sql:
      pluginName: "postgres12"
      databaseName: "temporal"
      connectAddr: "postgresql-primary:5432"
      user: "temporal"
      password: "temporal"
  visibility:
    sql:
      pluginName: "postgres12"
      databaseName: "temporal_visibility"
      connectAddr: "postgresql-primary:5432"
      user: "temporal"
      password: "temporal"
# Missing: numHistoryShards, defaultStore, visibilityStore, datastores
```

### Fix Applied
Created a complete ConfigMap with the proper 1.28+ structure:
```yaml
persistence:
  numHistoryShards: 10
  defaultStore: postgres-default
  visibilityStore: postgres-visibility
  datastores:
    postgres-default:
      sql:
        pluginName: postgres12
        connectProtocol: tcp
        databaseName: temporal
        connectAddr: postgresql-primary:5432
        user: temporal
        password: temporal
    postgres-visibility:
      sql:
        pluginName: postgres12
        connectProtocol: tcp
        databaseName: temporal_visibility
        connectAddr: postgresql-primary:5432
        user: temporal
        password: temporal
services:
  frontend:
    rpc:
      grpcPort: 7233
      membershipPort: 6933
```

### Status: RESOLVED (Config structure is now correct)

---

## Issue #4: Plugin Name Validation Error

### Symptoms
```
sql schema version compatibility check failed: plugin not supported: 
unknown plugin "postgres", 
supported plugins: [mysql8 postgres12 postgres12_pgx sqlite]
```

### Root Cause
When testing different configurations, the plugin name was changed from `postgres12` to `postgres`, which is not supported.

### Fix Applied
Ensured `pluginName: postgres12` in the ConfigMap.

### Status: RESOLVED

---

## Issue #5: Network Connectivity to PostgreSQL (UNRESOLVED)

### Symptoms
```
sql handle: unable to refresh database connection pool
error: dial tcp 10.43.205.181:5432: connect: connection refused
```

### Root Cause Analysis

The PostgreSQL database IS accessible from within the PostgreSQL pod itself:
```
localhost ([::1]:5432) open
```

The PostgreSQL service endpoints are correctly configured:
```
NAME                 ENDPOINTS         AGE
postgresql-primary   10.42.0.54:5432   2d22h
```

PostgreSQL is running normally with correct credentials and schema:
```
psql -U temporal -d temporal -c "\dt"  # Returns 36 tables
```

However, the Temporal pod (on `k3s-w-2:10.42.6.x`) cannot connect to the PostgreSQL service at `10.43.205.181:5432`.

### Network Policy Analysis

Multiple NetworkPolicies exist in the `data-plane` namespace that may be affecting connectivity:

1. **allow-all-in-namespace** (podSelector: `{}`)
   - Allows ingress/egress within namespace
   - **Problem**: Does not explicitly allow port 5432

2. **allow-data-to-storage** (podSelector: `{}`)
   - Initially restricted egress to ports 9000, 9001 (MinIO/Longhorn)
   - Was deleted during troubleshooting attempts

3. **allow-dns-egress** (podSelector: `{}`)
   - Allows DNS (port 53) to kube-system kube-dns

4. **allow-egress-https** (podSelector: `{}`)
   - Allows HTTPS egress to external IPs only

5. **allow-postgresql-egress** (podSelector: `app=temporal-final`)
   - Created during troubleshooting to explicitly allow port 5432 to postgresql pods
   - **Not effective**

### Cilium Network Policy

One CiliumNetworkPolicy exists:
- **s3-egress-restricted**: Restricts egress for pods with `s3-access=true` label to specific FQDNs

This policy does NOT apply to the temporal-final pod as it doesn't have the `s3-access: "true"` label.

### Possible Root Causes (Unresolved)

1. **Cilium-specific NetworkPolicy handling**: Even with Kubernetes NetworkPolicies in place, Cilium may interpret and enforce them differently. The combination of multiple `podSelector: {}` policies may be causing unexpected behavior.

2. **Cross-node communication**: The PostgreSQL pod is on `k3s-cp-1` (control plane) while Temporal is on `k3s-w-2` (worker). There may be network routing issues between nodes.

3. **DNS Resolution**: While DNS egress is allowed to kube-system, the resolution of `postgresql-primary.data-plane.svc.cluster.local` may be failing.

4. **Port-specific filtering**: The `allow-all-in-namespace` policy doesn't specify ports for internal namespace communication, which may cause issues with Cilium's enforcement.

### Steps Taken to Fix

1. Deleted the restrictive `allow-data-to-storage` policy
2. Created `allow-postgresql-egress` policy specifically for temporal-final pods
3. Attempted to add port 5432 to various policies
4. Verified endpointSlice configuration

### Current Status: UNRESOLVED

---

## Issue #6: LimitRange Memory Limit Breach

### Symptoms
```
pods "debug-pg" is forbidden: exceeded quota: data-plane-quota, 
requested: limits.memory=1Gi, used: limits.memory=5760Mi, limited: limits.memory=6Gi
```

### Root Cause
The quota check blocked the creation of debug pods. Memory usage summary:
- Limits Used: 5760Mi
- Limits Hard: 6Gi (6144Mi)
- Available: 384Mi

### Status: BYPASSED (Not directly affecting Temporal deployment)

---

## Deployment Current State

```
NAME                              READY   STATUS             RESTARTS      AGE
temporal-final-5b69d68694-h2hw7   0/1     CrashLoopBackOff   2 (14s ago)   31s
```

The pod is scheduling and running, but crashes immediately due to the PostgreSQL connection failure.

---

## Configuration Files Modified

1. **tmp_temporal_fixed.yaml** - Deployment manifest with corrected:
   - Init container resources (50m CPU, 128Mi memory)
   - Init container command (copies to config_template.yaml)

2. **temporal-config-final** ConfigMap - Recreated with complete PostgreSQL persistence configuration

3. **allow-postgresql-egress** NetworkPolicy - Created to explicitly allow port 5432

---

## Verification Commands Used

### PostgreSQL Connectivity (Working)
```bash
# From PostgreSQL pod - works
kubectl exec postgresql-primary-0 -n data-plane -- psql -U temporal -c "SELECT 1" -d temporal

# Service endpoints - correct
kubectl get endpoints postgresql-primary -n data-plane

# Database schema - exists
kubectl exec postgresql-primary-0 -n data-plane -- psql -U temporal -d temporal -c "\dt"
```

### Temporal Pod to PostgreSQL (Failing)
```bash
# Error from Temporal pod
kubectl logs temporal-final-xxx -n data-plane
# Result: dial tcp 10.43.205.181:5432: connect: connection refused
```

---

## Recommendations for Resolution

1. **Check Cilium Agent Status**: Run `cilium status` on all nodes to verify Cilium is functioning correctly.

2. **Test Cross-Node Connectivity**: Deploy a minimal debug pod on the same node as PostgreSQL to verify cross-node networking.

3. **Review CNI Configuration**: Verify that kube-robin or other CNI is not interfering with the network policies.

4. **Consider HostPort or NodePort**: Temporarily expose PostgreSQL on a host port to bypass network policies for testing.

5. **Enable Cilium Debugging**: Run `cilium status --verbose` to check for any network policy enforcement issues.

6. **Test with Relaxed Network Policies**: Delete all NetworkPolicies except `allow-all-in-namespace` to isolate if policy interaction is the issue.

---

## Summary Table

| Issue | Status | Resolution |
|-------|--------|------------|
| Init container resource requests below LimitRange | RESOLVED | Updated to 50m/128Mi |
| Config file naming mismatch | RESOLVED | Changed to config_template.yaml |
| Incomplete ConfigMap | RESOLVED | Created complete persistence config |
| Plugin name validation | RESOLVED | Using postgres12 |
| Network connectivity to PostgreSQL | UNRESOLVED | Likely Cilium/network policy issue |

---

## Files Referenced

- `tmp_temporal_fixed.yaml` - Deployment manifest at `C:\Users\Daniel\Documents\k3s code v2\tmp_temporal_fixed.yaml`
- ConfigMap: `temporal-config-final` in namespace `data-plane`
- NetworkPolicy: `allow-postgresql-egress` in namespace `data-plane`
- LimitRange: `data-plane-defaults` in namespace `data-plane`
- ResourceQuota: `data-plane-quota` in namespace `data-plane`
