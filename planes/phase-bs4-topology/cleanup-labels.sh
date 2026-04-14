#!/bin/bash
echo "Cleaning up node labels..."
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
for NODE in $NODES; do
    echo "Cleaning labels on node: $NODE"
    kubectl label node "$NODE" node-role- 2>/dev/null || true
    kubectl label node "$NODE" topology.kubernetes.io/zone- 2>/dev/null || true
    kubectl label node "$NODE" topology.kubernetes.io/region- 2>/dev/null || true
done
echo "✅ Labels cleaned up"
