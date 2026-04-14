# CP-5: Control Plane NATS (Stateless Signaling)

## Objective
Deploy a lightweight, stateless NATS instance for critical control signals only (not data streaming).

## Key Features
- **Stateless NATS** without JetStream for ultra-low latency control signals
- **TLS encryption** using Cert-Manager certificates
- **High availability** with 2 replicas and PodDisruptionBudget
- **Subject hierarchy**: `control.critical.*`, `control.audit.*`
- **Role-based accounts** with separate permissions
- **Leaf node support** for cross-plane message bridging

## Architecture

```
┌─────────────────────────────────────────────────┐
│            Control Plane NATS (CP-5)            │
├─────────────────────────────────────────────────┤
│  • Stateless (no JetStream)                     │
│  • 2+ replicas for HA                           │
│  • TLS encrypted                                │
│  • Accounts: CONTROL, AUDIT, SYS                │
│  • Subjects: control.critical.*, control.audit.*│
│  • Ports: 4222 (client), 8222 (monitor)         │
│  • Leaf node: 7422 for data plane connection    │
└─────────────────────────────────────────────────┘
```

## Prerequisites

1. Kubernetes cluster with at least 2 nodes
2. `control-plane` namespace
3. Cert-Manager (optional, for TLS)
4. kubectl configured with cluster access
5. NATS CLI (`nats`) for testing

## Directory Structure

```
phase-cp5-nats-control/
├── 01-pre-deployment-check.sh    # Prerequisite validation
├── 02-deployment.sh              # Main deployment script
├── 03-validation.sh              # Post-deployment validation
├── run-all.sh                    # Complete implementation script
├── stateless-nats.yaml           # Consolidated manifest
├── pdb.yaml                      # PodDisruptionBudget
├── test-nats-quick.sh            # Quick test script
├── manifests/                    # Generated manifests
├── logs/                         # Execution logs
└── validation-report.md          # Validation results
```

## Quick Start

```bash
# Make scripts executable
chmod +x *.sh

# Run complete implementation
./run-all.sh

# Or run phases individually
./01-pre-deployment-check.sh
./02-deployment.sh
./03-validation.sh
```

## Manual Deployment

```bash
# Apply manifests directly
kubectl apply -f stateless-nats.yaml
kubectl apply -f pdb.yaml

# Verify deployment
kubectl get deployment,service,pods -n control-plane -l app=nats-stateless
```

## Validation

```bash
# Quick test
./test-nats-quick.sh

# Full validation
./03-validation.sh

# Manual test
nats sub control.critical.alert --server=nats-stateless.control-plane.svc.cluster.local:4222 --user=controller --password=changeme
```

## Configuration Details

### Subjects
- `control.critical.*` - Critical control signals (alerts, commands)
- `control.audit.*` - Audit and logging signals

### Accounts
1. **CONTROL** (`controller`)
   - Full access to `control.*` subjects
   - Used by control plane components

2. **AUDIT** (`auditor`)
   - Access to `control.audit.*` subjects
   - Used for audit logging

3. **SYS** (`sysadmin`)
   - System monitoring account
   - Access to monitoring endpoints

### Ports
- **4222** - Client connections
- **8222** - Monitoring (HTTP)
- **6222** - Cluster connections (future HA)
- **7422** - Leaf nodes (data plane bridging)

### Security
- Runs as non-root user (UID 1000)
- Read-only root filesystem
- All capabilities dropped
- TLS encryption (if Cert-Manager available)
- Random password generation

## Integration with Data Plane

To connect data plane NATS as a leaf node:

```yaml
# In data plane NATS configuration
leafnodes {
  remotes = [
    {
      url: "nats://controller:changeme@nats-stateless.control-plane.svc.cluster.local:7422"
      account: "CONTROL"
    }
  ]
}
```

## Monitoring

Access monitoring dashboard:
```bash
# Port-forward monitoring
kubectl port-forward svc/nats-stateless -n control-plane 8222:8222

# Open browser
open http://localhost:8222
```

## Troubleshooting

### Common Issues

1. **Pods not starting**
   ```bash
   kubectl describe pod -n control-plane -l app=nats-stateless
   kubectl logs -n control-plane -l app=nats-stateless
   ```

2. **Connection refused**
   ```bash
   # Check service endpoints
   kubectl get endpoints nats-stateless -n control-plane
   
   # Test from within cluster
   kubectl run test --image=natsio/nats-box --restart=Never --rm -it -- nats server info --server=nats-stateless.control-plane.svc.cluster.local:4222
   ```

3. **Authentication failures**
   ```bash
   # Check secrets
   kubectl get secret nats-auth-secrets -n control-plane -o yaml
   
   # Update passwords
   kubectl create secret generic nats-auth-secrets -n control-plane \
     --from-literal=controller-password=newpass \
     --from-literal=auditor-password=newpass \
     --from-literal=sysadmin-password=newpass \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

### Logs
- Application logs: `kubectl logs -n control-plane -l app=nats-stateless`
- Deployment logs: `logs/` directory
- Validation report: `validation-report.md`

## Production Considerations

1. **Update passwords** in `nats-auth-secrets`
2. **Configure network policies** for NATS ports
3. **Set up monitoring alerts** for:
   - Pod restarts
   - High latency
   - Connection errors
4. **Implement backup** for configuration
5. **Test failover** scenarios
6. **Document API** for control signals

## Cleanup

```bash
# Remove all CP-5 NATS resources
kubectl delete -f stateless-nats.yaml
kubectl delete -f pdb.yaml

# Remove generated files
rm -rf manifests/ logs/ validation-report.md
```

## References

- [NATS Documentation](https://docs.nats.io/)
- [NATS Server Configuration](https://docs.nats.io/running-a-nats-service/configuration)
- [Kubernetes NATS Operator](https://github.com/nats-io/k8s)
- [Cert-Manager](https://cert-manager.io/)

## License

This implementation is part of the k3s control plane deployment.