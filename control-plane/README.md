# Phase 3: Control Plane

**Deployment Sequence:** After Phase 2 (Data Plane), before Phase 4 (Observability Plane)

## Purpose
The **governance layer**: policy enforcement, identity management, and GitOps. Manages security, compliance, and deployment orchestration across all planes.

## Components
1. **Kyverno**: Policy engine with rate limiting and security policies
2. **SPIRE**: Identity foundation with PostgreSQL backend and fallback mode
3. **ArgoCD**: GitOps controller with drift detection and API protection
4. **Control NATS**: Stateless signaling for critical control messages

## Deployment Order
1. Kyverno (policy engine)
2. SPIRE Server (identity management)
3. ArgoCD (GitOps)
4. Control NATS (stateless messaging)

## Validation
```bash
./scripts/validate-phase-gates.sh 3
```

## Important Notes
- **SPIRE Dependency**: Requires PostgreSQL from Data Plane for backend storage
- **Policy Enforcement**: Kyverno policies enforce labels, resource limits, and security baselines
- **GitOps**: ArgoCD manages all subsequent deployments via Git
