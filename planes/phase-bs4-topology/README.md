# BS-4: Node Labeling for Topology Awareness

## Objective
Enable topology-aware scheduling for I/O-heavy workloads by labeling Kubernetes nodes based on their intended roles in the cluster architecture.

## Problem Statement
I/O-intensive workloads (PostgreSQL, MinIO) need to be scheduled on nodes with appropriate storage capabilities, while control plane and observability workloads should run on general-purpose nodes.

## Solution
Label 2 of 3 nodes as `storage-heavy` for PostgreSQL + MinIO placement, leaving 1 node general-purpose for control/observability workloads.

## Architecture

### Node Roles
| Node Type | Count | Label | Purpose |
|-----------|-------|-------|---------|
| Storage-Heavy | 2 | `node-role=storage-heavy` | PostgreSQL, MinIO, stateful workloads |
| General Purpose | 1 | (no label or `node-role=general`) | Control plane, monitoring, logging |

### Topology Labels
- **Zone Labels:** `topology.kubernetes.io/zone=zone-{1,2,3}` for availability zone awareness
- **Region Labels:** `topology.kubernetes.io/region=hetzner-fsn1` for regional awareness

## Implementation Scripts

### 1. Pre-deployment Check (`01-pre-deployment-check.sh`)
Validates prerequisites before deployment:
- Kubernetes cluster connectivity
- Node inventory and current labels
- Resource capacities
- Required tools (kubectl, jq)

### 2. Deployment (`02-deployment.sh`)
Applies node labels:
- Labels first 2 nodes as `storage-heavy`
- Adds topology zone and region labels
- Creates cleanup script
- Generates workload placement examples

### 3. Validation (`03-validation.sh`)
Verifies implementation:
- Validates label application
- Tests node selector functionality
- Generates comprehensive reports
- Provides next steps guidance

### 4. Complete Execution (`run-all.sh`)
Runs all phases sequentially with error handling and comprehensive logging.

## Usage

### Quick Start
```bash
# Make scripts executable
chmod +x *.sh

# Run complete implementation
./run-all.sh
```

### Individual Phases
```bash
# 1. Pre-deployment check
./01-pre-deployment-check.sh

# 2. Deployment
./02-deployment.sh

# 3. Validation
./03-validation.sh
```

### Cleanup
```bash
# Remove all labels
./cleanup-labels.sh
```

## Deliverables

### Scripts
- `01-pre-deployment-check.sh` - Pre-deployment validation
- `02-deployment.sh` - Node labeling implementation
- `03-validation.sh` - Post-deployment validation
- `run-all.sh` - Complete execution wrapper
- `cleanup-labels.sh` - Label removal utility

### Documentation
- `shared/topology.md` - Topology strategy documentation
- `NEXT_STEPS.md` - Post-implementation guidance (generated)
- `EXECUTION_SUMMARY.md` - Execution report (generated)

### Logs
- `logs/` - Execution logs directory
- `execution-*/` - Timestamped execution directories

## Validation Criteria

### Success Metrics
1. ✅ Exactly 2 nodes labeled `node-role=storage-heavy`
2. ✅ All nodes have topology zone labels
3. ✅ All nodes have topology region labels
4. ✅ Test pods schedule correctly on storage-heavy nodes
5. ✅ No storage-heavy labels on general purpose nodes

### Expected Output
```bash
kubectl get nodes -l node-role=storage-heavy
# Expected: 2 nodes labeled

kubectl get nodes --show-labels
# Expected: All nodes with zone/region labels
```

## Workload Placement Examples

### PostgreSQL Deployment
```yaml
nodeSelector:
  node-role: storage-heavy
  topology.kubernetes.io/zone: zone-1
```

### MinIO Deployment
```yaml
nodeSelector:
  node-role: storage-heavy
  topology.kubernetes.io/zone: zone-2
```

### Monitoring Stack
```yaml
nodeSelector:
  node-role: general  # or no selector for general nodes
```

## Error Handling

### Common Issues
1. **Insufficient nodes:** Script adapts to available node count
2. **Permission errors:** Checks kubectl permissions upfront
3. **Label conflicts:** Uses `--overwrite` flag to handle existing labels
4. **Cluster connectivity:** Validates cluster access before operations

### Recovery
```bash
# Complete reset
./cleanup-labels.sh
./run-all.sh
```

## Monitoring

### Regular Checks
```bash
# Label consistency
kubectl get nodes --show-labels

# Workload distribution
kubectl get pods -o wide | grep -E "(postgresql|minio)"

# Resource utilization
kubectl top nodes
```

### Alerting Rules
1. Alert if storage-heavy nodes < 2
2. Alert if any node missing topology labels
3. Alert if workloads scheduled on wrong node types

## Dependencies

### Required Tools
- `kubectl` - Kubernetes CLI
- `jq` - JSON processor (for advanced parsing)

### Cluster Requirements
- Kubernetes cluster with ≥ 1 node (≥ 3 recommended)
- kubectl configured with cluster access
- Sufficient permissions to label nodes

## Testing

### Local Testing
```bash
# Syntax check
bash -n *.sh

# Dry run (simulate)
./01-pre-deployment-check.sh
```

### VPS Testing
1. Copy scripts to VPS
2. Ensure kubectl access
3. Run `./run-all.sh`
4. Review validation results

## Security Considerations

### Permission Model
- Scripts require `kubectl` with node labeling permissions
- No elevated privileges needed beyond kubectl access
- Cleanup script provided for easy reversal

### Audit Trail
- All operations logged with timestamps
- Execution directories preserve complete logs
- No sensitive data in logs

## Maintenance

### Updates
- Review `shared/topology.md` for strategy changes
- Update validation criteria as needed
- Test scripts after cluster changes

### Scaling
- Scripts handle variable node counts
- Additional nodes can be labeled manually
- Zone distribution adjusts automatically

## References

### Kubernetes Documentation
- [Node Selection](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
- [Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)

### Related Phases
- BS-3: StorageClass with WaitForFirstConsumer
- Future: Workload deployment with nodeSelectors

## Support

### Troubleshooting
1. Check execution logs in `logs/` directory
2. Review validation report in `NEXT_STEPS.md`
3. Verify kubectl configuration and permissions

### Issues
- Ensure cluster has at least 1 ready node
- Verify kubectl can connect to cluster
- Check script permissions (chmod +x *.sh)

## License
Part of k3s deployment automation suite. See project LICENSE for details.