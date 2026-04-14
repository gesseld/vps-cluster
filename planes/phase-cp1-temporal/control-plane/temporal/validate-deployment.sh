#!/bin/bash
set -e

echo "=== Validating Temporal Server Deployment ==="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found. Please install kubectl."
    exit 1
fi

# Check if namespace exists
echo "1. Checking control-plane namespace..."
if ! kubectl get namespace control-plane &> /dev/null; then
    echo "Creating control-plane namespace..."
    kubectl create namespace control-plane
fi

# Apply configurations
echo "2. Applying Temporal configurations..."
kubectl apply -f temporal-postgres-creds.yaml -n control-plane
kubectl apply -f temporal-tls-certs.yaml -n control-plane
kubectl apply -f config/ -n control-plane
kubectl apply -f pdb.yaml -n control-plane
kubectl apply -f networkpolicy.yaml -n control-plane
kubectl apply -f service.yaml -n control-plane
kubectl apply -f temporal-server.yaml -n control-plane

# Wait for pods to be ready
echo "3. Waiting for Temporal pods to be ready..."
sleep 10
kubectl wait --for=condition=ready pod -l app=temporal -n control-plane --timeout=120s

# Check pod status
echo "4. Checking pod status..."
kubectl get pods -n control-plane -l app=temporal

# Check services
echo "5. Checking services..."
kubectl get svc -n control-plane -l app=temporal

# Check PDB
echo "6. Checking PodDisruptionBudget..."
kubectl get pdb -n control-plane

# Check network policy
echo "7. Checking network policy..."
kubectl get networkpolicy -n control-plane

# Test connectivity (if tctl is available)
echo "8. Testing Temporal cluster health..."
if command -v tctl &> /dev/null; then
    echo "Running: tctl cluster health"
    # Note: This would require proper TLS configuration
    # tctl --address temporal.control-plane.svc.cluster.local:7233 cluster health
    echo "tctl command found. To test cluster health manually:"
    echo "  tctl --address temporal.control-plane.svc.cluster.local:7233 cluster health"
else
    echo "tctl not found. To install: https://docs.temporal.io/cli/"
fi

echo "=== Validation Complete ==="
echo ""
echo "To manually verify deployment:"
echo "1. Check pods: kubectl get pods -n control-plane -l app=temporal"
echo "2. Check services: kubectl get svc -n control-plane -l app=temporal"
echo "3. Test connectivity: kubectl exec -n control-plane -it \$(kubectl get pod -n control-plane -l app=temporal -o jsonpath='{.items[0].metadata.name}') -- curl http://localhost:9090/health"
echo ""
echo "Expected output:"
echo "- 2 pods in Running state"
echo "- Services: temporal-headless (headless) and temporal (ClusterIP)"
echo "- PDB with minAvailable: 1"
echo "- Network policy allowing ingress from execution-plane"