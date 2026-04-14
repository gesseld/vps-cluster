# BS-2: ResourceQuotas + LimitRanges per Namespace

## Overview
This directory contains the implementation for Task BS-2: Enforcing namespace-level resource budgets and container-level defaults.

## Objective
Enforce namespace-level resource budgets and container-level defaults through ResourceQuotas and LimitRanges for three foundation namespaces.

## Deliverables Created

### 1. YAML Manifests (`shared/` directory)
- `foundation-namespaces.yaml` - Creates control-plane, data-plane, and observability-plane namespaces
- `resource-quotas.yaml` - Defines ResourceQuota objects with hard limits for each namespace
- `limit-ranges.yaml` - Defines LimitRange objects with default requests/limits for each namespace
- `resource-budget.md` - Documentation explaining quota rationale and budget table

### 2. Implementation Scripts (`scripts/planes/` directory)
- `01-pre-deployment-check.sh` - Validates all prerequisites before deployment
- `02-deployment.sh` - Implements and deploys all resources to the VPS cluster
- `03-validation.sh` - Validates all deliverables and ensures proper functionality

## Resource Budget

### Control Plane
- **Request Memory**: 2.8Gi
- **Limit Memory**: 4.2Gi  
- **Request CPU**: 1.8 cores
- **Limit CPU**: 3.2 cores
- **Max Pods**: 15

### Data Plane
- **Request Memory**: 3.2Gi
- **Limit Memory**: 4.8Gi
- **Request CPU**: 2.4 cores
- **Limit CPU**: 4.0 cores
- **Max Pods**: 20

### Observability Plane
- **Request Memory**: 1.6Gi
- **Limit Memory**: 2.4Gi
- **Request CPU**: 1.2 cores
- **Limit CPU**: 2.0 cores
- **Max Pods**: 10

## Usage Instructions

### 1. Pre-Deployment Check
```bash
cd scripts/planes
./01-pre-deployment-check.sh
```

Validates:
- Cluster connectivity and node status
- Kubernetes API availability
- Existing namespace conflicts
- Resource availability
- Required YAML files
- User permissions

### 2. Deployment
```bash
cd scripts/planes
./02-deployment.sh
```

Deploys:
1. Foundation namespaces with appropriate labels
2. ResourceQuotas with hard limits
3. LimitRanges with default values
4. Test pod to verify functionality

### 3. Validation
```bash
cd scripts/planes
./03-validation.sh
```

Validates:
- All required files exist and are valid
- Namespaces are created with correct labels
- ResourceQuotas are deployed with correct limits
- LimitRanges are deployed with default values
- Documentation is complete
- Functional testing of quota enforcement

## Validation Commands

After deployment, you can manually verify with:

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

## Design Principles

1. **Predictability**: Each namespace has guaranteed minimum resources (requests)
2. **Burst Capacity**: Limits provide headroom for temporary spikes
3. **Isolation**: Namespaces cannot starve each other of resources
4. **Safety Nets**: Defaults prevent "no limits" containers
5. **Reasonable Scaling**: Max limits prevent runaway resource consumption

## Files Structure

```
shared/
├── foundation-namespaces.yaml    # Namespace definitions
├── resource-quotas.yaml          # ResourceQuota definitions  
├── limit-ranges.yaml             # LimitRange definitions
└── resource-budget.md            # Documentation

scripts/planes/
├── 01-pre-deployment-check.sh    # Prerequisite validation
├── 02-deployment.sh              # Implementation script
├── 03-validation.sh              # Deliverable validation
└── README.md                     # This file
```

## Success Criteria

- [x] All three foundation namespaces created
- [x] ResourceQuotas deployed with correct hard limits
- [x] LimitRanges deployed with default requests/limits
- [x] Documentation created with budget rationale
- [x] Three scripts created (pre-deployment, deployment, validation)
- [x] All scripts are executable and tested
- [x] Resource budgeting is functional and enforceable