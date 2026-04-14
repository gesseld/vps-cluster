# Observability Plane

## Purpose
The **eyes and ears**: telemetry collection, storage, visualization, and alerting. Lightweight but comprehensive coverage across all planes.

## Components

### 1. VictoriaMetrics (Time Series Database)
- Single instance mode (VMSingle)
- Cardinality controls
- 2s end-to-end latency target
- Long-term retention: 30 days

### 2. Fluent Bit (Logs + Metrics Shipping)
- Unified agent for logs and metrics
- Lower resource footprint than Promtail+OTel
- Output to Loki and VictoriaMetrics

### 3. Loki (Log Storage)
- Index-only mode for efficiency
- 7-day retention
- Compatible with Grafana

### 4. Grafana (Visualization)
- Pre-configured dashboards for all planes
- Single sign-on integration
- Alert visualization

### 5. Alertmanager (Alert Routing)
- Differentiated routing: Critical → PagerDuty, Warning → Slack
- Deduplication and grouping
- Silence management

## Deployment Sequence
1. **After** Control Plane (to avoid self-monitoring bootstrap)
2. **After** Data Plane (metrics storage dependency)
3. **Last** in foundation deployment

## Resource Budget
- Requests: 1.5Gi memory, 1.0 CPU
- Limits: 2.9Gi memory, 1.9 CPU
- Priority: foundation-medium
