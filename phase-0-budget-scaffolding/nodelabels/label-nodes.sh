#!/bin/bash
set -e

echo "=== Node Labeling for Topology Awareness ==="

# Label 2 of 3 nodes as storage-heavy for PostgreSQL + MinIO placement
NODES=$(kubectl get nodes -o name | cut -d/ -f2)
echo "Found nodes: $NODES"

# Label first two nodes as storage-heavy
echo "$NODES" | head -n 2 | while read node; do
  echo "Labeling $node as storage-heavy..."
  kubectl label node "$node" node-role=storage-heavy --overwrite
done

echo "✅ Nodes labeled: $(kubectl get nodes -l node-role=storage-heavy -o name | wc -l) storage-heavy"
echo ""
echo "Node topology:"
kubectl get nodes -o custom-columns=NAME:.metadata.name,ROLES:.metadata.labels.node-role
