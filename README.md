# VPS Cluster Deployment - Clean Architecture

This repository contains a clean, production-ready Kubernetes cluster deployment for VPS environments following a strict architectural specification.

## Architecture Overview

The deployment follows a multi-plane architecture with strict deployment sequencing:

1. **Phase 0: Budget Scaffolding** (MANDATORY FIRST)
   - PriorityClasses
   - ResourceQuotas and LimitRanges
   - StorageClass
   - Node Labels
   - Network Policies

2. **Data Plane** (Phase 2)
   - PostgreSQL
   - Temporal (Workflow Engine)
   - NATS (Messaging)
   - Redis (Caching)
   - S3-Compatible Storage

3. **Control Plane** (Phase 3)
   - Kyverno (Policy Engine)
   - SPIRE (Identity Management)
   - ArgoCD (GitOps)
   - Control NATS

4. **Observability Plane** (Phase 4)
   - VictoriaMetrics (Metrics)
   - Fluent Bit (Logging)
   - Loki (Log Aggregation)
   - AlertManager (Alerts)

## Key Features

- **Temporal in Data Plane**: Corrected architectural placement (was incorrectly in Control Plane)
- **Strict Deployment Sequence**: Phase 0 MUST be deployed before any plane workloads
- **Production-Ready**: HA configurations, proper resource management
- **Clean Structure**: Organized by architectural planes
- **Documentation**: Complete deployment guides and validation scripts

## Getting Started

1. Deploy Phase 0 first:
   ```bash
   cd phase-0-budget-scaffolding
   ./deploy-phase-0.sh
   ```

2. Follow the deployment sequence in `DEPLOYMENT_SEQUENCE.md`

3. Validate deployment with validation scripts

## Repository Structure

```
├── phase-0-budget-scaffolding/  # Budget scaffolding (deploy first)
├── data-plane/                  # Temporal, PostgreSQL, NATS, Redis, S3
├── control-plane/               # Kyverno, SPIRE, ArgoCD, Control NATS
├── observability-plane/         # VictoriaMetrics, Fluent Bit, Loki
├── shared/                      # PKI, RBAC, Network Policies
├── docs/                        # Architectural documentation
├── archive/                     # Archived messy state (reference only)
└── README.md                    # This file
```

## Important Notes

- **Temporal Version**: 1.30.4
- **Helm Version**: v4.1.3
- **Architectural Specification**: v4.0.4 (updated to place Temporal in Data Plane)
- **Non-negotiable**: Phase 0 MUST be deployed before any plane workloads

## License

MIT License - See LICENSE file for details.
