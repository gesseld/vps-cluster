# Task DP-3: Hetzner Object Storage with Lifecycle & Near-Real-Time Replication (Enterprise-Resilient v3)

> **Replacement for MinIO**: Managed Hetzner S3-compatible Object Storage with atomic health checks, memory-safe replication, automated heartbeat cleanup, and robust process supervision—designed for enterprise-scale resilience.

## Objective
Provide S3-compatible object storage with compliance-grade versioning, WORM retention, automated lifecycle management, and **true streaming replication with enterprise-grade observability** to external storage for improved RPO—all without managing MinIO infrastructure, while addressing critical edge cases in process supervision, memory safety, metadata bloat, and alert differentiation.

## Architecture

### Core Components
1. **Hetzner Object Storage**: Primary S3-compatible storage (fsn1 region)
2. **External Secrets Operator**: Secure credential management with hot-reload
3. **S3 Replicator Deployment**: Supervised `mc mirror --watch` with monitor loop
4. **Cilium FQDN Policies**: Zero-trust egress restriction by domain name
5. **Differentiated Alerting**: Critical (replication) vs Warning (cost) alerts

### Buckets
- **documents-raw**: Raw uploads, 30-day cold transition
- **documents-processed**: WORM compliance, 7-day retention, heartbeat cleanup
- **backups**: System backups, 90-day retention
- **observability-metrics**: Metrics storage, 30-day retention

### Replication Targets
- **Preferred**: Dual-S3 (fsn1 → nbg1) for atomic consistency
- **Fallback**: Storage Box (SFTP) for budget constraints

## Prerequisites

### Environment Variables
Create `.env` file in project root:
```bash
# Required
HETZNER_S3_ENDPOINT=https://fsn1.your-objectstorage.com
HETZNER_S3_ACCESS_KEY=your_access_key
HETZNER_S3_SECRET_KEY=your_secret_key
HETZNER_S3_REGION=fsn1

# Optional (for replication - currently disabled)
# REPLICATION_TARGET_ENDPOINT=https://nbg1.your-objectstorage.com
# REPLICATION_TARGET_ACCESS_KEY=dr_access_key
# REPLICATION_TARGET_SECRET_KEY=dr_secret_key

# Kubernetes
NAMESPACE=data-plane
STORAGE_CLASS=hcloud-volumes
OBSERVABILITY_NAMESPACE=observability-plane
```

### System Requirements
1. **VPS Requirements**:
   - Kubernetes cluster with kubectl access
   - External Secrets Operator installed
   - Cilium CNI (for FQDN policies)
   - Tools: `mc` (MinIO Client), `jq`, `curl`, `kubectl`

2. **Local Machine**:
   - SSH access to VPS
   - Copy of scripts and .env file
   - (Optional) mc for local testing

## Deployment Steps

### 1. Pre-deployment Check
```bash
./01-pre-deployment-check.sh
```
Validates cluster access, credentials, and prerequisites.

### 2. Deployment
```bash
./02-deployment.sh
```
Deploys all components:
- External Secrets for credentials
- S3 endpoint abstraction service
- Bucket initialization
- S3 replicator with sidecars
- Network policies
- Alerting rules

### 3. Validation
```bash
./03-validation.sh
```
Comprehensive validation of:
- Resource availability
- S3 connectivity
- Replication functionality
- Health checks
- Metrics collection

## Key Features

### Enterprise-Resilient Design
- **Atomic Health Checks**: Readiness verifies mc alias; liveness checks metrics freshness
- **Memory Safety**: Tuned buffer (250) + increased GC headroom (768Mi limit)
- **Metadata Bloat Prevention**: Heartbeat objects auto-expire after 1 day
- **Process Supervision**: Monitor loop detects background process failures
- **Alert Differentiation**: Critical replication → PagerDuty; cost warnings → Slack

### Compliance & Security
- **WORM (Write-Once-Read-Many)**: COMPLIANCE mode with 7-day retention
- **Zero-Trust Egress**: Cilium FQDN policies restrict to approved domains
- **Credential Isolation**: Separate secrets for primary and replication targets
- **Hot Reload**: Credentials refresh without pod restart via inotify

### Observability
- **Heartbeat-Based Lag**: Object-correlated replication monitoring
- **Cost Tracking**: Egress volume alerts for €0.01/GB external transfers
- **Bucket Metrics**: Size, object count, error rates
- **Differentiated Routing**: Appropriate escalation paths per alert type

## Validation Commands

### Quick Health Check
```bash
# Check deployment status
kubectl get deployment s3-replicator -n data-plane
kubectl get pods -n data-plane -l app=s3-replicator

# Check logs
kubectl logs -n data-plane -l app=s3-replicator -c replicator --tail=20
kubectl logs -n data-plane -l app=s3-replicator -c metrics-exporter --tail=10

# Verify metrics
kubectl exec -n data-plane -l app=s3-replicator -c metrics-exporter -- cat /metrics/s3_metrics.prom | head -5
```

### S3 Connectivity Test
```bash
# Configure mc alias
mc alias set hetzner https://fsn1.your-objectstorage.com ACCESS_KEY SECRET_KEY --path off

# Verify buckets
mc ls hetzner/
mc retention info hetzner/documents-processed
mc ilm ls hetzner/documents-processed | grep ".heartbeat"
```

### Replication Test
```bash
# Upload test object
echo "test-$(date +%s)" | mc pipe hetzner/documents-processed/test.txt

# Check replication lag in metrics
kubectl exec -n data-plane -l app=s3-replicator -c metrics-exporter -- \
  cat /metrics/s3_metrics.prom | grep s3_replication_lag_seconds
```

## Failover Procedure

### Trigger Conditions
- Replication lag > 300s + primary endpoint unreachable >2min
- Regional outage (fsn1 down)
- Credential compromise

### Steps (Dual-S3 Preferred)
1. **Verify DR target**: `mc ls dr/documents-processed`
2. **Update configuration**: Patch ExternalSecret or ConfigMap
3. **Restart workloads**: `kubectl rollout restart deployment -l s3-access=true`
4. **Validate**: Upload test object, verify replication within RPO

### RPO/RTO Targets
- **RPO**: 60 seconds (heartbeat interval)
- **RTO**: 10-15 minutes (manual failover)

## Cost Analysis

```
Hetzner Object Storage Pricing:
- Storage: €0.049/GB/month
- Egress: Free within Hetzner; €0.01/GB external

Estimated Monthly Cost:
- documents-raw (50GB): €2.45
- documents-processed (50GB): €2.45
- backups (50GB): €2.45
- observability-metrics (20GB): €0.98
- Dual-S3 replication (50GB): €2.45
- Total: ~€10.78/month

Remaining budget for compute: €29-32/month
```

## Troubleshooting

### Common Issues

#### Replication Stopped
```bash
# Check pod status
kubectl describe pod -n data-plane -l app=s3-replicator

# Check logs for errors
kubectl logs -n data-plane -l app=s3-replicator -c replicator | grep -i error

# Verify credentials
kubectl get secret hetzner-s3-credentials -n data-plane -o yaml

# Restart deployment
kubectl rollout restart deployment s3-replicator -n data-plane
```

#### High Memory Usage
```bash
# Check current usage
kubectl top pod -n data-plane -l app=s3-replicator

# Adjust buffer size (edit deployment)
kubectl edit deployment s3-replicator -n data-plane
# Change MC_MIRROR_WATCH_BUFFER_SIZE: "250" to "200"
```

#### Metrics Exporter Stale
```bash
# Check liveness probe
kubectl describe pod -n data-plane -l app=s3-replicator | grep -A5 Liveness

# Verify volume mounts
kubectl exec -n data-plane -l app=s3-replicator -c metrics-exporter -- ls -la /metrics/

# Restart metrics sidecar
kubectl delete pod -n data-plane -l app=s3-replicator
```

#### DNS Cache Expiry
```bash
# Check DNS refresher logs
kubectl logs -n data-plane -l app=s3-replicator -c dns-refresher

# Test DNS resolution from pod
kubectl exec -n data-plane -l app=s3-replicator -c replicator -- \
  nslookup fsn1.your-objectstorage.com
```

## Deliverables

| File | Purpose |
|------|---------|
| `01-pre-deployment-check.sh` | Validates prerequisites and credentials |
| `02-deployment.sh` | Deploys all S3 storage components |
| `03-validation.sh` | Comprehensive validation suite |
| `manifests/data-plane/storage/` | Kubernetes manifests |
| `manifests/observability-plane/` | Alerting rules and dashboards |
| `manifests/shared/storage-endpoints.md` | Endpoint documentation |
| `manifests/data-plane-runbook.md` | Failover and troubleshooting guide |

## Success Criteria

| Criterion | Validation Method |
|-----------|-------------------|
| **Bucket Provisioning** | All 4 buckets exist with correct settings |
| **WORM Compliance** | `documents-processed` immutable for 7 days |
| **Replication Correctness** | Heartbeat-based lag <60s |
| **Memory Safety** | Memory usage <768Mi under load |
| **Atomic Health Checks** | Probes pass/fail as expected |
| **Network Isolation** | Egress restricted to approved FQDNs |
| **Observability** | Metrics exported with <120s freshness |
| **Alert Differentiation** | Critical vs Warning alerts routed correctly |

## Limitations & Mitigations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| No native cross-bucket replication | Must maintain `mc mirror` replicator | Monitor replicator health; auto-healing |
| Heartbeat objects consume storage | ~1KB/hour per bucket | Auto-expire after 1 day via ILM |
| SSE-C encryption only | No KMS-style key management | Encrypt at application layer |
| Vendor lock-in risk | Hetzner-specific endpoints | Abstraction via ExternalName Service |

## Next Steps

1. **Immediate**: Run validation suite to verify deployment
2. **Weekly**: Review cost alerts and bucket growth
3. **Monthly**: Test credential rotation process
4. **Quarterly**: Conduct failover drills
5. **Annual**: Review architecture for new Hetzner features

## References

- [Hetzner Object Storage Documentation](https://docs.hetzner.com/cloud/storage/object-storage/)
- [External Secrets Operator](https://external-secrets.io/)
- [Cilium FQDN Policies](https://docs.cilium.io/en/stable/security/policy/language/#dns-based)
- [MinIO Client (mc) Documentation](https://min.io/docs/minio/linux/reference/minio-mc.html)