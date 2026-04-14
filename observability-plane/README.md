# Phase 4: Observability Plane

**Deployment Sequence:** After Phase 3 (Control Plane), last phase

## Purpose
The **sensory system**: unified telemetry collection (logs + metrics), long-term storage, and alerting. Uses VictoriaMetrics (not Prometheus) for 60% resource savings and Fluent Bit (not Promtail+OTel) for unified log shipping.

## Components
1. **VictoriaMetrics**: High-performance TSDB with cardinality control and backup
2. **vmagent**: Efficient metrics collection with relabeling and egress control
3. **Fluent Bit**: Unified log pipeline with noise reduction and audit enrichment
4. **Loki**: Log aggregation with S3 backend and tiered retention
5. **Alerting**: Burn-rate alerting with intelligent routing and inhibition

## Deployment Order
1. VictoriaMetrics (metrics storage)
2. vmagent (metrics collection)
3. Fluent Bit (log collection)
4. Loki (log storage)
5. Alerting + Grafana (visualization)

## Validation
```bash
./scripts/validate-phase-gates.sh 4
```

## Important Notes
- **Deployed Last**: Avoids self-monitoring bootstrap issues
- **Resource Budget**: 1.5GB RAM request, 2.9GB RAM limit for Observability Plane
- **Cardinality Control**: Strict limits (<50k series) to prevent resource exhaustion
