# Control Plane

## Purpose
The **brain** of the platform: workflow orchestration, policy enforcement, identity management, and GitOps. Does not process documents; manages the metadata and state transitions that govern processing.

## Components

### 1. Temporal (Workflow Orchestration)
- Version: 1.30.4
- HA: 2 replicas active-active
- Priority: foundation-critical
- Dependencies: PostgreSQL in Data Plane

### 2. Kyverno (Policy Engine)
- Policy enforcement and admission control
- Rate limiting for API protection
- Security baseline policies

### 3. SPIRE (Identity Foundation)
- Workload identity with mTLS
- PostgreSQL backend for persistence
- Fallback mode for operational resilience

### 4. ArgoCD (GitOps Controller)
- Declarative deployment with drift detection
- Protected API with rate limits
- ApplicationSets for multi-plane management

### 5. NATS (Control Signaling)
- Stateless instance for critical control signals
- TLS with Cert-Manager certificates
- Bridge to Data Plane NATS if needed

## Deployment Sequence
1. **After** Data Plane (PostgreSQL dependency)
2. **After** Shared Foundations (PKI, RBAC, Network Policies)
3. **After** Phase 0: Budget Scaffolding

## Resource Budget
- Requests: 2.8Gi memory, 1.8 CPU
- Limits: 4.2Gi memory, 3.2 CPU
- Priority: foundation-critical for Temporal
