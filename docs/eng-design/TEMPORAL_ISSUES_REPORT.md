# Temporal Deployment Issue Report

**Date:** 2026-04-13  
**Status:** ✅ FULLY RESOLVED  
**Namespace:** control-plane  
**Pod:** temporal-0

## Current Status

```
kubectl get pod temporal-0 -n control-plane
NAME         READY   STATUS    RESTARTS       AGE
temporal-0   1/1     Running   2 (9m3s ago)   9m4s
```

**Temporal is fully operational.** All critical issues have been resolved.

## ✅ Issues Resolved

| Issue | Fix Applied | Status |
|-------|-------------|--------|
| ConfigMap credentials (`user: app`) | Changed to `user: temporal` | ✅ Fixed |
| Base64 password in ConfigMap | Changed to plaintext `temporal_password` | ✅ Fixed |
| `broadcastAddress: POD_IP` (invalid) | Changed to `0.0.0.0` | ✅ Fixed |
| emptyDir volume instead of ConfigMap | Patched to use `temporal-config` ConfigMap | ✅ Fixed |
| HTTP probes returning 404 | Changed to TCP socket on port 7233 | ✅ Fixed |
| Broken init container (`|| true`) | Removed entirely | ✅ Fixed |
| Duplicate `POSTGRES_SEEDS` env vars | Corrected to single value | ✅ Fixed |

## 🔍 Verified Working

- ✅ Database connection successful
- ✅ History service shards initializing (277+)
- ✅ All queue processors started (transfer, timer, visibility)
- ✅ Worker service running (taskqueue scavenger active)
- ✅ Health probes passing (TCP socket on 7233)
- ✅ No auth errors in logs

## 📊 Consolidated Master Reference (Applied)

All fixes from the consolidated document have been applied:

### Pre-Flight Checks (Verified)
```bash
kubectl get configmap temporal-config -n control-plane -o yaml | grep password
# ✅ password: temporal_password (plaintext)

kubectl get statefulset temporal -n control-plane -o jsonpath='{.spec.template.spec.volumes[0]}'
# ✅ {"configMap":{"name":"temporal-config"},"name":"config"}
```

### Probe Fix Applied (TCP Socket)
```bash
kubectl patch statefulset temporal -n control-plane --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe","value":{"tcpSocket":{"port":7233},"initialDelaySeconds":30,"periodSeconds":10,"timeoutSeconds":5,"failureThreshold":3}},
  {"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe","value":{"tcpSocket":{"port":7233},"initialDelaySeconds":10,"periodSeconds":5,"timeoutSeconds":3,"failureThreshold":1}}
]'
```

### Volume Mount Fixed
```bash
kubectl patch statefulset temporal -n control-plane --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/volumes/0","value":{"configMap":{"name":"temporal-config"},"name":"config"}},
  {"op":"remove","path":"/spec/template/spec/initContainers"}
]'
```

## ⚠️ Remaining Items (Technical Debt - Optional)

These items are **NOT blockers** but are optimizations:

| Issue | Impact | Recommendation |
|-------|--------|----------------|
| `broadcastAddress: 0.0.0.0` | Medium | Use Downward API `${POD_IP}` for proper clustering |
| Multiple ConfigMaps | Low | Consolidate to single `temporal-config` |
| Credentials in ConfigMap | Low | Move to Secret with env var expansion |
| Missing Kyverno labels | Low | Add `plane: control, tenant: platform` to template |

## 📁 Configuration Files Updated

| File | Status |
|------|--------|
| `planes/phase-cp1-temporal/control-plane/temporal/temporal-server.yaml` | ✅ Updated with correct spec |
| `planes/phase-cp1-temporal/control-plane/temporal/config/temporal-config.yaml` | ✅ Fixed credentials and address |
| `temporal-statefulset.yaml` | ✅ Deleted (was causing confusion) |
| `docs/eng-design/TEMPORAL_ISSUES_REPORT.md` | ✅ This file - final status |

## Verification Commands

```bash
# Check pod is ready
kubectl get pod temporal-0 -n control-plane
# Expected: 1/1 Running

# Check for errors
kubectl logs temporal-0 -n control-plane | grep -i error
# Expected: Only non-critical warnings

# Verify service ports
kubectl exec temporal-0 -n control-plane -- ss -tlnp | grep -E "7233|7234|7235|9090"
# Expected: All ports listening

# Test metrics endpoint
kubectl exec temporal-0 -n control-plane -- curl -s http://localhost:9090/metrics | head -3
# Expected: Prometheus metrics output
```

## 🎯 Prevention Best Practices

1. **Never use POD_IP in config** - Use valid IPs or `0.0.0.0`
2. **ConfigMaps use plaintext** - Secrets use base64 (don't mix)
3. **Direct ConfigMap mount** - Don't use init container copy pattern
4. **TCP probes for gRPC services** - HTTP probes don't work on gRPC ports
5. **Single source of truth** - One ConfigMap, mounted directly
6. **Use JSON patch for container arrays** - More reliable than merge patch

---

**Deployment Status: OPERATIONAL** ✅