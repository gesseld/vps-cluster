#!/bin/bash
# BS-3: Simple Validation Script
# Validates that StorageClass with WaitForFirstConsumer was created successfully

echo "================================================================"
echo "BS-3: STORAGECLASS WITH WAITFORFIRSTCONSUMER - SIMPLE VALIDATION"
echo "================================================================"
echo "Date: $(date)"
echo ""

# Simple validation
echo "=== VALIDATION CHECKS ==="
echo ""

# 1. Check if StorageClass exists
echo "1. Checking if StorageClass 'nvme-waitfirst' exists..."
if kubectl get storageclass nvme-waitfirst &> /dev/null; then
    echo "✅ PASS: StorageClass 'nvme-waitfirst' exists"
else
    echo "❌ FAIL: StorageClass 'nvme-waitfirst' not found"
    exit 1
fi

# 2. Check volumeBindingMode
echo "2. Checking volumeBindingMode..."
BINDING_MODE=$(kubectl get storageclass nvme-waitfirst -o jsonpath='{.volumeBindingMode}' 2>/dev/null || echo "")
if [ "$BINDING_MODE" = "WaitForFirstConsumer" ]; then
    echo "✅ PASS: volumeBindingMode is WaitForFirstConsumer"
else
    echo "❌ FAIL: volumeBindingMode is '$BINDING_MODE' (expected: WaitForFirstConsumer)"
    exit 1
fi

# 3. Check allowVolumeExpansion
echo "3. Checking allowVolumeExpansion..."
ALLOW_EXPANSION=$(kubectl get storageclass nvme-waitfirst -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null || echo "")
if [ "$ALLOW_EXPANSION" = "true" ]; then
    echo "✅ PASS: allowVolumeExpansion is true"
else
    echo "⚠️  WARN: allowVolumeExpansion is '$ALLOW_EXPANSION' (expected: true)"
fi

# 4. Check reclaimPolicy
echo "4. Checking reclaimPolicy..."
RECLAIM_POLICY=$(kubectl get storageclass nvme-waitfirst -o jsonpath='{.reclaimPolicy}' 2>/dev/null || echo "")
if [ "$RECLAIM_POLICY" = "Retain" ]; then
    echo "✅ PASS: reclaimPolicy is Retain"
else
    echo "⚠️  WARN: reclaimPolicy is '$RECLAIM_POLICY' (expected: Retain)"
fi

# 5. Check provisioner
echo "5. Checking provisioner..."
PROVISIONER=$(kubectl get storageclass nvme-waitfirst -o jsonpath='{.provisioner}' 2>/dev/null || echo "")
if [ -n "$PROVISIONER" ]; then
    echo "✅ PASS: Provisioner is $PROVISIONER"
else
    echo "❌ FAIL: No provisioner specified"
    exit 1
fi

# 6. Test the validation command from task requirements
echo ""
echo "=== TASK VALIDATION COMMAND ==="
echo "Running: kubectl get storageclass nvme-waitfirst -o jsonpath='{.volumeBindingMode}'"
RESULT=$(kubectl get storageclass nvme-waitfirst -o jsonpath='{.volumeBindingMode}' 2>/dev/null || echo "")
echo "Result: $RESULT"
if [ "$RESULT" = "WaitForFirstConsumer" ]; then
    echo "✅ SUCCESS: Validation command returns expected result: WaitForFirstConsumer"
else
    echo "❌ FAIL: Validation command returned '$RESULT' (expected: WaitForFirstConsumer)"
    exit 1
fi

echo ""
echo "================================================================"
echo "VALIDATION SUMMARY"
echo "================================================================"
echo "✅ All critical checks passed"
echo ""
echo "StorageClass Details:"
echo "---------------------"
kubectl get storageclass nvme-waitfirst -o jsonpath='{
    "Name: "}{.metadata.name}{"\n"
    "Provisioner: "}{.provisioner}{"\n"
    "Binding Mode: "}{.volumeBindingMode}{"\n"
    "Allow Expansion: "}{.allowVolumeExpansion}{"\n"
    "Reclaim Policy: "}{.reclaimPolicy}{"\n"
}' 2>/dev/null

echo ""
echo "Next steps:"
echo "1. Test with PVC creation: kubectl apply -f manifests/test-pvc-waitfirst.yaml"
echo "2. Test WaitForFirstConsumer behavior with Pod: kubectl apply -f manifests/test-pod-waitfirst.yaml"
echo "3. Monitor volume provisioning in your applications"
echo ""
echo "Validation completed successfully at: $(date)"