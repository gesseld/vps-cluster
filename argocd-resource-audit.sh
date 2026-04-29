#!/bin/bash
# ArgoCD Resource Audit
NAMESPACE=dip-control-infra

echo "ArgoCD Resource Audit - \04/29/2026 13:53:42"
echo "--------------------------------"
kubectl top pods -n \

echo ""
echo "Limits vs Usage:"
# This is a simplified check
kubectl get pods -n \ -o custom-columns=NAME:.metadata.name,CPU_LIMIT:.spec.containers[0].resources.limits.cpu,MEM_LIMIT:.spec.containers[0].resources.limits.memory
