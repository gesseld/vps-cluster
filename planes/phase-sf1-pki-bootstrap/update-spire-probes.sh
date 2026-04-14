#!/bin/bash

# Update SPIRE server probes to TCP socket checks

set -e

echo "=============================================="
echo "Updating SPIRE Server Probes to TCP Socket"
echo "=============================================="
echo ""

echo "1. Getting current StatefulSet configuration..."
kubectl get statefulset -n spire spire-server -o yaml > /tmp/spire-current.yaml

echo ""
echo "2. Creating updated configuration with TCP probes..."
# Create a new YAML with updated probes
cat > /tmp/spire-updated.yaml << 'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"apps/v1","kind":"StatefulSet","metadata":{"annotations":{},"labels":{"app":"spire-server"},"name":"spire-server","namespace":"spire"},"spec":{"replicas":1,"selector":{"matchLabels":{"app":"spire-server"}},"serviceName":"spire-server","template":{"metadata":{"labels":{"app":"spire-server"}},"spec":{"containers":[{"args":["-config","/run/spire/config/server.conf"],"image":"ghcr.io/spiffe/spire-server:1.8.0","livenessProbe":{"tcpSocket":{"port":8081},"initialDelaySeconds":30,"periodSeconds":30},"name":"spire-server","ports":[{"containerPort":8081,"name":"grpc"},{"containerPort":8082,"name":"http"}],"readinessProbe":{"tcpSocket":{"port":8081},"initialDelaySeconds":30,"periodSeconds":30},"resources":{"limits":{"cpu":"500m","memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}},"volumeMounts":[{"mountPath":"/run/spire/config","name":"spire-config","readOnly":true},{"mountPath":"/run/spire/data","name":"spire-data"},{"mountPath":"/tmp/spire-server/private","name":"spire-sockets"}]}],"serviceAccountName":"spire-server","volumes":[{"configMap":{"name":"spire-server-config"},"name":"spire-config"},{"emptyDir":{},"name":"spire-sockets"}]}},"volumeClaimTemplates":[{"metadata":{"name":"spire-data"},"spec":{"accessModes":["ReadWriteOnce"],"resources":{"requests":{"storage":"1Gi"}}}}]}}
  creationTimestamp: "2026-04-11T13:04:11Z"
  generation: 3
  labels:
    app: spire-server
  name: spire-server
  namespace: spire
  resourceVersion: "1071006"
  uid: 0f96a07f-8de8-43e6-9adb-d1b8ea054861
spec:
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain
    whenScaled: Retain
  podManagementPolicy: OrderedReady
  replicas: 1
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: spire-server
  serviceName: spire-server
  template:
    metadata:
      labels:
        app: spire-server
    spec:
      containers:
      - args:
        - -config
        - /run/spire/config/server.conf
        image: ghcr.io/spiffe/spire-server:1.8.0
        livenessProbe:
          failureThreshold: 3
          initialDelaySeconds: 30
          periodSeconds: 30
          successThreshold: 1
          tcpSocket:
            port: 8081
          timeoutSeconds: 1
        name: spire-server
        ports:
        - containerPort: 8081
          name: grpc
          protocol: TCP
        - containerPort: 8082
          name: http
          protocol: TCP
        readinessProbe:
          failureThreshold: 3
          initialDelaySeconds: 30
          periodSeconds: 30
          successThreshold: 1
          tcpSocket:
            port: 8081
          timeoutSeconds: 1
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 256Mi
        volumeMounts:
        - mountPath: /run/spire/config
          name: spire-config
          readOnly: true
        - mountPath: /run/spire/data
          name: spire-data
        - mountPath: /tmp/spire-server/private
          name: spire-sockets
      serviceAccountName: spire-server
      volumes:
      - configMap:
          name: spire-server-config
        name: spire-config
      - emptyDir: {}
        name: spire-sockets
  updateStrategy:
    type: RollingUpdate
  volumeClaimTemplates:
  - metadata:
      name: spire-data
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 1Gi
      volumeMode: Filesystem
EOF

echo ""
echo "3. Applying updated configuration..."
kubectl apply -f /tmp/spire-updated.yaml
echo "✓ Updated StatefulSet with TCP socket probes"

echo ""
echo "4. Restarting SPIRE server..."
kubectl delete pod -n spire spire-server-0 --ignore-not-found

echo ""
echo "5. Waiting for SPIRE server to start with new probes..."
sleep 30

echo ""
echo "6. Checking SPIRE server status..."
kubectl get pods -n spire

echo ""
echo "7. Monitoring for 2 minutes to check stability..."
echo "   Starting at: $(date)"
START_TIME=$(date +%s)

for i in {1..24}; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    # Check pod status
    POD_READY=$(kubectl get pod -n spire spire-server-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    RESTART_COUNT=$(kubectl get pod -n spire spire-server-0 -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
    
    echo "   $(date): Ready=$POD_READY, Restarts=$RESTART_COUNT, Elapsed=${ELAPSED}s"
    
    if [ "$POD_READY" = "true" ]; then
        echo "✅ SPIRE server is READY and stable!"
        
        # Check logs
        echo ""
        echo "8. Checking SPIRE server logs..."
        kubectl logs -n spire spire-server-0 --tail=10
        
        break
    fi
    
    if [ "$RESTART_COUNT" -gt 0 ]; then
        echo "⚠ SPIRE server has restarted $RESTART_COUNT time(s)"
        echo "   Checking logs..."
        kubectl logs -n spire spire-server-0 --previous 2>/dev/null | tail -10 || echo "   Could not get previous logs"
        break
    fi
    
    sleep 5
done

echo ""
echo "9. Final status after monitoring..."
kubectl get pods -n spire

echo ""
echo "=============================================="
echo "TCP Probe Update Complete"
echo "=============================================="
echo ""
echo "📊 Results:"
echo "   - Probes changed from HTTP to TCP socket on port 8081"
echo "   - SPIRE server gRPC port should be stable"
echo "   - Monitoring complete"
echo ""
echo "➡️  Next steps based on results:"
echo "   If server is stable:"
echo "     1. Check if agents can connect"
echo "     2. Run validation script"
echo "   If server still unstable:"
echo "     1. Check resource limits"
echo "     2. Test with SQLite instead of PostgreSQL"
echo "     3. Check for configuration errors"
echo ""

# Cleanup
rm -f /tmp/spire-current.yaml /tmp/spire-updated.yaml

exit 0