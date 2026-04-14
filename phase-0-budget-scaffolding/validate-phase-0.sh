#!/bin/bash
set -e

echo "=== Phase 0: Budget Scaffolding Validation ==="
echo ""

# Check PriorityClasses
echo "1. PriorityClasses:"
kubectl get priorityclass | grep foundation || echo "❌ No foundation PriorityClasses found"

# Check ResourceQuotas
echo ""
echo "2. ResourceQuotas:"
for ns in control-plane data-plane observability-plane; do
  echo "  $ns:"
  kubectl get resourcequota -n $ns 2>/dev/null || echo "    ❌ Not found"
done

# Check LimitRanges
echo ""
echo "3. LimitRanges:"
for ns in control-plane data-plane observability-plane; do
  echo "  $ns:"
  kubectl get limitrange -n $ns 2>/dev/null || echo "    ❌ Not found"
done

# Check StorageClass
echo ""
echo "4. StorageClass:"
kubectl get storageclass nvme-waitfirst -o jsonpath='{.volumeBindingMode}' 2>/dev/null && echo "  ✅ WaitForFirstConsumer" || echo "  ❌ Not found"

# Check Node Labels
echo ""
echo "5. Node Labels:"
kubectl get nodes -l node-role=storage-heavy -o name | wc -l | xargs echo "  storage-heavy nodes:"

# Check NetworkPolicy CRD
echo ""
echo "6. NetworkPolicy CRD:"
kubectl api-resources | grep -q networkpolicies && echo "  ✅ Available" || echo "  ❌ Not available"

echo ""
echo "=== Phase 0 Validation Complete ==="
