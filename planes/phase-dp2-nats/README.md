# NATS JetStream Phase DP-2: Event Bus with Persistence & Backpressure

## Objective
Deploy a NATS JetStream event bus with persistence, TLS encryption, and backpressure monitoring for document processing, task execution, and observability data.

## Architecture
- **NATS Server 2.10+**: Single replica with JetStream persistence (simplified, no HA requirements)
- **JetStream Streams**: Three dedicated streams with appropriate retention policies
- **TLS Encryption**: Self-signed certificates for client connections (port 4222)
- **Backpressure Monitoring**: Prometheus metrics exporter with alerting thresholds
- **Network Policies**: Controlled access from execution, control, and observability namespaces
- **Resource Limits**: 170MB request / 256MB limit per replica

## Stream Configuration

### 1. DOCUMENTS Stream
- **Subjects**: `data.doc.>`
- **Retention**: WorkQueue
- **Max Messages**: 100,000
- **Max Bytes**: 5GB
- **Replicas**: 1
- **Purpose**: Document processing with work queue semantics

### 2. EXECUTION Stream
- **Subjects**: `exec.task.>`
- **Retention**: Interest (24h)
- **Max Age**: 24 hours
- **Replicas**: 1
- **Purpose**: Task execution with time-based retention

### 3. OBSERVABILITY Stream
- **Subjects**: `obs.metric.>`
- **Retention**: Limits
- **Max Bytes**: 1GB
- **Replicas**: 1
- **Purpose**: Observability metrics with size limits

## Prerequisites
1. Kubernetes cluster with at least 1 node
2. Helm installed and configured
3. `kubectl` configured with cluster access
4. (Optional) Prometheus for metrics collection
5. (Optional) NATS CLI for validation (`nats` command)

## Deployment Steps

### 1. Pre-deployment Check
```bash
./01-pre-deployment-check.sh
```
Checks cluster access, Helm configuration, storage classes, and existing resources.

### 2. Deployment
```bash
./02-deployment.sh
```
Deploys all components:
- Creates TLS certificates (self-signed)
- Deploys NATS with Helm (single replica)
- Applies stream configurations
- Sets up network policies
- Creates PodDisruptionBudget
- Configures metrics exporter
- Creates and labels required namespaces

### 3. Validation
```bash
./03-validation.sh
```
Validates the deployment:
- Pod and service status
- NATS server connectivity
- JetStream stream creation
- TLS configuration
- Metrics exporter functionality
- Backpressure monitoring setup

## Configuration

### Environment Variables
Create `.env` file in project root or set variables:
```bash
export NAMESPACE=default
export NATS_VERSION=2.10
export HELM_REPO=nats
export HELM_CHART=nats
export HELM_CHART_VERSION=1.0.0
export STORAGE_CLASS=hcloud-volumes  # Optional
```

### TLS Certificates
- Self-signed certificates generated during deployment
- Stored in Kubernetes secret `nats-tls`
- Contains: `tls.crt`, `tls.key`, `ca.crt`
- In production, replace with certificates from your CA

## Components

### 1. NATS Server (`data-plane/nats/values.yaml`)
- NATS 2.10 with JetStream enabled
- Single replica (simplified deployment)
- TLS on port 4222
- Resource limits: 170MB request / 256MB limit
- 10GB persistent storage for JetStream
- Monitoring on port 8222

### 2. Stream Configuration (`data-plane/nats/stream-config.yaml`)
- ConfigMap with stream creation scripts
- Defines DOCUMENTS, EXECUTION, OBSERVABILITY streams
- Includes backpressure monitoring script
- JSON definitions for reference

### 3. Network Policies (`data-plane/nats/networkpolicy.yaml`)
- Allows access from execution, control, observability namespaces
- Requires namespace labels: `kubernetes.io/metadata.name=<namespace>`
- Default deny all other traffic
- Separate policies for server, exporter, and management

### 4. Pod Disruption Budget (`data-plane/nats/pdb.yaml`)
- `minAvailable: 1` for NATS server (single replica)
- `maxUnavailable: 1` for metrics exporter
- Prevents voluntary disruptions from evicting critical pods

### 5. Metrics Exporter (`data-plane/nats/metrics-exporter.yaml`)
- VictoriaMetrics-compatible metrics exporter on port 7777
- VMAlert rules for backpressure monitoring (>80% threshold)
- Grafana dashboard configuration for VictoriaMetrics
- VMAgent scrape configuration

## Validation Tests

### Basic Connectivity Test
```bash
# Test NATS server connectivity
kubectl exec -it deployment/nats -n default -- nats server info
```

### Stream Verification
```bash
# List all streams
kubectl exec -it deployment/nats -n default -- nats stream list

# Check specific stream
kubectl exec -it deployment/nats -n default -- nats stream info DOCUMENTS
```

### Backpressure Monitoring with VictoriaMetrics
```bash
# Check metrics endpoint
curl http://nats-exporter.default.svc.cluster.local:7777/metrics | grep nats_jetstream_stream

# Query in VictoriaMetrics
curl -g 'http://victoriametrics:8428/api/v1/query?query=nats_jetstream_stream_total_bytes{stream="DOCUMENTS"}/nats_jetstream_stream_config_max_bytes{stream="DOCUMENTS"}*100'
```

### TLS Test
```bash
# Test TLS connection
kubectl run -it --rm test-tls --image=natsio/nats-box --restart=Never -- \
  nats --server nats://nats.default.svc.cluster.local:4222 \
  --tlscert=/etc/nats/tls/tls.crt \
  --tlskey=/etc/nats/tls/tls.key \
  server info
```

## Monitoring & Alerts

### Key Metrics
- `nats_jetstream_stream_total_bytes`: Current stream size
- `nats_jetstream_stream_config_max_bytes`: Stream size limit
- `nats_jetstream_stream_consumer_pending_msgs`: Pending messages
- Backpressure % = (total_bytes / max_bytes) * 100

### Alert Thresholds
- **Warning**: Backpressure > 80%
- **Critical**: Backpressure > 90%
- **Critical**: Consumer pending messages > 10,000

### Grafana Dashboard
Import the dashboard JSON from `metrics-exporter.yaml` to monitor:
- Stream backpressure percentages
- Consumer pending messages
- Server health and connections

## Troubleshooting

### Pods Not Starting
1. Check PVC binding: `kubectl get pvc -n default`
2. Check resource availability: `kubectl describe nodes`
3. Check TLS secret: `kubectl get secret nats-tls -n default`

### Stream Creation Issues
1. Check NATS logs: `kubectl logs deployment/nats -n default`
2. Manually create streams:
   ```bash
   kubectl exec -it deployment/nats -n default -- /tmp/create-streams.sh
   ```

### Connection Issues
1. Check network policies: `kubectl get networkpolicy -n default`
2. Verify namespace labels: `kubectl get namespaces --show-labels`
3. Test internal connectivity:
   ```bash
   kubectl run -it --rm test-connect --image=natsio/nats-box --restart=Never -- \
     nats --server nats://nats:4222 pub test.hello "Hello"
   ```

### Metrics Not Appearing in VictoriaMetrics
1. Check exporter logs: `kubectl logs -l component=exporter -n default`
2. Verify service: `kubectl get svc nats-exporter -n default`
3. Test endpoint: `curl http://nats-exporter.default.svc.cluster.local:7777/metrics`
4. Check VMAgent config: `kubectl get configmap nats-vmagent-scrape-config -o yaml`
5. Verify VMAgent targets: `curl http://vmagent:8429/targets | grep nats`

## Cleanup
```bash
# Delete all resources
helm uninstall nats -n default
kubectl delete -f data-plane/nats/ --recursive
kubectl delete secret nats-tls -n default
kubectl delete configmap nats-stream-config nats-metrics-exporter-config -n default
kubectl label namespaces execution control observability kubernetes.io/metadata.name-
```

## Scaling Considerations

### Future HA Deployment
If HA resources become available, modify `values.yaml`:
```yaml
replicaCount: 3
cluster:
  enabled: true
jetstream:
  replicas: 3
```

### Storage Scaling
Increase storage size in `values.yaml`:
```yaml
jetstream:
  fileStorage:
    storageSize: 50Gi
```

## Deliverables Checklist
- [x] `data-plane/nats/values.yaml` (Helm values with single replica)
- [x] `data-plane/nats/stream-config.yaml` (with backpressure limits)
- [x] `data-plane/nats/networkpolicy.yaml` (allow from execution, control, observability)
- [x] `data-plane/nats/pdb.yaml` (minAvailable: 1)
- [x] `data-plane/nats/metrics-exporter.yaml` (VictoriaMetrics compatible)
- [x] `data-plane/nats/vmagent-config.yaml` (VMAgent configuration)
- [x] Pre-deployment script (`01-pre-deployment-check.sh`)
- [x] Deployment script (`02-deployment.sh`)
- [x] Validation script (`03-validation.sh`)

## Security Notes
1. **TLS Certificates**: Self-signed certificates are used for simplicity. In production, use certificates from a trusted CA or cert-manager.
2. **Authentication**: Authentication is disabled in this deployment. Enable it in production using NATS accounts and users.
3. **Network Policies**: Strict network policies limit access to required namespaces only.
4. **Resource Limits**: CPU and memory limits prevent resource exhaustion.
5. **Storage Encryption**: Consider enabling encryption at rest for JetStream storage if sensitive data is being processed.