# Phase 0: Budget Scaffolding

## Purpose
Encode resource constraints as Kubernetes primitives that the scheduler enforces at admission time. This phase creates the guardrails that make "resource frugality" enforceable, not aspirational.

## Implementation Tasks

### Task BS-1: PriorityClasses Deployment
**Objective:** Create tiered priority classes that protect critical foundation workloads during resource pressure.

**Sub-tasks:**
- Apply `foundation-critical` (value: 1000000) for PostgreSQL, NATS, Temporal
- Apply `foundation-high` (value: 900000) for Kyverno, SPIRE, MinIO
- Apply `foundation-medium` (value: 800000) for observability components
- Set `preemptionPolicy: PreemptLowerPriority` on all classes
- Document priority hierarchy in `shared/priority-classes.md`

## Scripts

### 1. `01-pre-deployment-check.sh`
**Purpose:** Ensure all prerequisites are met before deployment.
**Checks:**
- Kubernetes cluster connectivity
- PriorityClass API availability
- Existing PriorityClasses (conflict detection)
- Manifest file validation
- kubectl permissions
- Node resources and scheduler status

### 2. `02-deployment.sh`
**Purpose:** Deploy PriorityClasses and verify functionality.
**Actions:**
- Run pre-deployment check
- Apply `priority-classes.yaml` manifest
- Verify each PriorityClass creation
- Test PriorityClass assignment with a test pod
- Create deployment summary

### 3. `03-validation.sh`
**Purpose:** Validate deployment and ensure all deliverables are completed.
**Validations:**
- PriorityClasses existence and values
- PreemptionPolicy settings
- Global default configuration
- Priority hierarchy order
- Duplicate detection
- Functional testing with pods

## Files

### `priority-classes.yaml`
Contains the three PriorityClass definitions:
- `foundation-critical` (1000000): PostgreSQL, NATS, Temporal
- `foundation-high` (900000): Kyverno, SPIRE, MinIO
- `foundation-medium` (800000): Observability components

### `shared/priority-classes.md`
Documentation of the priority hierarchy and usage guidelines.

## Execution Order

1. **Pre-deployment check:** `./01-pre-deployment-check.sh`
2. **Deployment:** `./02-deployment.sh`
3. **Validation:** `./03-validation.sh`

## Expected Output

After successful deployment:
```bash
kubectl get priorityclass | grep foundation
```

Should show:
```
foundation-critical   1000000             false                   PreemptLowerPriority
foundation-high       900000              false                   PreemptLowerPriority  
foundation-medium     800000              false                   PreemptLowerPriority
```

## Notes

- These PriorityClasses establish the foundation for resource budget enforcement
- Higher priority pods can preempt lower priority pods during resource contention
- Critical foundation workloads are protected from eviction
- All classes use `PreemptLowerPriority` to ensure resource availability
- None are set as global default to avoid unintended priority assignment