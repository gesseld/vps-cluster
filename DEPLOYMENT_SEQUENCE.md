# Deployment Sequence (Non-Negotiable)

This document outlines the strict deployment sequence required by the architectural specification v4.0.4.

## Phase 0: Budget Scaffolding (MANDATORY FIRST)

**MUST be deployed before ANY plane workloads**

```bash
cd phase-0-budget-scaffolding
./deploy-phase-0.sh
./validate-phase-0.sh
```

Components:
- PriorityClasses (foundation, control, data, observability)
- ResourceQuotas (per-plane resource limits)
- StorageClass (nvme-waitfirst)
- Node Labels (plane affinity)
- Network Policy templates

## Phase 1: Shared Foundations

Deploy shared infrastructure:
```bash
# Deploy shared PKI
kubectl apply -f shared/pki/

# Deploy shared RBAC
kubectl apply -f shared/rbac/

# Deploy shared storage classes
kubectl apply -f shared/storage-classes/
```

## Phase 2: Data Plane

**Temporal is in Data Plane (corrected from architectural spec)**

Deployment order within Data Plane:
1. PostgreSQL (database)
2. NATS (messaging)
3. Redis (caching)
4. S3-Compatible Storage
5. Temporal (workflow engine)

```bash
cd data-plane
# Follow README.md in each subdirectory
```

## Phase 3: Control Plane

Deployment order within Control Plane:
1. Kyverno (policy engine)
2. SPIRE (identity management)
3. ArgoCD (GitOps)
4. Control NATS

```bash
cd control-plane
# Follow README.md in each subdirectory
```

## Phase 4: Observability Plane

Deployment order within Observability Plane:
1. VictoriaMetrics (metrics)
2. Fluent Bit (logging)
3. Loki (log aggregation)
4. AlertManager (alerts)
5. Grafana (visualization)

```bash
cd observability-plane
# Follow README.md in each subdirectory
```

## Validation

After each phase, run validation scripts:
```bash
# Validate Phase 0
cd phase-0-budget-scaffolding
./validate-phase-0.sh

# Validate Data Plane
cd data-plane
./validate-data-plane.sh

# Validate Control Plane
cd control-plane
./validate-control-plane.sh

# Validate Observability Plane
cd observability-plane
./validate-observability-plane.sh
```

## Important Notes

1. **Sequence is non-negotiable**: Each phase depends on the previous
2. **Temporal in Data Plane**: Corrected from architectural specification
3. **Resource quotas**: Enforced by Phase 0
4. **Network policies**: Default deny, allow specific communication
5. **Node affinity**: Workloads scheduled to appropriate nodes

## Troubleshooting

If deployment fails:
1. Verify Phase 0 is deployed and validated
2. Check resource quotas are not exceeded
3. Verify network policies allow required communication
4. Check node labels and affinity rules
