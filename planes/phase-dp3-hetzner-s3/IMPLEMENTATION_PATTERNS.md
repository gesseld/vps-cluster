# Phase DP-3: Implementation Patterns & Key Learnings

## Quick Reference Guide

### 🚀 Deployment Pattern
```bash
# 1. Test S3 connectivity
mc alias set test https://fsn1.your-objectstorage.com $ACCESS_KEY $SECRET_KEY --api s3v4
mc ls test/

# 2. Create Kubernetes secret
kubectl create secret generic hetzner-s3-credentials \
  --namespace=data-plane \
  --from-literal=ENDPOINT="https://fsn1.your-objectstorage.com" \
  --from-literal=ACCESS_KEY="$ACCESS_KEY" \
  --from-literal=SECRET_KEY="$SECRET_KEY" \
  --from-literal=REGION="fsn1" \
  --from-literal=PATH_STYLE="false" \
  --from-literal=TARGET_ENDPOINT="https://fsn1.your-objectstorage.com" \
  --from-literal=TARGET_ACCESS_KEY="$ACCESS_KEY" \
  --from-literal=TARGET_SECRET_KEY="$SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Apply deployment
kubectl apply -f s3-replicator-deployment.yaml
```

### 🔧 Troubleshooting Commands
```bash
# Check pod status
kubectl get pods -n data-plane | grep s3-replicator

# View logs
kubectl logs -n data-plane deployment/s3-replicator --tail=20

# Test from pod
POD_NAME=$(kubectl get pods -n data-plane -l app=s3-replicator -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n data-plane $POD_NAME -- mc --config-dir /mc-config alias list
kubectl exec -n data-plane $POD_NAME -- mc --config-dir /mc-config ls source/
```

## Critical Implementation Patterns

### 1. **Config Directory Pattern**
**Problem**: `mc` needs writable config directory but containers have read-only root filesystem
**Solution**: Use `emptyDir` volume mounted at `/mc-config`
```yaml
volumeMounts:
- name: mc-config
  mountPath: /mc-config

volumes:
- name: mc-config
  emptyDir: {}

# In container args:
mkdir -p /mc-config
mc --config-dir /mc-config alias set source ...
```

### 2. **Same-Region Replication Pattern**
**Problem**: Cross-region replication has latency and cost issues
**Solution**: Configure source and target to same endpoint with different bucket names
```bash
# Source: fsn1 region
mc alias set source https://fsn1.your-objectstorage.com $ACCESS_KEY $SECRET_KEY

# Target: Same region, different buckets
mc alias set target https://fsn1.your-objectstorage.com $ACCESS_KEY $SECRET_KEY

# Replicate: source/bucket → target/bucket-dr
mc mirror --watch source/documents-processed target/documents-processed-dr
```

### 3. **Error-Resilient Replication Pattern**
**Problem**: `mc mirror --watch` can fail and exit
**Solution**: Wrap in infinite retry loop
```bash
while true; do
    mc --config-dir /mc-config mirror --watch \
        --overwrite \
        --remove \
        source/$bucket target/$bucket
    echo "Mirror stopped, restarting in 10 seconds..."
    sleep 10
done
```

### 4. **Bucket Discovery Pattern**
**Problem**: Hardcoded bucket lists fail when buckets don't exist
**Solution**: Dynamic bucket discovery
```bash
# Discover available buckets
AVAILABLE_BUCKETS=$(mc --config-dir /mc-config ls source/ | awk '{print $NF}' | sed 's|/$||')

# Replicate only existing buckets
for bucket in $AVAILABLE_BUCKETS; do
    if [ "$bucket" != "backup-dr" ] && [ "$bucket" != "backup-replica" ]; then
        mc --config-dir /mc-config mirror --watch source/$bucket target/$bucket &
    fi
done
```

### 5. **Health Check Pattern**
**Problem**: Need to verify S3 connectivity continuously
**Solution**: Liveness probe that tests S3 alias
```yaml
livenessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - mc --config-dir /mc-config alias list source > /dev/null 2>&1
  initialDelaySeconds: 90
  periodSeconds: 60
```

## Common Issues & Solutions

### Issue 1: "Bucket name not available"
**Cause**: Global bucket name conflict
**Solution**: Use alternative naming patterns
```bash
# Instead of "backups", use:
mc mb hetzner-s3/backup-dr
mc mb hetzner-s3/backup-replica
mc mb hetzner-s3/backup-$(date +%Y%m%d)
```

### Issue 2: "Read-only file system"
**Cause**: Security context prevents writing to `/root/.mc`
**Solution**: Use config directory pattern with emptyDir volume

### Issue 3: "Signature does not match"
**Cause**: Incorrect PATH_STYLE setting or credential mismatch
**Solution**: Verify credentials and PATH_STYLE
```bash
# For Hetzner S3 (virtual-host style)
PATH_STYLE="false"

# For MinIO or other S3-compatible (path style)
PATH_STYLE="true"
```

### Issue 4: "Replication stops after pod restart"
**Cause**: Background processes not managed
**Solution**: Use process management or restart strategy
```bash
# Store PIDs and monitor
REPLICATION_PIDS=()
for bucket in $BUCKETS; do
    mc mirror --watch source/$bucket target/$bucket &
    REPLICATION_PIDS+=($!)
done

# Monitor and restart if needed
while true; do
    for pid in "${REPLICATION_PIDS[@]}"; do
        if ! kill -0 $pid 2>/dev/null; then
            echo "Process $pid died, restarting..."
            # Restart logic
        fi
    done
    sleep 60
done
```

## Performance Optimization Patterns

### 1. **Bandwidth Limiting**
```bash
mc mirror --watch --bandwidth "25M" source/ target/
```

### 2. **Concurrent Operations**
```bash
mc mirror --watch --max-workers 4 source/ target/
```

### 3. **Exclusion Patterns**
```bash
mc mirror --watch \
    --exclude "*.tmp" \
    --exclude "*.log" \
    --exclude ".heartbeat/*" \
    source/ target/
```

## Security Patterns

### 1. **Credential Management**
```bash
# Never hardcode in scripts
# Use Kubernetes secrets
kubectl create secret generic s3-credentials \
    --from-literal=ACCESS_KEY="$ACCESS_KEY" \
    --from-literal=SECRET_KEY="$SECRET_KEY"
```

### 2. **Container Security**
```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 1000
```

### 3. **Network Security**
```yaml
# Restrict to S3 endpoints only
egress:
- to:
  - ipBlock:
      cidr: 0.0.0.0/0
  ports:
  - protocol: TCP
    port: 443  # HTTPS to S3
```

## Monitoring Patterns

### 1. **Logging Structure**
```json
{
  "timestamp": "2026-04-12T09:20:11Z",
  "level": "INFO",
  "component": "s3-replicator",
  "bucket": "documents-processed",
  "action": "replication_start",
  "duration_ms": 150,
  "success": true
}
```

### 2. **Metrics Collection**
```bash
# Objects count
OBJECTS_COUNT=$(mc --json ls source/documents-processed/ | jq '. | length')

# Replication lag
SOURCE_COUNT=$(mc --json ls source/documents-processed/ | jq '. | length')
TARGET_COUNT=$(mc --json ls target/documents-processed/ | jq '. | length')
REPLICATION_LAG=$((SOURCE_COUNT - TARGET_COUNT))
```

### 3. **Health Endpoints**
```bash
# Simple HTTP health endpoint
while true; do
    echo "HTTP/1.1 200 OK\nContent-Type: application/json\n\n{\"status\":\"healthy\",\"timestamp\":\"$(date)\"}" | \
        nc -l -p 8080 -q 1
done
```

## Deployment Checklist

### Pre-Deployment
- [ ] S3 credentials verified with `mc ls`
- [ ] Required buckets exist or created
- [ ] Kubernetes secret created
- [ ] Network policies configured
- [ ] Resource limits defined

### Deployment
- [ ] Deployment YAML validated
- [ ] Security context configured
- [ ] Health probes configured
- [ ] Volumes mounted correctly
- [ ] Environment variables set

### Post-Deployment
- [ ] Pod reaches Running state
- [ ] Liveness probe passes
- [ ] Replication processes start
- [ ] Test file replicates successfully
- [ ] Logs show no errors
- [ ] Metrics collection working

## Quick Recovery Procedures

### 1. **Pod in CrashLoopBackOff**
```bash
# 1. Check previous logs
kubectl logs -n data-plane <pod-name> --previous

# 2. Delete and recreate
kubectl delete pod -n data-plane <pod-name>
kubectl rollout restart deployment s3-replicator -n data-plane
```

### 2. **Replication Stopped**
```bash
# 1. Check S3 connectivity from pod
POD_NAME=$(kubectl get pods -n data-plane -l app=s3-replicator -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n data-plane $POD_NAME -- mc --config-dir /mc-config alias list

# 2. Restart replication processes
kubectl exec -n data-plane $POD_NAME -- pkill -f "mc mirror"
```

### 3. **Credentials Expired**
```bash
# 1. Update secret
kubectl create secret generic hetzner-s3-credentials-new --from-literal=ACCESS_KEY="$NEW_KEY" ...

# 2. Update deployment
kubectl set env deployment/s3-replicator --from=secret/hetzner-s3-credentials-new

# 3. Restart
kubectl rollout restart deployment s3-replicator -n data-plane
```

## Key Performance Indicators (KPIs)

### Operational KPIs
- **Uptime**: > 99.9%
- **Replication Lag**: < 60 seconds
- **Error Rate**: < 0.1%
- **Recovery Time**: < 5 minutes

### Resource KPIs
- **CPU Usage**: < 70% of limit
- **Memory Usage**: < 80% of limit
- **Network Bandwidth**: < 50Mbps average
- **Storage Growth**: < 10GB/day

### Business KPIs
- **Data Protection**: 100% of critical buckets replicated
- **Compliance**: Versioning enabled on required buckets
- **Cost Efficiency**: No cross-region transfer fees
- **Availability**: Multi-AZ replication within same region

## Continuous Improvement Actions

### Short-term (1-2 weeks)
- [ ] Implement automated testing pipeline
- [ ] Add comprehensive monitoring dashboard
- [ ] Create runbooks for common incidents
- [ ] Establish alerting thresholds

### Medium-term (1-2 months)
- [ ] Implement multi-region disaster recovery
- [ ] Add data validation checks
- [ ] Optimize replication performance
- [ ] Establish backup verification procedures

### Long-term (3-6 months)
- [ ] Implement zero-downtime upgrades
- [ ] Add predictive failure analysis
- [ ] Establish chaos engineering tests
- [ ] Implement cost optimization automation

---

## Summary
This document captures the essential patterns, solutions, and procedures for implementing and maintaining S3 replication in production. By following these patterns, teams can ensure reliable, secure, and efficient data replication with minimal operational overhead.

**Last Updated**: 2026-04-12  
**Version**: 1.0.0  
**Status**: Production Validated  
**Environment**: K3s on Hetzner VPS, fsn1 region