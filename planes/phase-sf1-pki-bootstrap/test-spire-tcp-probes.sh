#!/bin/bash

# Test SPIRE server with TCP socket probes instead of HTTP

set -e

echo "=============================================="
echo "Testing SPIRE Server with TCP Socket Probes"
echo "=============================================="
echo ""

# Load environment variables
if [ -f "../../.env" ]; then
    source ../../.env
    echo "✓ Loaded environment variables from ../../.env"
else
    echo "⚠ Warning: ../../.env file not found"
    echo "   Using default values"
fi

echo ""
echo "1. Restoring original SPIRE configuration..."
kubectl patch statefulset -n spire spire-server --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/volumes/0/configMap/name", "value": "spire-server-config"}]'

echo ""
echo "2. Updating probes to use TCP socket checks..."
# Create a patch to change HTTP probes to TCP socket probes
cat > /tmp/spire-probe-patch.yaml << 'EOF'
spec:
  template:
    spec:
      containers:
      - name: spire-server
        livenessProbe:
          tcpSocket:
            port: 8081
          initialDelaySeconds: 30
          periodSeconds: 30
          failureThreshold: 3
        readinessProbe:
          tcpSocket:
            port: 8081
          initialDelaySeconds: 30
          periodSeconds: 30
          failureThreshold: 3
EOF

kubectl patch statefulset -n spire spire-server --type merge --patch "$(cat /tmp/spire-probe-patch.yaml)"
echo "✓ Updated probes to TCP socket checks on port 8081"

echo ""
echo "3. Restarting SPIRE server..."
kubectl delete pod -n spire spire-server-0 --ignore-not-found

echo ""
echo "4. Waiting for SPIRE server to start..."
echo "   This will test if TCP socket probes work better than HTTP probes"
sleep 30

for i in {1..12}; do
    echo "   Checking... ($((i*5)) seconds)"
    
    # Check pod status
    POD_STATUS=$(kubectl get pod -n spire spire-server-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    
    if [ "$POD_STATUS" = "true" ]; then
        echo "✓ SPIRE server is READY!"
        break
    fi
    
    # Check if pod is running but not ready
    if kubectl get pod -n spire spire-server-0 2>/dev/null | grep -q "Running"; then
        echo "   Pod is Running but not Ready yet"
    fi
    
    sleep 5
done

echo ""
echo "5. Checking SPIRE server status..."
kubectl get pods -n spire

echo ""
echo "6. Checking SPIRE server logs..."
kubectl logs -n spire spire-server-0 --tail=20

echo ""
echo "7. Checking pod events for probe failures..."
kubectl describe pod -n spire spire-server-0 | grep -i "probe\|unhealthy" | head -10

echo ""
echo "8. Testing if server stays running..."
echo "   Waiting 2 minutes to see if server remains stable..."
sleep 120

echo ""
echo "9. Final status check after 2 minutes..."
kubectl get pods -n spire
RESTART_COUNT=$(kubectl get pod -n spire spire-server-0 -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
echo "   Restart count: $RESTART_COUNT"

if [ "$RESTART_COUNT" = "0" ]; then
    echo "✅ SUCCESS: SPIRE server remained stable for 2+ minutes!"
else
    echo "⚠ Server restarted $RESTART_COUNT time(s) in 2 minutes"
fi

echo ""
echo "=============================================="
echo "TCP Probe Test Complete"
echo "=============================================="
echo ""
echo "📋 Summary:"
echo "   - Changed liveness/readiness probes from HTTP to TCP socket"
echo "   - Probes now check port 8081 (gRPC) instead of 8082 (HTTP)"
echo "   - SPIRE server gRPC port should be more stable than HTTP health endpoints"
echo ""
echo "🔍 If this works:"
echo "   1. SPIRE server should remain stable"
echo "   2. Agents should be able to connect"
echo "   3. We can proceed with validation"
echo ""
echo "🔍 If this fails:"
echo "   1. Check logs for other issues"
echo "   2. Consider testing with SQLite instead of PostgreSQL"
echo "   3. Check resource limits"
echo ""

# Cleanup
rm -f /tmp/spire-probe-patch.yaml

exit 0