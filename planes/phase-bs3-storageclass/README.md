# BS-3: StorageClass with WaitForFirstConsumer

## Objective
Ensure stateful workloads schedule to nodes with available NVMe storage before PVC binding by implementing a StorageClass with `volumeBindingMode: WaitForFirstConsumer`.

## Problem Statement
Traditional StorageClasses with `Immediate` binding mode create volumes immediately when a PVC is created, which can lead to:
- Orphaned volumes if pods fail to schedule
- Suboptimal placement (volume created in wrong zone/region)
- Inefficient use of NVMe storage resources

## Solution
Create a StorageClass with `WaitForFirstConsumer` binding mode that delays volume provisioning until a pod is scheduled, ensuring:
1. Volume created in same topology as pod
2. NVMe storage allocated only when needed
3. Better resource utilization

## Scripts Overview

### 1. `01-pre-deployment-check.sh`
**Purpose**: Validate all prerequisites before creating StorageClass
**Checks**:
- Kubernetes cluster connectivity
- kubectl permissions
- Existing StorageClasses and CSI drivers
- Node topology labels
- Required CLI tools (kubectl, jq, envsubst)
- CSI driver compatibility

### 2. `02-deployment.sh`
**Purpose**: Implement StorageClass with WaitForFirstConsumer
**Tasks**:
1. Pre-flight validation
2. Create StorageClass manifest (auto-detects CSI driver)
3. Deploy StorageClass to cluster
4. Document CSI driver compatibility
5. Create test manifests for validation
6. Generate deployment summary

### 3. `03-validation.sh`
**Purpose**: Verify StorageClass implementation
**Tests**:
1. Basic StorageClass validation (exists, correct binding mode)
2. WaitForFirstConsumer behavior test
3. Topology validation (node labels)
4. Cleanup and final verification
5. Generate validation report

## Key Files

### Manifests (created during deployment):
- `manifests/nvme-waitfirst-storageclass.yaml` - Dynamic StorageClass based on CSI driver
- `manifests/test-pvc-waitfirst.yaml` - Test PVC
- `manifests/test-pod-waitfirst.yaml` - Test Pod
- `manifests/test-topology-aware.yaml` - Topology test

### Documentation:
- `CSI_DRIVER_COMPATIBILITY.md` - Driver compatibility guide
- `DEPLOYMENT_SUMMARY.md` - Deployment summary
- `VALIDATION_REPORT.md` - Validation results
- `shared-storage-classes.yaml` - Reference manifests

## Usage Workflow

### Phase 1: Pre-Deployment Check
```bash
cd planes/phase-bs3-storageclass
./01-pre-deployment-check.sh
```
**Expected**: All checks pass or have acceptable warnings

### Phase 2: Deployment
```bash
./02-deployment.sh
```
**Creates**: StorageClass, documentation, test manifests

### Phase 3: Validation
```bash
./03-validation.sh
```
**Verifies**: StorageClass works correctly with WaitForFirstConsumer

## StorageClass Configuration

### Core Settings:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nvme-waitfirst
provisioner: <auto-detected-csi-driver>
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
```

### Supported CSI Drivers:
- **Rancher CSI** (`rke.csi.rancher.io`) - K3s/RKE2 default
- **Hetzner Cloud CSI** (`csi.hetzner.cloud`) - Hetzner Cloud
- **Longhorn** (`driver.longhorn.io`) - Distributed storage
- **AWS EBS CSI** (`ebs.csi.aws.com`) - AWS
- **Azure Disk CSI** (`disk.csi.azure.com`) - Azure
- **GCP PD CSI** (`pd.csi.storage.gke.io`) - GCP

## WaitForFirstConsumer Behavior

### How It Works:
1. **PVC Creation**: PVC created but remains in `Pending` state
2. **Pod Scheduling**: Pod scheduled to a node based on constraints
3. **Volume Provisioning**: CSI driver creates volume in same topology as pod
4. **Binding**: PVC binds to newly created volume

### Benefits:
- **Topology Awareness**: Volume created in same zone/region as pod
- **Cost Optimization**: Avoids orphaned volumes
- **NVMe Optimization**: Ensures pod scheduled to node with NVMe storage
- **Better Scheduling**: Scheduler considers storage availability

## Validation Tests

### Quick Validation:
```bash
kubectl get storageclass nvme-waitfirst -o jsonpath='{.volumeBindingMode}'
# Expected: WaitForFirstConsumer
```

### Full Test:
```bash
# Apply test manifests
kubectl apply -f manifests/test-pvc-waitfirst.yaml
kubectl apply -f manifests/test-pod-waitfirst.yaml

# Check PVC status (should be Pending, then Bound)
kubectl get pvc test-pvc-waitfirst -w
```

## Requirements

### Kubernetes:
- Version ≥ 1.13 (WaitForFirstConsumer support)
- CSI driver installed
- Node topology labels (recommended)

### Node Labels (for optimal behavior):
```bash
# Zone labels
kubectl label nodes <node-name> topology.kubernetes.io/zone=<zone>

# Region labels  
kubectl label nodes <node-name> topology.kubernetes.io/region=<region>

# Storage type labels (optional)
kubectl label nodes <node-name> storage-type=nvme
```

## Troubleshooting

### Common Issues:

1. **PVC stuck in Pending**:
   ```bash
   kubectl describe pvc <pvc-name>
   kubectl get events --sort-by='.lastTimestamp'
   ```

2. **CSI driver not found**:
   ```bash
   kubectl get pods -n kube-system | grep csi
   kubectl logs -n kube-system <csi-pod-name>
   ```

3. **Wrong binding mode**:
   ```bash
   kubectl get sc nvme-waitfirst -o jsonpath='{.volumeBindingMode}'
   kubectl edit storageclass nvme-waitfirst
   ```

4. **No topology labels**:
   ```bash
   kubectl get nodes --show-labels | grep topology
   # Add labels if missing
   ```

## Deliverables

✅ **Pre-deployment script** - Validates prerequisites  
✅ **Deployment script** - Implements StorageClass  
✅ **Validation script** - Verifies implementation  
✅ **StorageClass manifest** - `nvme-waitfirst` with WaitForFirstConsumer  
✅ **Test manifests** - PVC and Pod for validation  
✅ **Documentation** - Compatibility guide and usage instructions  
✅ **Validation command** - From task requirements:
   ```bash
   kubectl get storageclass nvme-waitfirst -o jsonpath='{.volumeBindingMode}'
   # Expected: WaitForFirstConsumer
   ```

## References
- [Kubernetes Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Volume Binding Modes](https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode)
- [CSI Specification](https://kubernetes-csi.github.io/docs/)
- [Topology-aware Volume Provisioning](https://kubernetes.io/docs/concepts/storage/storage-classes/#topology)