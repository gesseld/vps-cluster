# CSI Driver Compatibility for nvme-waitfirst StorageClass

## Overview
This document outlines the compatibility of the `nvme-waitfirst` StorageClass with various CSI drivers.

## Current Configuration
- **CSI Driver**: `csi.hetzner.cloud`
- **Volume Binding Mode**: `WaitForFirstConsumer`
- **Allow Volume Expansion**: `true`
- **Reclaim Policy**: `Retain`

## Supported CSI Drivers

### 1. Rancher CSI (rke.csi.rancher.io)
**Status**: ✅ Fully Supported
**Environment**: K3s/RKE2 default
**Parameters**:
- No additional parameters required
- Uses default filesystem: ext4
- Compatible with WaitForFirstConsumer

### 2. Hetzner Cloud CSI (csi.hetzner.cloud)
**Status**: ✅ Fully Supported
**Environment**: Hetzner Cloud K8s
**Parameters**:
- `type: premium-nvme` (for NVMe volumes)
- `type: premium` (for SSD volumes)
- WaitForFirstConsumer works with node topology labels

### 3. Longhorn (driver.longhorn.io)
**Status**: ✅ Fully Supported
**Environment**: Longhorn distributed block storage
**Parameters**:
- `numberOfReplicas: "3"` (default)
- `staleReplicaTimeout: "2880"`
- WaitForFirstConsumer ensures replicas are placed appropriately

### 4. AWS EBS CSI (ebs.csi.aws.com)
**Status**: ⚠️ Conditionally Supported
**Requirements**:
- Requires `allowedTopologies` for zone awareness
- Node labels: `topology.ebs.csi.aws.com/zone`
- Example parameters:
  ```yaml
  parameters:
    type: gp3
    encrypted: "true"
  allowedTopologies:
  - matchLabelExpressions:
    - key: topology.ebs.csi.aws.com/zone
      values:
      - us-east-1a
      - us-east-1b
  ```

### 5. Azure Disk CSI (disk.csi.azure.com)
**Status**: ⚠️ Conditionally Supported
**Requirements**:
- Requires `skuName` parameter
- Node labels for topology
- Example parameters:
  ```yaml
  parameters:
    skuName: Premium_LRS
  ```

## WaitForFirstConsumer Behavior

### How It Works
1. PVC creation does NOT immediately trigger volume provisioning
2. Volume provisioning occurs when:
   - A Pod is scheduled that uses the PVC
   - The scheduler considers node topology constraints
   - The CSI driver creates volume on appropriate node/zone

### Benefits
- **Topology Awareness**: Volumes created in same zone/region as pod
- **Cost Optimization**: Avoids orphaned volumes
- **NVMe Optimization**: Ensures pod scheduled to node with NVMe storage

### Requirements
1. Node topology labels:
   - `topology.kubernetes.io/zone`
   - `topology.kubernetes.io/region`
2. CSI driver support for topology
3. Kubernetes ≥1.13

## Testing Procedure

### 1. Basic Test
```bash
# Create test PVC
kubectl apply -f test-pvc.yaml

# Create test Pod
kubectl apply -f test-pod.yaml

# Verify volume binding
kubectl get pvc test-pvc -o jsonpath='{.status.phase}'
```

### 2. Topology Test
```bash
# Check node labels
kubectl get nodes --show-labels | grep topology

# Check StorageClass
kubectl get storageclass nvme-waitfirst -o yaml
```

## Troubleshooting

### Common Issues

1. **PVC stuck in Pending**
   - Check CSI driver pods: `kubectl get pods -n kube-system | grep csi`
   - Check StorageClass: `kubectl get storageclass nvme-waitfirst -o yaml`
   - Check events: `kubectl describe pvc <pvc-name>`

2. **Volume not created**
   - Verify WaitForFirstConsumer mode: `kubectl get sc nvme-waitfirst -o jsonpath='{.volumeBindingMode}'`
   - Check pod scheduling: `kubectl describe pod <pod-name>`

3. **Wrong storage type**
   - Update StorageClass parameters for your CSI driver
   - Delete and recreate StorageClass

## Migration Guide

### From ImmediateBinding to WaitForFirstConsumer
1. Create new StorageClass with WaitForFirstConsumer
2. Update PVC templates to use new StorageClass
3. Test with non-critical workloads first
4. Migrate existing PVCs (requires recreation)

### Driver-Specific Configuration
Update the `parameters` section in the StorageClass manifest based on your CSI driver.

## References
- [Kubernetes Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Volume Binding Modes](https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode)
- [CSI Specification](https://kubernetes-csi.github.io/docs/)
