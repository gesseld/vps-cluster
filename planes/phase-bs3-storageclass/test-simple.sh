#!/bin/bash
echo "Test script starting"
echo "Testing kubectl..."
kubectl get nodes
echo "Testing jq..."
kubectl get nodes -o json | jq -r '.items[0].metadata.name'
echo "Test script completed"