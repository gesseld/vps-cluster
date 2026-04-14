# NATS JetStream Production Configuration

## 📊 Resource Summary Table

| Resource Type | Per Replica (Pod) | Total Cluster (3 Pods) | Notes |
|---------------|-------------------|------------------------|-------|
| **Memory** | `170Mi` req / `256Mi` lim | `510Mi` req / `768Mi` lim | Tight but workable for moderate throughput |
| **CPU** | `100m` req / `250m` lim | `300m` req / `750m` lim | TLS + JetStream replication overhead |
| **Storage (PVC)** | `15Gi` per PVC | `45Gi` total | `ReadWriteOnce`, SSD/NVMe recommended |
| **Worker Nodes** | 1 pod/node (enforced) | **Minimum 3 nodes** | Required for HA deployment |
| **Metrics Exporter** | `50m` CPU / `64Mi` RAM | N/A | `nats-prometheus-exporter` sidecar |
| **Network Ports** | `4222` (TLS), `6222` (cluster), `8222` (monitoring) | Intra-cluster + ingress | Bandwidth scales with throughput |

## 🔧 Configuration Details

### 1. Compute Resources (CPU & Memory)

**Memory Configuration:**
- Request: `170Mi` per pod
- Limit: `256Mi` per pod  
- JetStream memory store: `128Mi` (kept well under limit)
- File store: `14Gi` (15Gi PVC with 1Gi overhead)

**CPU Configuration:**
- Request: `100m` per pod
- Limit: `250m` per pod (increased for TLS + replication)

### 2. Storage Configuration

**Per-PVC Requirements:**
- Size: `15Gi` (12-15Gi range as recommended)
- StorageClass: Any supporting `ReadWriteOnce`
- Binding mode: `WaitForFirstConsumer` for better topology
- File system: `ext4` or `xfs` recommended

**Stream Storage Distribution:**
| Stream | Logical Limit | Replicas | Physical Storage |
|--------|---------------|----------|------------------|
| `DOCUMENTS` | 5GB | 3 | 15GB total (5GB × 3) |
| `EXECUTION` | 2GB + 50k msgs | 3 | 6GB total (2GB × 3) |
| `OBSERVABILITY` | 1GB | 2 | 2GB total (1GB × 2) |
| **Total** | **8GB + 50k msgs** | **3** | **~23GB + overhead** |

### 3. Network & Security

**Port Configuration:**
- `4222`: Client TLS (ingress from execution/control/observability)
- `6222`: Cluster route mesh (pod-to-pod, internal only)
- `8222`: HTTP monitoring (exporter & vmagent scrape)

**TLS Configuration:**
- Self-signed certificates for development
- Production: Use cert-manager or trusted CA
- Certificates stored in secret `nats-tls`

**Network Policies:**
- Allow access from: execution, control, observability namespaces
- Default deny all other traffic
- Requires namespace labels: `kubernetes.io/metadata.name=<namespace>`

### 4. JetStream Stream Configuration

**DOCUMENTS Stream:**
- Subjects: `data.doc.>`
- Retention: WorkQueue
- Max Messages: 100,000
- Max Bytes: 5GB
- Replicas: 1 (3 for HA)
- Purpose: Document processing with work queue semantics

**EXECUTION Stream:**
- Subjects: `exec.task.>`
- Retention: Interest
- Max Age: 24h
- Max Bytes: 2GB
- Max Messages: 50,000
- Replicas: 1 (3 for HA)
- Purpose: Task execution with time-based retention

**OBSERVABILITY Stream:**
- Subjects: `obs.metric.>`
- Retention: Limits
- Max Bytes: 1GB
- Replicas: 1 (2 for HA)
- Purpose: Observability metrics with size limits

### 5. Monitoring & Backpressure

**Metrics Exporter:**
- Port: `7777`
- Resource: `50m` CPU / `64Mi` RAM
- Path: `/metrics`

**Key Metrics to Monitor:**
- `nats_jetstream_stream_total_bytes`: Current stream size
- `nats_jetstream_stream_config_max_bytes`: Stream size limit
- `nats_jetstream_stream_consumer_pending_msgs`: Pending messages
- Backpressure % = `(total_bytes / max_bytes) * 100`

**Alert Thresholds:**
- **Warning**: Backpressure > 80%
- **Critical**: Backpressure > 90%
- **Critical**: Consumer pending messages > 10,000

### 6. High Availability Configuration

**For Future HA Deployment (when resources available):**
```yaml
# In values.yaml
replicaCount: 3
cluster:
  enabled: true
  port: 6222
jetstream:
  replicas: 3
topologySpreadConstraints:
  - maxSkew: 0
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
```

**Quorum Requirements:**
- NATS requires `N/2 + 1` nodes online
- With 3 replicas: Need 2 pods online
- PDB: `minAvailable: 2` maintains quorum

## 🚀 Deployment Instructions

### 1. Pre-deployment Check
```bash
./01-pre-deployment-check.sh
```

### 2. Customize Configuration (Optional)
```bash
export STORAGE_CLASS=fast-ssd
export PVC_SIZE=20Gi
export NAMESPACE=production
```

### 3. Deploy NATS JetStream
```bash
./02-deployment.sh
```

### 4. Validate Deployment
```bash
./03-validation.sh
```

### 5. Complete Deployment
```bash
./run-all.sh
```

## 🔍 Validation Checklist

- [ ] NATS pod running with `Running` status
- [ ] PVC bound with adequate size (≥12Gi)
- [ ] TLS certificates created in secret `nats-tls`
- [ ] All three streams created (DOCUMENTS, EXECUTION, OBSERVABILITY)
- [ ] Network policies applied
- [ ] Metrics exporter responding on port 7777
- [ ] Backpressure monitoring scripts available
- [ ] Required namespaces labeled (execution, control, observability)

## ⚠️ Production Considerations

### 1. TLS Certificates
- Replace self-signed certificates with trusted CA
- Use cert-manager for automatic certificate management
- Rotate certificates regularly

### 2. Authentication
- Currently disabled for simplicity
- Enable NATS accounts and users for production
- Implement JWT-based authentication

### 3. Storage Performance
- Use SSD/NVMe storage for JetStream
- Monitor I/O performance
- Consider RAID configuration for durability

### 4. Monitoring Integration
- Integrate with existing Prometheus/Grafana
- Set up alert notifications
- Create custom dashboards for business metrics

### 5. Backup & Disaster Recovery
- Regular backups of JetStream data
- Disaster recovery plan for NATS cluster
- Test recovery procedures regularly

## 📈 Scaling Guidelines

### Vertical Scaling (Increase Resources):
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
  limits:
    memory: "512Mi"
    cpu: "500m"
jetstream:
  maxMemory: "256M"
  maxFile: "20G"
```

### Horizontal Scaling (Add Replicas):
```yaml
replicaCount: 3
cluster:
  enabled: true
jetstream:
  replicas: 3
```

### Storage Scaling:
```yaml
jetstream:
  fileStorage:
    storageSize: 50Gi
```

## 🛠️ Troubleshooting

### Common Issues:

1. **PVC Not Binding:**
   - Check StorageClass availability
   - Verify node has available storage
   - Check resource quotas

2. **Stream Creation Failed:**
   - Check NATS pod logs
   - Verify TLS certificates
   - Check resource limits

3. **Metrics Not Appearing:**
   - Check exporter pod logs
   - Verify network policies
   - Test endpoint connectivity

4. **High Backpressure:**
   - Increase stream limits
   - Add more consumers
   - Optimize message processing

## 📚 References

- [NATS Documentation](https://docs.nats.io/)
- [JetStream Guide](https://docs.nats.io/nats-concepts/jetstream)
- [Kubernetes NATS Operator](https://github.com/nats-io/k8s)
- [Prometheus NATS Exporter](https://github.com/nats-io/prometheus-nats-exporter)