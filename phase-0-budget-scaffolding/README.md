# Phase 0: Budget Scaffolding

## Purpose
Encode resource constraints as Kubernetes primitives that the scheduler enforces at admission time. This phase creates the guardrails that make "resource frugality" enforceable, not aspirational.

## Non-Negotiable Order
**This phase MUST be deployed BEFORE any plane workloads.** Without these guardrails, pods can schedule without limits, leading to resource contention, eviction storms, or silent OOM kills.

## Components

### 1. PriorityClasses
Tiered priority classes that protect critical foundation workloads during resource pressure:
- `foundation-critical` (1000000): PostgreSQL, NATS, Temporal
- `foundation-high` (900000): Kyverno, SPIRE, MinIO  
- `foundation-medium` (800000): Observability components

### 2. ResourceQuotas + LimitRanges
Enforce namespace-level resource budgets and container-level defaults:
- **Control Plane**: 2.8Gi request memory, 4.2Gi limit
- **Data Plane**: 4.2Gi request memory, 7.1Gi limit  
- **Observability Plane**: 1.5Gi request memory, 2.9Gi limit

### 3. StorageClass with WaitForFirstConsumer
Ensure stateful workloads schedule to nodes with available NVMe before PVC binding.

### 4. Node Labeling for Topology Awareness
Label 2 of 3 nodes as `node-role=storage-heavy` for PostgreSQL + MinIO placement.

### 5. NetworkPolicy CRD Check
Verify NetworkPolicy CRD is available before workloads deploy.

## Deployment

```bash
# Deploy Phase 0
./deploy-phase-0.sh

# Validate deployment
./validate-phase-0.sh
```

## Success Criteria (GATE 0)

| Criterion | Metric | Blocker If Failed |
|-----------|--------|------------------|
| **PriorityClasses** | All 3 classes present | ❌ Cannot proceed: pod specs reference missing classes |
| **ResourceQuotas** | Quotas applied to all 3 namespaces | ❌ Cannot proceed: risk of unbounded resource consumption |
| **StorageClass** | `WaitForFirstConsumer` mode active | ❌ Cannot proceed: stateful pods may schedule to wrong node |
| **Node Labels** | ≥2 nodes labeled `storage-heavy` | ❌ Cannot proceed: topology constraints will fail |

## Next Phase
After Phase 0 passes validation, proceed to **Phase 1: Shared Foundations** (PKI, RBAC, Network Policies).
