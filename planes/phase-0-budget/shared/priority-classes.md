# Priority Classes Hierarchy

## Overview
This document defines the priority class hierarchy for the Kubernetes cluster. Priority classes are used by the scheduler to determine the order of pod scheduling and preemption during resource contention.

## Priority Classes

### foundation-critical (value: 1000000)
**Purpose:** Highest priority for critical foundation workloads that must never be preempted.
**Usage:** PostgreSQL, NATS, Temporal
**Preemption Policy:** `PreemptLowerPriority` - Can preempt lower priority pods when resources are scarce.

### foundation-high (value: 900000)
**Purpose:** High priority for essential foundation services.
**Usage:** Kyverno, SPIRE, MinIO
**Preemption Policy:** `PreemptLowerPriority` - Can preempt lower priority pods.

### foundation-medium (value: 800000)
**Purpose:** Medium priority for observability and monitoring components.
**Usage:** Prometheus, Grafana, Loki, Tempo, AlertManager
**Preemption Policy:** `PreemptLowerPriority` - Can preempt lower priority pods.

## Implementation Notes

1. **Global Default:** None of these classes are set as global default to avoid unintended priority assignment.
2. **Value Range:** Kubernetes priority values range from -10 to 10,000,000,000. Our values are chosen to leave room for future expansion.
3. **Preemption:** All classes use `PreemptLowerPriority` to ensure critical workloads can claim resources when needed.
4. **Usage:** Apply these classes to pod specifications using `priorityClassName` field.

## Validation
After deployment, verify with:
```bash
kubectl get priorityclass | grep foundation
```

Expected output:
```
foundation-critical   1000000             false                   PreemptLowerPriority
foundation-high       900000              false                   PreemptLowerPriority  
foundation-medium     800000              false                   PreemptLowerPriority
```