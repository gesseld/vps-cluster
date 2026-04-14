# BS-4: Next Steps for Topology Awareness

## Completed Tasks
✅ Node labeling for topology-aware scheduling
✅ Storage-heavy nodes identified and labeled
✅ Topology zone and region labels applied
✅ Validation completed

## Immediate Next Steps

### 1. Deploy Storage Workloads
- PostgreSQL: Use nodeSelector with `node-role: storage-heavy`
- MinIO: Use nodeSelector with `node-role: storage-heavy`
- Consider spreading across different zones for high availability

### 2. Configure Node Affinity/Anti-Affinity
Example for PostgreSQL StatefulSet:
```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node-role
          operator: In
          values:
          - storage-heavy
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app
            operator: In
            values:
            - postgresql
        topologyKey: topology.kubernetes.io/zone
```

### 3. Monitor Workload Placement
- Use `kubectl describe nodes` to see resource allocation
- Monitor pod distribution across zones
- Set up alerts for imbalanced scheduling

### 4. Consider Adding Taints
For stricter control:
```bash
kubectl taint nodes -l node-role=storage-heavy storage-heavy=true:NoSchedule
```
Then add corresponding tolerations to storage workloads.

## Validation Results
See: '$(basename "$VALIDATION_LOG")'

## Cleanup
If needed, run: `./cleanup-labels.sh`
