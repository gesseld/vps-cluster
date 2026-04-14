# Phase SF-1: Cert-Manager + SPIRE PKI Bootstrap

## Objective
Establish certificate authority for mTLS before any workload requests certificates.

## Architecture Overview

This phase implements a secure PKI (Public Key Infrastructure) bootstrap using:
1. **Cert-Manager v1.13+** - For initial self-signed root CA and certificate management
2. **SPIRE (SPIFFE Runtime Environment)** - For dynamic, short-lived certificate issuance
3. **PostgreSQL** - Backend datastore for SPIRE (Data Plane dependency)
4. **SDS (Secret Discovery Service)** - For Envoy/NGINX mTLS integration

## Components Deployed

### 1. Cert-Manager
- Self-signed ClusterIssuer for root CA
- CA certificate with 1-year validity, 30-day renewal
- Automatic certificate approval workflow

### 2. SPIRE Server
- StatefulSet with PVC for persistence
- PostgreSQL backend for data storage
- `k8s_psat` node attestor (Proof of Possession)
- Configurable SVID TTL: 1 hour (short-lived for security)

### 3. SPIRE Agent
- DaemonSet running on all nodes
- `k8s` workload attestor (Unix + Kubernetes)
- Creates `/tmp/spire-sockets/agent.sock` for workload access
- Integrated with node attestor for secure bootstrap

### 4. Security Features
- **Node Attestation**: `k8s_psat` verifies node identity
- **Workload Attestation**: Kubernetes metadata + Unix process inspection
- **Short-lived Certificates**: 1-hour SVID TTL for reduced attack surface
- **Fallback Mode**: ConfigMap toggle to use cert-manager TLS if SPIRE unavailable

### 5. Monitoring & Observability
- SPIRE server metrics endpoint (port 9090)
- Prometheus ServiceMonitor for metrics collection
- Alerts for:
  - SVID issuance latency >5 seconds
  - SPIRE server downtime
  - Missing SPIRE agents

## Scripts

### 1. `01-pre-deployment-check.sh`
Validates all prerequisites before deployment:
- Kubernetes cluster connectivity
- Required tools (kubectl, helm, jq, curl)
- Helm repositories
- PostgreSQL availability (Data Plane dependency)
- Node resources and labels
- RBAC permissions
- Storage classes

### 2. `02-deployment.sh`
Deploys all components:
1. Creates namespaces (cert-manager, spire, foundation)
2. Deploys Cert-Manager v1.13+ with CRDs
3. Creates self-signed ClusterIssuer
4. Deploys SPIRE Server with PostgreSQL backend
5. Deploys SPIRE Agent DaemonSet
6. Configures RBAC for TokenReview
7. Creates registration entries for foundation namespaces
8. Sets up fallback configuration
9. Deploys metrics exporter and alerts
10. Configures SDS for Envoy/NGINX mTLS

### 3. `03-validation.sh`
Validates the deployment:
- Checks all deliverable files exist
- Verifies Cert-Manager components are working
- Validates SPIRE server and agent deployment
- Tests RBAC and registration entries
- Verifies fallback configuration
- Checks metrics and monitoring setup
- Validates SDS configuration
- Runs integration tests

## Deliverables

| File | Purpose |
|------|---------|
| `shared/pki/cert-manager.yaml` | Cert-Manager ClusterIssuer and CA certificate |
| `control-plane/spire/server.yaml` | SPIRE Server StatefulSet with PVC |
| `control-plane/spire/agent-daemonset.yaml` | SPIRE Agent DaemonSet |
| `control-plane/spire/roles.yaml` | RBAC for TokenReview |
| `control-plane/spire/entries.yaml` | Registration entries for foundation namespaces |
| `control-plane/spire/fallback-config.yaml` | cert-manager fallback toggle |
| `control-plane/spire/metrics-exporter.yaml` | Metrics exporter and alerts |
| `shared/pki/sds-config.yaml` | SDS configuration for Envoy/NGINX |
| ConfigMap `spire-server-config` | PostgreSQL connection string |

## Validation Requirements

```bash
# 1. Certificate requests are being approved
kubectl get certificaterequest -A | grep -q Approved

# 2. New pods receive agent socket within 5 seconds
# Pods should have /tmp/spire-sockets/agent.sock available

# 3. SPIRE metrics are accessible
curl http://spire-server:9090/metrics | grep spire_server_svid_issuance_latency_seconds
```

## Dependencies

1. **PostgreSQL**: Required for SPIRE backend (Data Plane dependency)
   - Should be available in `postgresql` namespace
   - Connection string configured in `spire-server-config` ConfigMap

2. **Monitoring Stack**: Optional but recommended
   - Prometheus Operator for ServiceMonitor
   - vmagent for metrics collection
   - AlertManager for alerts

3. **Storage Class**: Required for SPIRE server PVC
   - Default storage class should be available
   - 1Gi storage requested

## Configuration

### SPIRE Server Configuration
- Trust Domain: `example.org` (configurable)
- Bind Address: `0.0.0.0:8081` (gRPC), `0.0.0.0:8082` (HTTP)
- PostgreSQL backend with connection string
- `k8s_psat` node attestor for cluster authentication

### SPIRE Agent Configuration
- Connects to SPIRE server via service DNS
- `k8s` and `unix` workload attestors
- Socket path: `/tmp/spire-sockets/agent.sock`
- Trust bundle auto-update

### Fallback Configuration
- ConfigMap `spire-fallback-config` controls fallback mode
- When enabled, workloads use cert-manager TLS certificates
- Toggle via annotation: `spire-fallback/enabled: "true"`

## Usage

### Deployment Sequence
```bash
# 1. Run pre-deployment checks
./01-pre-deployment-check.sh

# 2. Deploy all components
./02-deployment.sh

# 3. Validate deployment
./03-validation.sh
```

### Testing SVID Issuance
```bash
# Create a test workload
kubectl apply -f test-workload.yaml

# Check for SVID
kubectl exec test-workload -- ls -la /tmp/spire-sockets/
```

### Enabling Fallback Mode
```bash
# Enable fallback
kubectl patch cm -n spire spire-fallback-config --type merge -p '{"data":{"enabled":"true"}}'

# Annotate workload to use fallback
kubectl annotate pod my-workload spire-fallback/enabled="true"
```

## Troubleshooting

### Common Issues

1. **PostgreSQL Connection Failed**
   - Check PostgreSQL is running: `kubectl get pods -n postgresql`
   - Verify connection string in `spire-server-config`
   - Check network policies allow communication

2. **SPIRE Agent Not Creating Socket**
   - Verify DaemonSet is running on all nodes
   - Check hostPath volumes are mounted correctly
   - Verify node has `/tmp/spire-sockets` directory

3. **Certificate Requests Not Approved**
   - Check cert-manager pods are running
   - Verify ClusterIssuer is ready
   - Check cert-manager logs for errors

4. **Metrics Not Accessible**
   - Verify SPIRE server is exposing port 9090
   - Check ServiceMonitor is configured
   - Verify network policies allow metrics scraping

### Logs
```bash
# SPIRE Server logs
kubectl logs -n spire -l app=spire-server

# SPIRE Agent logs
kubectl logs -n spire -l app=spire-agent

# Cert-Manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager
```

## Security Considerations

1. **Short-lived Certificates**: 1-hour TTL reduces exposure time
2. **Node Attestation**: `k8s_psat` ensures only authorized nodes join
3. **Workload Isolation**: Each workload gets unique identity
4. **Zero Trust**: No implicit trust between workloads
5. **Audit Logging**: All SVID issuances are logged
6. **Metrics Monitoring**: Latency and error monitoring

## Performance

- SVID issuance latency target: <5 seconds
- Agent startup time: <30 seconds
- Memory usage: Server 256-512MB, Agent 128-256MB
- Storage: 1Gi PVC for SPIRE server

## Next Steps

After successful deployment:
1. Integrate with Envoy/NGINX using SDS
2. Deploy workload-specific registration entries
3. Configure mTLS between services
4. Set up certificate rotation automation
5. Implement certificate revocation if needed