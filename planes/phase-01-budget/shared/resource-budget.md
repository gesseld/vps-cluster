# Resource Budget and Quota Rationale

## Overview
This document outlines the resource budgeting strategy for the three foundation namespaces as part of BS-2 task implementation. The budget ensures predictable resource allocation and prevents resource exhaustion in the cluster.

## Budget Table

| Namespace | Request Memory | Limit Memory | Request CPU | Limit CPU | Max Pods | Rationale |
|-----------|----------------|--------------|-------------|-----------|----------|-----------|
| **control-plane** | 2.8Gi | 4.2Gi | 1.8 cores | 3.2 cores | 15 | Core Kubernetes components (API server, scheduler, controller manager, etcd) require stable resources but moderate scaling |
| **data-plane** | 3.2Gi | 4.8Gi | 2.4 cores | 4.0 cores | 20 | Application workloads with data processing needs; higher memory for caching and data operations |
| **observability-plane** | 1.6Gi | 2.4Gi | 1.2 cores | 2.0 cores | 10 | Monitoring agents, log collectors, and metrics exporters; lightweight but consistent resource needs |

## LimitRange Defaults

### Control Plane
- **Default Request**: 256Mi memory, 100m CPU
- **Default Limit**: 512Mi memory, 250m CPU  
- **Max per Container**: 1Gi memory, 1 CPU
- **Min per Container**: 64Mi memory, 10m CPU

### Data Plane
- **Default Request**: 512Mi memory, 200m CPU
- **Default Limit**: 1Gi memory, 500m CPU
- **Max per Container**: 2Gi memory, 2 CPU
- **Min per Container**: 128Mi memory, 50m CPU

### Observability Plane
- **Default Request**: 128Mi memory, 50m CPU
- **Default Limit**: 256Mi memory, 100m CPU
- **Max per Container**: 512Mi memory, 1 CPU
- **Min per Container**: 32Mi memory, 10m CPU

## Design Principles

1. **Predictability**: Each namespace has guaranteed minimum resources (requests)
2. **Burst Capacity**: Limits provide headroom for temporary spikes
3. **Isolation**: Namespaces cannot starve each other of resources
4. **Safety Nets**: Defaults prevent "no limits" containers
5. **Reasonable Scaling**: Max limits prevent runaway resource consumption

## Implementation Notes

- ResourceQuotas enforce hard limits at namespace level
- LimitRanges inject defaults for containers without explicit resource specs
- The combination ensures both namespace-level budgeting and container-level safety
- Namespaces are labeled for easy identification and RBAC targeting

## Validation Commands

```bash
# Check ResourceQuotas
kubectl describe resourcequota -n control-plane
kubectl describe resourcequota -n data-plane
kubectl describe resourcequota -n observability-plane

# Check LimitRanges
kubectl describe limitrange -n control-plane
kubectl describe limitrange -n data-plane
kubectl describe limitrange -n observability-plane

# Check namespace usage
kubectl describe namespace control-plane
kubectl describe namespace data-plane
kubectl describe namespace observability-plane
```

## Files Created

1. `foundation-namespaces.yaml` - Creates the three foundation namespaces
2. `resource-quotas.yaml` - Defines ResourceQuota objects for each namespace
3. `limit-ranges.yaml` - Defines LimitRange objects for each namespace

## Deployment Order
1. Create namespaces
2. Apply ResourceQuotas
3. Apply LimitRanges