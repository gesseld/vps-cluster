# NATS JetStream Resource Requirements

## 📊 Complete Resource Specification

### 1. Per-Pod Requirements (Single Replica)

| Resource | Request | Limit | Justification |
|----------|---------|-------|---------------|
| **CPU** | `100m` | `250m` | TLS handshakes, JetStream replication, message processing |
| **Memory** | `170Mi` | `256Mi` | JetStream cache (128Mi), TLS buffers, connection tracking |
| **Storage** | `15Gi` PVC | N/A | Stream data + 20% overhead for WAL, snapshots, compaction |
| **Network** | 1Gbps | N/A | Client connections + intra-cluster replication |

### 2. Cluster Requirements (3-Replica HA)

| Resource | Total | Per Node | Notes |
|----------|-------|----------|-------|
| **CPU** | `300m` req / `750m` lim | `100m` req / `250m` lim | Distributed across 3 nodes |
| **Memory** | `510Mi` req / `768Mi` lim | `170Mi` req / `256Mi` lim | Each pod independent |
| **Storage** | `45Gi` total | `15Gi` per node | Fully replicated streams |
| **Nodes** | 3 minimum | 1 pod per node | Enforced by `maxSkew: 0` |

### 3. Stream Storage Breakdown

#### DOCUMENTS Stream (WorkQueue, 3 replicas)
- **Logical size**: 5GB
- **Physical storage**: 15GB (5GB × 3 replicas)
- **Messages**: 100,000 max
- **Message size**: 1MB max
- **Retention**: WorkQueue (consumed messages removed)

#### EXECUTION Stream (Interest, 3 replicas)
- **Logical size**: 2GB
- **Physical storage**: 6GB (2GB × 3 replicas)
- **Messages**: 50,000 max
- **Message size**: 512KB max
- **Retention**: 24 hours

#### OBSERVABILITY Stream (Limits, 2 replicas)
- **Logical size**: 1GB
- **Physical storage**: 2GB (1GB × 2 replicas)
- **Messages**: Unlimited
- **Message size**: 128KB max
- **Retention**: Size-based (oldest messages discarded)

### 4. Total Storage Calculation

```
DOCUMENTS:   5GB × 3 replicas = 15GB
EXECUTION:   2GB × 3 replicas =  6GB
OBSERVABILITY: 1GB × 2 replicas =  2GB
                          Total = 23GB

Add 30% overhead for:
  • WAL (Write-Ahead Log) files
  • Snapshots
  • Compaction temporary space
  • TLS certificate storage
  • Log files

23GB × 1.3 = ~30GB

Round up to nearest practical size: 15GB per pod × 3 pods = 45GB total
```

## 🖥️ Node Requirements

### Minimum Node Specifications:
```yaml
nodeRequirements:
  count: 3
  cpu: "4 cores minimum"
  memory: "8GB minimum"
  storage: "50GB minimum per node"
  network: "1Gbps minimum"
  os: "Linux with kernel 4.18+"
  kubelet: "1.24+"
```

### Node Labels for Topology:
```bash
# Label nodes for topology spread
kubectl label node <node1> topology.kubernetes.io/zone=zone-a
kubectl label node <node2> topology.kubernetes.io/zone=zone-b
kubectl label node <node3> topology.kubernetes.io/zone=zone-c

# Or use hostname for simpler topology
kubectl label node <node1> topology.kubernetes.io/hostname=<node1>
```

### Resource Reservation (System Overhead):
```
Total Node Memory: 8GB
  - System: 1GB
  - Kubelet: 512MB
  - OS: 512MB
  - Available: ~6GB
  
Total Node CPU: 4 cores
  - System: 0.5 cores
  - Kubelet: 0.5 cores
  - Available: ~3 cores
```

## 💾 Storage Requirements

### StorageClass Configuration:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nats-jetstream
provisioner: kubernetes.io/aws-ebs  # or your cloud provider
parameters:
  type: gp3  # SSD recommended
  iops: "3000"
  throughput: "125"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
```

### PVC Configuration:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nats-jetstream-pvc-0
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nats-jetstream
  resources:
    requests:
      storage: 15Gi
```

### Performance Requirements:
- **IOPS**: Minimum 1000, recommended 3000+
- **Throughput**: 100MB/s minimum
- **Latency**: <5ms for 95th percentile
- **Durability**: 99.999% (11 nines)
- **Availability**: 99.9% (three nines)

## 🌐 Network Requirements

### Port Configuration:
| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| `4222` | TCP | Ingress | Client connections (TLS) |
| `6222` | TCP | Pod-to-Pod | Cluster mesh replication |
| `8222` | TCP | Ingress | Monitoring/management |
| `7777` | TCP | Ingress | Prometheus metrics |

### Bandwidth Estimation:
```
Assuming:
  • 1000 messages/second
  • Average message size: 10KB
  • 3 replicas

Client ingress: 1000 × 10KB = 10MB/s
Intra-cluster: 10MB/s × 2 (replication) = 20MB/s
Total per node: ~10MB/s ingress + 20MB/s replication = 30MB/s

Network requirement: 1Gbps (125MB/s) provides 4× headroom
```

### Network Policies:
```yaml
# Required for HA cluster communication
- port: 6222
  protocol: TCP
  cidr: [Pod CIDR range]

# Client access
- port: 4222
  protocol: TCP
  cidr: [Application CIDR ranges]

# Monitoring
- port: 8222
  protocol: TCP
  cidr: [Monitoring CIDR range]
```

## ⚡ Performance Tuning

### JetStream Memory Configuration:
```yaml
jetstream:
  # Keep at 50% of memory limit for safety
  max_memory_store: 128Mi  # 50% of 256Mi limit
  
  # File store should be 90% of PVC size
  max_file_store: 14Gi  # 15Gi PVC - 1Gi overhead
  
  # Compression (if supported)
  compression: s2
  
  # Snapshot interval
  snapshot_interval: 30m
  
  # Retention policy
  discard: old
  max_age: 0  # Unlimited for WorkQueue
```

### NATS Server Tuning:
```yaml
server:
  # Connection limits
  max_connections: 1000
  max_pending_size: 64MB
  max_payload: 10MB
  
  # TLS configuration
  tls_timeout: 2
  tls_handshake_first: true
  
  # Logging
  debug: false
  trace: false
  logtime: true
```

### Kubernetes Resource Quality of Service:
```yaml
resources:
  requests:
    memory: "170Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "250m"
  
# This gives Burstable QoS class
# Guaranteed would require requests = limits
```

## 📈 Scaling Guidelines

### Vertical Scaling (When to Increase):
- **CPU**: When utilization >70% for 5 minutes
- **Memory**: When usage >80% of limit
- **Storage**: When usage >70% of PVC size

### Horizontal Scaling (When to Add Nodes):
- **Throughput**: >5000 messages/second
- **Connections**: >500 concurrent connections
- **Streams**: >10 active streams
- **Consumers**: >50 active consumers per stream

### Storage Scaling Procedure:
```bash
# 1. Check current usage
kubectl exec nats-0 -- df -h /data/jetstream

# 2. Backup if needed
nats --server nats://nats:4222 stream export DOCUMENTS > backup.json

# 3. Update PVC size
kubectl patch pvc nats-jetstream-pvc-0 -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# 4. Expand filesystem (if supported)
kubectl exec nats-0 -- resize2fs /dev/xxx

# 5. Update JetStream config
kubectl exec nats-0 -- nats server config --max-file-store 19G
```

## 🚨 Resource Limits and Quotas

### Namespace Quotas:
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: nats-quota
  namespace: default
spec:
  hard:
    requests.cpu: "1"
    requests.memory: "2Gi"
    limits.cpu: "2"
    limits.memory: "3Gi"
    requests.storage: "50Gi"
    persistentvolumeclaims: "3"
```

### Limit Ranges:
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: nats-limits
  namespace: default
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: "100m"
        memory: "170Mi"
      default:
        cpu: "250m"
        memory: "256Mi"
      max:
        cpu: "500m"
        memory: "512Mi"
```

## 🔍 Monitoring Resource Usage

### Key Metrics to Monitor:
```prometheus
# CPU and Memory
container_cpu_usage_seconds_total{container="nats"}
container_memory_working_set_bytes{container="nats"}

# Storage
kubelet_volume_stats_available_bytes{persistentvolumeclaim="nats-jetstream"}
kubelet_volume_stats_used_bytes{persistentvolumeclaim="nats-jetstream"}

# Network
container_network_receive_bytes_total{container="nats"}
container_network_transmit_bytes_total{container="nats"}

# JetStream specific
nats_jetstream_stream_total_bytes
nats_jetstream_stream_memory_bytes
```

### Alerting Rules:
```yaml
- alert: NATSHighMemoryUsage
  expr: container_memory_working_set_bytes{container="nats"} / container_spec_memory_limit_bytes{container="nats"} > 0.8
  for: 5m
  labels:
    severity: warning
    
- alert: NATSHighCPUUsage
  expr: rate(container_cpu_usage_seconds_total{container="nats"}[5m]) > 0.7
  for: 5m
  labels:
    severity: warning
    
- alert: NATSStorageRunningLow
  expr: kubelet_volume_stats_available_bytes{persistentvolumeclaim="nats-jetstream"} / kubelet_volume_stats_capacity_bytes{persistentvolumeclaim="nats-jetstream"} < 0.3
  for: 10m
  labels:
    severity: warning
```

## 💰 Cost Estimation (Cloud Providers)

### AWS Estimate (us-east-1):
```
3 × t3.medium instances: 3 × $0.0416/hour = $0.1248/hour
3 × gp3 volumes (15Gi): 3 × $1.50/month = $4.50/month
Data transfer: ~100GB/month = $9.00/month

Monthly total: ~$100-150/month
```

### GCP Estimate (us-central1):
```
3 × e2-medium instances: 3 × $0.0335/hour = $0.1005/hour
3 × pd-ssd (15Gi): 3 × $2.25/month = $6.75/month
Data transfer: ~100GB/month = $12.00/month

Monthly total: ~$90-130/month
```

### Azure Estimate (eastus):
```
3 × B2s instances: 3 × $0.0408/hour = $0.1224/hour
3 × P6 disks (15Gi): 3 × $1.54/month = $4.62/month
Data transfer: ~100GB/month = $8.70/month

Monthly total: ~$95-140/month
```

## 🎯 Summary

### Minimum Viable Deployment:
- **Nodes**: 1 (development), 3 (production)
- **CPU**: 100m per pod, 250m limit
- **Memory**: 170Mi per pod, 256Mi limit
- **Storage**: 15Gi per pod, SSD recommended
- **Network**: 1Gbps, proper firewall rules

### Production Recommendation:
- **Nodes**: 3+ for HA
- **CPU**: 200m request, 500m limit
- **Memory**: 256Mi request, 512Mi limit
- **Storage**: 20Gi per pod, NVMe if possible
- **Monitoring**: Prometheus + Grafana
- **Backup**: Daily stream exports
- **DR**: Multi-zone deployment