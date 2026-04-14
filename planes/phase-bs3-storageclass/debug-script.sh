#!/bin/bash
# Debug version - run line by line

echo "Line 1: Starting"
set -euo pipefail
echo "Line 2: set done"

echo "=== SECTION 1 ==="
echo "Line 3: Checking cluster status..."
if kubectl get nodes -o wide &> /dev/null; then
    echo "Line 4: Cluster accessible"
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    echo "Line 5: Node count: $NODE_COUNT"
    READY_COUNT=$(kubectl get nodes --no-headers | grep -c "Ready")
    echo "Line 6: Ready count: $READY_COUNT"
    
    if [ "$READY_COUNT" -eq "$NODE_COUNT" ]; then
        echo "Line 7: All nodes ready"
    else
        echo "Line 8: Not all nodes ready"
    fi
else
    echo "Line 9: Cannot connect to cluster"
fi

echo "Line 10: Checking permissions..."
if kubectl auth can-i create storageclass 2>/dev/null | grep -q "yes"; then
    echo "Line 11: Has permissions"
else
    echo "Line 12: No permissions"
fi

echo "Line 13: Debug script completed"