# Topology-Aware Scheduling Strategy

## Objective
Enable topology-aware scheduling for I/O-heavy workloads by labeling nodes based on their intended roles in the cluster architecture.

## Node Labeling Strategy

### 1. Storage-Heavy Nodes (2 of 3 nodes)
**Purpose:** Host I/O-intensive stateful workloads
**Label:** `node-role=storage-heavy`
**Workloads:**
- PostgreSQL databases
- MinIO object storage
- Other stateful applications requiring high I/O

**Characteristics:**
- Prioritized for storage-intensive operations
- Should have better I/O performance (NVMe/SSD)
- Isolated from control plane noise

### 2. General Purpose Nodes (1 of 3 nodes)
**Purpose:** Host control plane and observability workloads
**Label:** No specific `node-role` label (or `node-role=general`)
**Workloads:**
- Kubernetes control plane components
- Monitoring stack (Prometheus, Grafana, Loki)
- Logging infrastructure
- Service mesh control plane

**Characteristics:**
- Lower I/O requirements
- Higher CPU for control plane operations
- Centralized observability

## Topology Labels

### Zone Labels
**Purpose:** Enable zone-aware scheduling for high availability
**Label:** `topology.kubernetes.io/zone=zone-{1,2,3}`
**Strategy:** Distribute storage-heavy nodes across different zones when possible

### Region Labels
**Purpose:** Regional awareness for multi-region deployments
**Label:** `topology.kubernetes.io/region=hetzner-fsn1`
**Note:** All nodes in same region for this deployment

## Workload Placement Rules

### 1. Mandatory Placement (NodeSelector)
```yaml
# For PostgreSQL
nodeSelector:
  node-role: storage-heavy
  topology.kubernetes.io/zone: zone-1

# For MinIO
nodeSelector:
  node-role: storage-heavy
  topology.kubernetes.io/zone: zone-2
```

### 2. Preferred Placement (NodeAffinity)
```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: node-role
          operator: In
          values:
          - storage-heavy
```

### 3. Anti-Affinity for High Availability
```yaml
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchExpressions:
      - key: app
        operator: In
        values:
        - postgresql
    topologyKey: topology.kubernetes.io/zone
```

## Taints and Tolerations (Optional)

For stricter control, consider adding taints:

```bash
# Add taint to storage-heavy nodes
kubectl taint nodes -l node-role=storage-heavy storage-heavy=true:NoSchedule

# Corresponding toleration in workload
tolerations:
- key: "storage-heavy"
  operator: "Equal"
  value: "true"
  effect: "NoSchedule"
```

## Validation Criteria

### Success Criteria
1. ✅ Exactly 2 nodes labeled `node-role=storage-heavy`
2. ✅ All nodes have `topology.kubernetes.io/zone` labels
3. ✅ All nodes have `topology.kubernetes.io/region` labels
4. ✅ Test pods schedule correctly on storage-heavy nodes
5. ✅ No storage-heavy labels on general purpose nodes

### Failure Scenarios
1. ❌ Less than 2 nodes available for storage-heavy labeling
2. ❌ Nodes not ready or accessible
3. ❌ Insufficient permissions to label nodes
4. ❌ Existing labels conflict with new labeling strategy

## Recovery Procedures

### 1. Label Conflicts
```bash
# Remove conflicting labels
kubectl label node <node-name> node-role-
kubectl label node <node-name> topology.kubernetes.io/zone-
kubectl label node <node-name> topology.kubernetes.io/region-
```

### 2. Complete Reset
```bash
# Run cleanup script
./cleanup-labels.sh
# Re-run deployment
./02-deployment.sh
```

## Scaling Considerations

### Adding More Nodes
1. **Storage-heavy expansion:** Label new nodes with `node-role=storage-heavy`
2. **General purpose expansion:** Leave unlabeled or use `node-role=general`
3. **Zone distribution:** Assign new zones for better HA

### Node Failure Recovery
1. **Storage-heavy node failure:** 
   - Workloads rescheduled to other storage-heavy nodes
   - Consider adding replacement node with same labels
2. **General purpose node failure:**
   - Control plane components should be highly available
   - Observability stack can be rescheduled

## Monitoring and Maintenance

### Regular Checks
```bash
# Check label consistency
kubectl get nodes --show-labels

# Verify workload distribution
kubectl get pods -o wide | grep -E "(postgresql|minio)"

# Check node resource utilization
kubectl top nodes
```

### Alerting Rules
1. Alert if storage-heavy nodes < 2
2. Alert if any node missing topology labels
3. Alert if workloads scheduled on wrong node types

## Implementation Scripts

### Main Scripts
- `01-pre-deployment-check.sh`: Validate prerequisites
- `02-deployment.sh`: Apply node labels
- `03-validation.sh`: Verify implementation
- `cleanup-labels.sh`: Remove all labels

### Support Files
- `shared/topology.md`: This documentation
- `logs/`: Execution logs
- `NEXT_STEPS.md`: Post-implementation guidance

## References

### Kubernetes Documentation
- [Node Selection](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)

### Best Practices
- Always test labeling strategy in non-production first
- Document all custom labels and their purposes
- Consider future scaling when designing topology
- Monitor actual workload performance after implementation