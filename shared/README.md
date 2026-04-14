# Shared Foundations

## Purpose
Cross-cutting concerns that all planes depend on. Deployed in **Phase 1** after Budget Scaffolding.

## Components

### 1. PKI Bootstrap (Cert-Manager + SPIRE)
- Certificate authority for mTLS
- SPIRE Server + Agent with PostgreSQL backend
- Fallback mode for operational resilience

### 2. RBAC Baseline
- Least-privilege service accounts per plane
- Minimal roles for foundation workloads
- Documentation in rbac-matrix.md

### 3. Network Policies
- Default-deny applied to all planes
- Explicit allow rules for known dependencies
- Zero-trust boundaries enforced

### 4. Storage Classes
- `nvme-waitfirst`: WaitForFirstConsumer for topology awareness
- Configured in Phase 0: Budget Scaffolding

## Deployment Sequence
1. **After** Phase 0: Budget Scaffolding
2. **Before** any plane workloads
3. **Required** for zero-trust security model
