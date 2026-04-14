#!/bin/bash
# BS-3: StorageClass with WaitForFirstConsumer - Deployment Script
# Implements StorageClass with WaitForFirstConsumer for stateful workloads

set -euo pipefail

echo "================================================================"
echo "BS-3: STORAGECLASS WITH WAITFORFIRSTCONSUMER - DEPLOYMENT SCRIPT"
echo "================================================================"
echo "Objective: Ensure stateful workloads schedule to nodes with available NVMe before PVC binding"
echo "Date: $(date)"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/manifests"
LOG_FILE="$SCRIPT_DIR/deployment-$(date +%Y%m%d-%H%M%S).log"

# Create directories
mkdir -p "$MANIFESTS_DIR"
mkdir -p "$SCRIPT_DIR/logs"

# Function to log output
log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
    echo "$message"
}

# Function to check and exit on error
check_error() {
    if [ $1 -ne 0 ]; then
        log "${RED}ERROR: $2${NC}"
        exit 1
    fi
}

# Start deployment
log "${BLUE}=== Starting BS-3 StorageClass Deployment ===${NC}"

# ============================================================================
# TASK 1: PRE-FLIGHT VALIDATION
# ============================================================================
log "${YELLOW}=== Task 1: Pre-Flight Validation ===${NC}"

# Check if pre-deployment check was run
if [ -z "${CSI_DRIVER:-}" ]; then
    log "CSI_DRIVER not set. Running auto-detection..."
    
    # Try to detect CSI driver from existing StorageClasses
    if kubectl get storageclass &> /dev/null; then
        CSI_DRIVER=$(kubectl get storageclass -o jsonpath='{.items[0].provisioner}' 2>/dev/null || echo "")
    fi
    
    # Fallback to common CSI drivers
    if [ -z "$CSI_DRIVER" ]; then
        # Check for common CSI driver pods
        if kubectl get pods -n kube-system 2>/dev/null | grep -q "rke.csi"; then
            CSI_DRIVER="rke.csi.rancher.io"
        elif kubectl get pods -n kube-system 2>/dev/null | grep -q "csi.hetzner"; then
            CSI_DRIVER="csi.hetzner.cloud"
        elif kubectl get pods -n kube-system 2>/dev/null | grep -q "csi.longhorn"; then
            CSI_DRIVER="driver.longhorn.io"
        else
            CSI_DRIVER="rke.csi.rancher.io"  # Default for K3s
        fi
    fi
    
    log "Auto-detected CSI driver: $CSI_DRIVER"
fi

# Verify kubectl connectivity
log "Verifying kubectl connectivity..."
if ! kubectl get nodes &> /dev/null; then
    log "${RED}ERROR: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi
log "${GREEN}Connected to Kubernetes cluster${NC}"

# Verify permissions
log "Verifying kubectl permissions..."
if ! kubectl auth can-i create storageclass &> /dev/null; then
    log "${RED}ERROR: Insufficient permissions to create StorageClass${NC}"
    exit 1
fi
log "${GREEN}Has permissions to create StorageClass${NC}"

# ============================================================================
# TASK 2: CREATE STORAGECLASS MANIFEST
# ============================================================================
log "${YELLOW}=== Task 2: Create StorageClass Manifest ===${NC}"

# Create the StorageClass YAML
STORAGECLASS_YAML="$MANIFESTS_DIR/nvme-waitfirst-storageclass.yaml"

cat > "$STORAGECLASS_YAML" << EOF
# BS-3: StorageClass with WaitForFirstConsumer
# Purpose: Delay PVC binding until pod scheduling to ensure node has NVMe storage
# Compatible with: ${CSI_DRIVER}
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nvme-waitfirst
  labels:
    storage-type: nvme-optimized
    binding-mode: wait-for-first-consumer
    provisioner: ${CSI_DRIVER}
  annotations:
    description: "StorageClass with WaitForFirstConsumer binding mode for NVMe-optimized workloads"
    documentation: "https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode"
provisioner: ${CSI_DRIVER}
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
parameters:
  # CSI driver specific parameters
  csi.storage.k8s.io/fstype: ext4
  # Add any driver-specific parameters here
  # For Rancher CSI: (none required)
  # For Hetzner CSI: type: premium-nvme
  # For Longhorn: numberOfReplicas: "3"
EOF

log "Created StorageClass manifest: $STORAGECLASS_YAML"
log "CSI Driver: $CSI_DRIVER"
log "Volume Binding Mode: WaitForFirstConsumer"
log "Allow Volume Expansion: true"
log "Reclaim Policy: Retain"

# Add driver-specific parameters
if [[ "$CSI_DRIVER" == "csi.hetzner.cloud" ]]; then
    echo "  type: premium-nvme" >> "$STORAGECLASS_YAML"
    log "Added Hetzner CSI parameter: type: premium-nvme"
elif [[ "$CSI_DRIVER" == "driver.longhorn.io" ]]; then
    echo "  numberOfReplicas: \"3\"" >> "$STORAGECLASS_YAML"
    echo "  staleReplicaTimeout: \"2880\"" >> "$STORAGECLASS_YAML"
    echo "  fromBackup: \"\"" >> "$STORAGECLASS_YAML"
    log "Added Longhorn CSI parameters"
fi

# ============================================================================
# TASK 3: DEPLOY STORAGECLASS
# ============================================================================
log "${YELLOW}=== Task 3: Deploy StorageClass ===${NC}"

# Check if StorageClass already exists
if kubectl get storageclass nvme-waitfirst &> /dev/null; then
    log "${YELLOW}StorageClass 'nvme-waitfirst' already exists. Updating...${NC}"
    
    # Delete existing StorageClass
    kubectl delete storageclass nvme-waitfirst
    check_error $? "Failed to delete existing StorageClass"
    log "${GREEN}Deleted existing StorageClass${NC}"
    
    # Wait a moment
    sleep 2
fi

# Apply the StorageClass
log "Applying StorageClass manifest..."
kubectl apply -f "$STORAGECLASS_YAML"
check_error $? "Failed to apply StorageClass"
log "${GREEN}StorageClass 'nvme-waitfirst' created successfully${NC}"

# Verify creation
log "Verifying StorageClass creation..."
if kubectl get storageclass nvme-waitfirst &> /dev/null; then
    log "${GREEN}StorageClass verification passed${NC}"
else
    log "${RED}ERROR: StorageClass creation verification failed${NC}"
    exit 1
fi

# ============================================================================
# TASK 4: DOCUMENT CSI DRIVER COMPATIBILITY
# ============================================================================
log "${YELLOW}=== Task 4: Document CSI Driver Compatibility ===${NC}"

# Create documentation
DOC_FILE="$SCRIPT_DIR/CSI_DRIVER_COMPATIBILITY.md"

cat > "$DOC_FILE" << EOF
# CSI Driver Compatibility for nvme-waitfirst StorageClass

## Overview
This document outlines the compatibility of the \`nvme-waitfirst\` StorageClass with various CSI drivers.

## Current Configuration
- **CSI Driver**: \`${CSI_DRIVER}\`
- **Volume Binding Mode**: \`WaitForFirstConsumer\`
- **Allow Volume Expansion**: \`true\`
- **Reclaim Policy**: \`Retain\`

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
- \`type: premium-nvme\` (for NVMe volumes)
- \`type: premium\` (for SSD volumes)
- WaitForFirstConsumer works with node topology labels

### 3. Longhorn (driver.longhorn.io)
**Status**: ✅ Fully Supported
**Environment**: Longhorn distributed block storage
**Parameters**:
- \`numberOfReplicas: "3"\` (default)
- \`staleReplicaTimeout: "2880"\`
- WaitForFirstConsumer ensures replicas are placed appropriately

### 4. AWS EBS CSI (ebs.csi.aws.com)
**Status**: ⚠️ Conditionally Supported
**Requirements**:
- Requires \`allowedTopologies\` for zone awareness
- Node labels: \`topology.ebs.csi.aws.com/zone\`
- Example parameters:
  \`\`\`yaml
  parameters:
    type: gp3
    encrypted: "true"
  allowedTopologies:
  - matchLabelExpressions:
    - key: topology.ebs.csi.aws.com/zone
      values:
      - us-east-1a
      - us-east-1b
  \`\`\`

### 5. Azure Disk CSI (disk.csi.azure.com)
**Status**: ⚠️ Conditionally Supported
**Requirements**:
- Requires \`skuName\` parameter
- Node labels for topology
- Example parameters:
  \`\`\`yaml
  parameters:
    skuName: Premium_LRS
  \`\`\`

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
   - \`topology.kubernetes.io/zone\`
   - \`topology.kubernetes.io/region\`
2. CSI driver support for topology
3. Kubernetes ≥1.13

## Testing Procedure

### 1. Basic Test
\`\`\`bash
# Create test PVC
kubectl apply -f test-pvc.yaml

# Create test Pod
kubectl apply -f test-pod.yaml

# Verify volume binding
kubectl get pvc test-pvc -o jsonpath='{.status.phase}'
\`\`\`

### 2. Topology Test
\`\`\`bash
# Check node labels
kubectl get nodes --show-labels | grep topology

# Check StorageClass
kubectl get storageclass nvme-waitfirst -o yaml
\`\`\`

## Troubleshooting

### Common Issues

1. **PVC stuck in Pending**
   - Check CSI driver pods: \`kubectl get pods -n kube-system | grep csi\`
   - Check StorageClass: \`kubectl get storageclass nvme-waitfirst -o yaml\`
   - Check events: \`kubectl describe pvc <pvc-name>\`

2. **Volume not created**
   - Verify WaitForFirstConsumer mode: \`kubectl get sc nvme-waitfirst -o jsonpath='{.volumeBindingMode}'\`
   - Check pod scheduling: \`kubectl describe pod <pod-name>\`

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
Update the \`parameters\` section in the StorageClass manifest based on your CSI driver.

## References
- [Kubernetes Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Volume Binding Modes](https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode)
- [CSI Specification](https://kubernetes-csi.github.io/docs/)
EOF

log "Created compatibility documentation: $DOC_FILE"

# ============================================================================
# TASK 5: CREATE TEST MANIFESTS
# ============================================================================
log "${YELLOW}=== Task 5: Create Test Manifests ===${NC}"

# Create test PVC
TEST_PVC_YAML="$MANIFESTS_DIR/test-pvc-waitfirst.yaml"

cat > "$TEST_PVC_YAML" << EOF
# Test PVC for nvme-waitfirst StorageClass
# Purpose: Verify WaitForFirstConsumer behavior
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc-waitfirst
  labels:
    test: storageclass-waitfirst
    purpose: validation
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nvme-waitfirst
  resources:
    requests:
      storage: 1Gi
EOF

# Create test Pod
TEST_POD_YAML="$MANIFESTS_DIR/test-pod-waitfirst.yaml"

cat > "$TEST_POD_YAML" << EOF
# Test Pod for nvme-waitfirst StorageClass
# Purpose: Trigger PVC binding with WaitForFirstConsumer
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-waitfirst
  labels:
    test: storageclass-waitfirst
    purpose: validation
spec:
  containers:
  - name: test-container
    image: busybox:latest
    command: ["sh", "-c", "echo 'PVC successfully bound with WaitForFirstConsumer' && sleep 3600"]
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: test-pvc-waitfirst
  restartPolicy: Never
EOF

# Create topology-aware test (if nodes have zone labels)
TOPOLOGY_TEST_YAML="$MANIFESTS_DIR/test-topology-aware.yaml"

cat > "$TOPOLOGY_TEST_YAML" << EOF
# Topology-aware test for WaitForFirstConsumer
# Purpose: Demonstrate topology-constrained scheduling
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: topology-test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nvme-waitfirst
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: topology-test-pod
spec:
  containers:
  - name: app
    image: nginx:alpine
    volumeMounts:
    - name: data
      mountPath: /usr/share/nginx/html
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: topology-test-pvc
  # Optional: Add node selector for specific zone
  # nodeSelector:
  #   topology.kubernetes.io/zone: us-east-1a
EOF

log "Created test manifests:"
log "  - $TEST_PVC_YAML"
log "  - $TEST_POD_YAML"
log "  - $TOPOLOGY_TEST_YAML"

# ============================================================================
# TASK 6: DEPLOYMENT SUMMARY
# ============================================================================
log "${YELLOW}=== Task 6: Deployment Summary ===${NC}"

# Create deployment summary
SUMMARY_FILE="$SCRIPT_DIR/DEPLOYMENT_SUMMARY.md"

cat > "$SUMMARY_FILE" << EOF
# BS-3: StorageClass with WaitForFirstConsumer - Deployment Summary

## Deployment Information
- **Date**: $(date)
- **CSI Driver**: ${CSI_DRIVER}
- **StorageClass Name**: nvme-waitfirst
- **Volume Binding Mode**: WaitForFirstConsumer
- **Status**: ✅ Deployment Completed Successfully

## What Was Deployed

### 1. StorageClass Configuration
\`\`\`yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nvme-waitfirst
provisioner: ${CSI_DRIVER}
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
\`\`\`

### 2. Key Features
- **WaitForFirstConsumer**: Delays PVC binding until pod scheduling
- **Volume Expansion**: Allows volume resizing (future growth)
- **Retain Policy**: Prevents accidental data deletion
- **NVMe Optimization**: Designed for stateful workloads with NVMe storage

### 3. Created Files
- \`manifests/nvme-waitfirst-storageclass.yaml\` - StorageClass definition
- \`manifests/test-pvc-waitfirst.yaml\` - Test PVC
- \`manifests/test-pod-waitfirst.yaml\` - Test Pod
- \`manifests/test-topology-aware.yaml\` - Topology test
- \`CSI_DRIVER_COMPATIBILITY.md\` - Driver documentation
- \`deployment-*.log\` - Deployment logs

## Validation Steps

### Quick Validation
\`\`\`bash
# Check StorageClass
kubectl get storageclass nvme-waitfirst

# Verify binding mode
kubectl get storageclass nvme-waitfirst -o jsonpath='{.volumeBindingMode}'

# Expected output: WaitForFirstConsumer
\`\`\`

### Full Test
\`\`\`bash
# Apply test manifests
kubectl apply -f manifests/test-pvc-waitfirst.yaml
kubectl apply -f manifests/test-pod-waitfirst.yaml

# Check PVC status (should be Pending until pod schedules)
kubectl get pvc test-pvc-waitfirst

# Check Pod status
kubectl get pod test-pod-waitfirst

# Cleanup test
kubectl delete -f manifests/test-pod-waitfirst.yaml
kubectl delete -f manifests/test-pvc-waitfirst.yaml
\`\`\`

## Next Steps

### 1. Immediate Actions
- Run validation script: \`03-validation.sh\`
- Test with a real workload
- Document any issues encountered

### 2. Medium-term Actions
- Label nodes with storage type (nvme/ssd)
- Update application manifests to use new StorageClass
- Monitor volume provisioning performance

### 3. Long-term Actions
- Consider implementing storage quotas
- Set up monitoring for volume usage
- Plan for volume migration if needed

## Troubleshooting

### Common Issues

1. **PVC stuck in Pending**
   \`\`\`bash
   kubectl describe pvc <pvc-name>
   kubectl get events --sort-by='.lastTimestamp'
   \`\`\`

2. **CSI driver issues**
   \`\`\`bash
   kubectl get pods -n kube-system | grep csi
   kubectl logs -n kube-system <csi-pod-name>
   \`\`\`

3. **Topology problems**
   \`\`\`bash
   kubectl get nodes --show-labels | grep topology
   \`\`\`

## References
- [StorageClass Documentation](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [WaitForFirstConsumer Mode](https://kubernetes.io/docs/concepts/storage/storage-classes/#volume-binding-mode)
- [CSI Driver Compatibility](CSI_DRIVER_COMPATIBILITY.md)
EOF

log "Created deployment summary: $SUMMARY_FILE"

# ============================================================================
# DEPLOYMENT COMPLETE
# ============================================================================
log "${BLUE}=== Deployment Complete ===${NC}"
echo ""
echo -e "${GREEN}✅ BS-3 STORAGECLASS DEPLOYMENT SUCCESSFUL${NC}"
echo ""
echo "Summary:"
echo "  - StorageClass 'nvme-waitfirst' created with WaitForFirstConsumer"
echo "  - CSI Driver: $CSI_DRIVER"
echo "  - Test manifests created in: $MANIFESTS_DIR"
echo "  - Documentation: $DOC_FILE"
echo "  - Summary: $SUMMARY_FILE"
echo ""
echo "Next steps:"
echo "  1. Run validation script: 03-validation.sh"
echo "  2. Test with real workloads"
echo "  3. Monitor volume provisioning"
echo ""
echo "Log file: $LOG_FILE"
echo "================================================================"