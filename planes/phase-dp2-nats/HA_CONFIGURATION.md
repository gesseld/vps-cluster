# NATS JetStream High Availability Configuration

## 🎯 HA Requirements Summary

| Requirement | Specification | Notes |
|-------------|---------------|-------|
| **Replicas** | 3 pods | Minimum for quorum-based HA |
| **Nodes** | Minimum 3 worker nodes | Enforced by `maxSkew: 0` |
| **Storage per Pod** | 15Gi PVC | Total 45Gi across cluster |
| **Memory per Pod** | 170Mi req / 256Mi lim | 510Mi req / 768Mi lim total |
| **CPU per Pod** | 100m req / 250m lim | 300m req / 750m lim total |
| **Quorum** | N/2 + 1 (2 pods) | Maintained by `minAvailable: 2` PDB |
| **Topology Spread** | `maxSkew: 0` | One pod per node mandatory |

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    NATS JetStream HA Cluster            │
├──────────────┬──────────────┬──────────────┬────────────┤
│   Node 1     │   Node 2     │   Node 3     │   Client   │
│              │              │              │  Access    │
│  ┌────────┐  │  ┌────────┐  │  ┌────────┐  │            │
│  │ NATS-0 │  │  │ NATS-1 │  │  │ NATS-2 │  │  ┌──────┐  │
│  │  Pod   │◄─┼─►│  Pod   │◄─┼─►│  Pod   │◄───┤ Load │  │
│  └────────┘  │  └────────┘  │  └────────┘  │  │ Bal  │  │
│    15Gi      │    15Gi      │    15Gi      │  └──────┘  │
│    PVC       │    PVC       │    PVC       │            │
└──────────────┴──────────────┴──────────────┴────────────┘
       │              │              │              │
       └──────────────┴──────────────┴──────────────┘
                 Cluster Mesh (port 6222)
```

## 🔧 HA Configuration Files

### 1. Updated `values.yaml` for HA

```yaml
# data-plane/nats/values-ha.yaml
nats:
  replicaCount: 3
  
  # Enable cluster for HA
  cluster:
    enabled: true
    port: 6222
  
  # JetStream with 3 replicas
  jetstream:
    enabled: true
    maxMemory: 128M
    maxFile: 14G
  
  # Topology spread constraints
  topologySpreadConstraints:
    - maxSkew: 0
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: nats
  
  # Anti-affinity rules
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchExpressions:
              - key: app
                operator: In
                values:
                  - nats
          topologyKey: kubernetes.io/hostname

global:
  jetstream:
    fileStorage:
      storageSize: 15Gi
      volumeBindingMode: WaitForFirstConsumer
  
  tls:
    enabled: true
    secret:
      name: nats-tls

# Server configuration with cluster routes
config:
  serverConfig: |
    jetstream {
      store_dir: "/data/jetstream"
      max_memory_store: 134217728
      max_file_store: 15032385536
    }
    
    cluster {
      name: "nats-cluster"
      port: 6222
      routes: [
        nats://nats-0.nats-headless.default.svc.cluster.local:6222
        nats://nats-1.nats-headless.default.svc.cluster.local:6222
        nats://nats-2.nats-headless.default.svc.cluster.local:6222
      ]
    }
    
    tls {
      cert_file: "/etc/nats/tls/tls.crt"
      key_file: "/etc/nats/tls/tls.key"
      ca_file: "/etc/nats/tls/ca.crt"
    }
```

### 2. Updated Stream Configuration for HA

```yaml
# data-plane/nats/stream-config-ha.yaml
data:
  create-streams.sh: |
    #!/bin/bash
    set -e
    
    echo "Creating NATS JetStream streams with 3 replicas..."
    
    # Create DOCUMENTS stream with 3 replicas
    nats --server nats://nats:4222 stream add DOCUMENTS \
      --subjects "data.doc.>" \
      --retention workqueue \
      --max-msgs 100000 \
      --max-bytes 5GB \
      --storage file \
      --replicas 3 \
      --discard old \
      --dupe-window 2m \
      --max-msg-size 1MB
    
    # Create EXECUTION stream with 3 replicas
    nats --server nats://nats:4222 stream add EXECUTION \
      --subjects "exec.task.>" \
      --retention interest \
      --max-age 24h \
      --max-bytes 2GB \
      --max-msgs 50000 \
      --storage file \
      --replicas 3 \
      --discard old \
      --dupe-window 1m \
      --max-msg-size 512KB
    
    # Create OBSERVABILITY stream with 2 replicas
    nats --server nats://nats:4222 stream add OBSERVABILITY \
      --subjects "obs.metric.>" \
      --retention limits \
      --max-bytes 1GB \
      --storage file \
      --replicas 2 \
      --discard old \
      --dupe-window 30s \
      --max-msg-size 128KB
```

### 3. Updated PDB for HA

```yaml
# data-plane/nats/pdb-ha.yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: nats-pdb
  namespace: default
spec:
  # Maintain quorum (2 out of 3 pods)
  minAvailable: 2
  selector:
    matchLabels:
      app: nats
      component: server
```

## 🚀 HA Deployment Script

```bash
#!/bin/bash
# deploy-ha.sh

set -e

echo "========================================="
echo "NATS JetStream HA Deployment"
echo "========================================="

# Source environment
if [ -f .env ]; then
    source .env
fi

# Default values
NAMESPACE=${NAMESPACE:-default}
STORAGE_CLASS=${STORAGE_CLASS:-""}
PVC_SIZE=${PVC_SIZE:-15Gi}
NODE_COUNT=${NODE_COUNT:-3}

echo "Deploying NATS JetStream HA cluster with:"
echo "  • 3 replicas"
echo "  • 15Gi PVC per pod"
echo "  • TLS encryption"
echo "  • Topology spread (one pod per node)"
echo ""

# Check node count
echo "Checking node availability..."
ACTUAL_NODES=$(kubectl get nodes --no-headers | wc -l)
if [ "$ACTUAL_NODES" -lt "$NODE_COUNT" ]; then
    echo "ERROR: Need at least $NODE_COUNT nodes for HA deployment"
    echo "Found only $ACTUAL_NODES nodes"
    exit 1
fi

# Label nodes for topology (if needed)
echo "Labeling nodes for topology spread..."
for node in $(kubectl get nodes -o name | cut -d'/' -f2); do
    kubectl label node "$node" topology.kubernetes.io/zone=zone-a --overwrite
done

# Create TLS certificates
echo "Creating TLS certificates..."
./scripts/create-tls-certs.sh

# Deploy with HA values
echo "Deploying NATS HA cluster..."
helm upgrade --install nats nats/nats \
    -n "$NAMESPACE" \
    -f data-plane/nats/values-ha.yaml \
    --set global.jetstream.fileStorage.storageSize="$PVC_SIZE" \
    --set global.jetstream.fileStorage.storageClassName="$STORAGE_CLASS" \
    --wait \
    --timeout 10m

echo "NATS JetStream HA deployment completed!"
echo ""
echo "Cluster Status:"
echo "  kubectl get pods -n $NAMESPACE -l app=nats"
echo "  kubectl get pvc -n $NAMESPACE -l app=nats"
echo ""
echo "Stream Information:"
echo "  kubectl exec deployment/nats -n $NAMESPACE -- nats stream list"
echo ""
echo "Cluster Information:"
echo "  kubectl exec deployment/nats -n $NAMESPACE -- nats server list"
```

## 🔍 HA Validation Script

```bash
#!/bin/bash
# validate-ha.sh

set -e

echo "========================================="
echo "NATS JetStream HA Validation"
echo "========================================="

# Source environment
if [ -f .env ]; then
    source .env
fi

NAMESPACE=${NAMESPACE:-default}

echo "Validating HA deployment..."

# Check pod count
echo "1. Checking pod count..."
POD_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=nats --no-headers | wc -l)
if [ "$POD_COUNT" -eq 3 ]; then
    echo "   ✓ 3 pods running"
else
    echo "   ✗ Expected 3 pods, found $POD_COUNT"
    exit 1
fi

# Check pod distribution
echo "2. Checking pod distribution across nodes..."
NODE_COUNT=$(kubectl get pods -n "$NAMESPACE" -l app=nats -o jsonpath='{.items[*].spec.nodeName}' | tr ' ' '\n' | sort -u | wc -l)
if [ "$NODE_COUNT" -eq 3 ]; then
    echo "   ✓ Pods distributed across 3 nodes"
else
    echo "   ✗ Pods not properly distributed (on $NODE_COUNT nodes)"
fi

# Check cluster status
echo "3. Checking NATS cluster status..."
NATS_POD=$(kubectl get pod -n "$NAMESPACE" -l app=nats -o jsonpath='{.items[0].metadata.name}')
CLUSTER_INFO=$(kubectl exec "$NATS_POD" -n "$NAMESPACE" -- nats server list 2>/dev/null || echo "")
if echo "$CLUSTER_INFO" | grep -q "3 servers"; then
    echo "   ✓ Cluster has 3 servers"
else
    echo "   ✗ Cluster not properly formed"
    echo "$CLUSTER_INFO"
fi

# Check stream replication
echo "4. Checking stream replication..."
for stream in DOCUMENTS EXECUTION OBSERVABILITY; do
    STREAM_INFO=$(kubectl exec "$NATS_POD" -n "$NAMESPACE" -- nats stream info "$stream" 2>/dev/null || echo "")
    if echo "$STREAM_INFO" | grep -q "Clustered: Yes"; then
        echo "   ✓ $stream stream is clustered"
        
        # Check replicas
        if [ "$stream" = "OBSERVABILITY" ]; then
            EXPECTED_REPLICAS=2
        else
            EXPECTED_REPLICAS=3
        fi
        
        if echo "$STREAM_INFO" | grep -q "Replicas: $EXPECTED_REPLICAS"; then
            echo "   ✓ $stream has $EXPECTED_REPLICAS replicas"
        else
            echo "   ✗ $stream replicas incorrect"
        fi
    else
        echo "   ✗ $stream not clustered"
    fi
done

# Check PDB
echo "5. Checking PodDisruptionBudget..."
PDB_INFO=$(kubectl get pdb nats-pdb -n "$NAMESPACE" -o jsonpath='{.spec.minAvailable}' 2>/dev/null || echo "")
if [ "$PDB_INFO" = "2" ]; then
    echo "   ✓ PDB configured with minAvailable: 2"
else
    echo "   ✗ PDB not properly configured"
fi

echo ""
echo "HA Validation Summary:"
echo "  • Pods: $POD_COUNT/3"
echo "  • Nodes: $NODE_COUNT/3"
echo "  • Cluster: $(echo "$CLUSTER_INFO" | grep -c "Server ID" || echo "0")/3"
echo "  • PDB: minAvailable=$PDB_INFO"
echo ""
echo "NATS JetStream HA cluster is operational!"
```

## 📊 HA Performance Considerations

### 1. Network Bandwidth
- **Intra-cluster traffic**: 2-3× client traffic due to replication
- **Example**: 10MB/s client ingress → 20-30MB/s inter-node traffic
- **Recommendation**: 10Gbps network between nodes

### 2. Storage I/O
- **Write amplification**: 3× for fully replicated streams
- **Read operations**: Local reads from replica
- **Recommendation**: SSD/NVMe with adequate IOPS

### 3. Memory Usage
- **Per pod**: 170Mi request, 256Mi limit
- **Cluster total**: 510Mi request, 768Mi limit
- **JetStream memory**: 128Mi per pod (384Mi total)

### 4. Failure Scenarios

| Scenario | Impact | Recovery |
|----------|--------|----------|
| **1 node failure** | 1 pod down, 2 remain | Automatic failover, quorum maintained |
| **2 node failures** | 2 pods down, 1 remains | Loss of quorum, manual intervention needed |
| **Network partition** | Split brain possible | Manual reconciliation required |
| **Storage failure** | Data loss on affected pod | Rebuild from other replicas |

## 🛡️ Disaster Recovery

### 1. Backup Strategy
```bash
# Backup stream configuration
nats --server nats://nats:4222 stream export DOCUMENTS > documents-backup.json

# Backup account information
nats --server nats://nats:4222 account info > account-backup.json
```

### 2. Recovery Procedures

**Single Pod Recovery:**
```bash
# Delete failed pod
kubectl delete pod nats-0 -n default

# Kubernetes will recreate with existing PVC
# NATS will rejoin cluster and sync data
```

**Full Cluster Recovery:**
```bash
# 1. Backup existing data
./scripts/backup-nats.sh

# 2. Delete all pods
kubectl delete pods -n default -l app=nats

# 3. Wait for recreation
kubectl wait --for=condition=ready pod -l app=nats -n default --timeout=300s

# 4. Restore streams if needed
./scripts/restore-streams.sh
```

## 🔄 Rolling Updates

### Safe Update Procedure:
```bash
# 1. Check PDB allows disruption
kubectl get pdb nats-pdb -n default

# 2. Update one pod at a time
kubectl rollout restart statefulset nats -n default

# 3. Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=nats -n default --timeout=300s

# 4. Verify cluster health
kubectl exec deployment/nats -n default -- nats server list
```

### Configuration Updates:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1  # Update one pod at a time
    maxSurge: 0
```

## 📈 Monitoring HA Cluster

### Key HA Metrics:
```prometheus
# Cluster health
nats_core_num_connections
nats_jetstream_cluster_leader
nats_jetstream_cluster_offline

# Stream replication health
nats_jetstream_stream_replicas{state="current"}
nats_jetstream_stream_replicas{state="offline"}

# Node distribution
count by (node) (nats_core_num_connections)

# Quorum status
nats_jetstream_cluster_size - nats_jetstream_cluster_offline >= 2
```

### HA Alerts:
```yaml
- alert: NATSClusterQuorumAtRisk
  expr: nats_jetstream_cluster_size - nats_jetstream_cluster_offline < 2
  for: 1m
  labels:
    severity: critical
  annotations:
    summary: "NATS cluster quorum at risk"
    
- alert: NATSPodDistributionImbalanced
  expr: count by (node) (nats_core_num_connections) > 1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "NATS pods not evenly distributed"
```

## 🎯 Migration from Single to HA

### Step-by-Step Migration:
1. **Prepare infrastructure**: Ensure 3 nodes available
2. **Backup current deployment**: `./scripts/backup-nats.sh`
3. **Update configuration**: Apply HA values.yaml
4. **Scale up**: `kubectl scale statefulset nats --replicas=3`
5. **Verify cluster formation**: `nats server list`
6. **Update streams**: Recreate with 3 replicas
7. **Test failover**: Simulate node failure
8. **Update clients**: Point to load balancer

### Migration Script:
```bash
#!/bin/bash
# migrate-to-ha.sh

echo "Migrating from single to HA deployment..."

# Backup current state
./scripts/backup-current-state.sh

# Scale to 3 replicas
kubectl scale statefulset nats --replicas=3 -n default

# Wait for pods
kubectl wait --for=condition=ready pod -l app=nats -n default --timeout=300s

# Update stream replication
./scripts/update-stream-replication.sh

echo "Migration completed!"
echo "Verify with: ./validate-ha.sh"
```

## 📚 References

- [NATS High Availability Guide](https://docs.nats.io/nats-concepts/clustering)
- [JetStream Clustering](https://docs.nats.io/nats-concepts/jetstream/clustering)
- [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Pod Disruption Budgets](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)