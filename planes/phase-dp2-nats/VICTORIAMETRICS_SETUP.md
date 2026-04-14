# VictoriaMetrics Setup for NATS JetStream

## 📊 Overview

This guide provides complete VictoriaMetrics integration for NATS JetStream backpressure monitoring. The implementation includes VMAgent scrape configuration, VMAlert rules, and Grafana dashboards specifically designed for VictoriaMetrics.

## 🎯 Key Features

- **VMAgent scrape configuration** for NATS metrics
- **VMAlert rules** for backpressure monitoring (>80% threshold)
- **Grafana dashboard** optimized for VictoriaMetrics
- **Kubernetes service discovery** for automatic pod detection
- **Performance-optimized** metric relabeling

## 🚀 Quick Start

### 1. Apply VMAgent Configuration

```bash
# Apply the VMAgent configuration
kubectl apply -f data-plane/nats/vmagent-config.yaml -n default
```

### 2. Verify Configuration

```bash
# Check VMAgent targets
kubectl port-forward svc/vmagent 8429:8429 &
curl http://localhost:8429/targets | grep nats

# Check metrics endpoint
curl http://nats-exporter.default.svc.cluster.local:7777/metrics | head -5
```

### 3. Query Metrics in VictoriaMetrics

```bash
# Check if metrics are being collected
curl -g 'http://victoriametrics:8428/api/v1/query?query=up{job="nats-jetstream"}'

# Query stream backpressure
curl -g 'http://victoriametrics:8428/api/v1/query?query=nats_jetstream_stream_total_bytes{stream="DOCUMENTS"}/nats_jetstream_stream_config_max_bytes{stream="DOCUMENTS"}*100'
```

## 🔧 Configuration Details

### VMAgent Scrape Configuration

The configuration includes two scrape methods:

#### 1. Static Target Configuration
```yaml
- job_name: 'nats-jetstream'
  static_configs:
    - targets: ['nats-exporter.default.svc.cluster.local:7777']
```

#### 2. Kubernetes Service Discovery
```yaml
- job_name: 'kubernetes-pods-nats'
  kubernetes_sd_configs:
    - role: pod
      namespaces: [default]
```

### Metric Relabeling for Optimization

```yaml
metric_relabel_configs:
  # Keep only NATS metrics
  - source_labels: [__name__]
    regex: 'nats_.*'
    action: keep
  
  # Add stream labels
  - source_labels: [stream]
    regex: '(.*)'
    target_label: stream
```

### VMAlert Rules

Key alert rules for backpressure monitoring:

```yaml
- alert: NATSStreamDocumentsBackpressureHigh
  expr: nats_jetstream_stream_total_bytes{stream="DOCUMENTS"} / nats_jetstream_stream_config_max_bytes{stream="DOCUMENTS"} > 0.8
  for: 5m
  labels:
    severity: warning
```

## 📈 Grafana Dashboard

### Import Dashboard

1. **Download dashboard JSON** from `data-plane/nats/metrics-exporter.yaml` (look for `grafana-dashboard-vm.json`)
2. **Import into Grafana**:
   - Navigate to Dashboards → Import
   - Paste the JSON content
   - Select VictoriaMetrics as datasource
   - Set dashboard variables:
     - `$datasource`: VictoriaMetrics
     - `$cluster`: default (or your cluster name)

### Dashboard Panels

The dashboard includes:

1. **Stream Backpressure %** - Real-time percentage of stream capacity
2. **Consumer Pending Messages** - Messages waiting for consumption
3. **Stream Message Count** - Total messages per stream
4. **Stream Bytes Storage** - Storage usage per stream

## 🔍 Monitoring Key Metrics

### Stream Metrics
```bash
# Bytes backpressure
nats_jetstream_stream_total_bytes{stream="DOCUMENTS"} / nats_jetstream_stream_config_max_bytes{stream="DOCUMENTS"} * 100

# Messages backpressure  
nats_jetstream_stream_total_msgs{stream="DOCUMENTS"} / nats_jetstream_stream_config_max_msgs{stream="DOCUMENTS"} * 100
```

### Consumer Metrics
```bash
# Pending messages
nats_jetstream_stream_consumer_pending_msgs

# Delivery rate
rate(nats_jetstream_stream_consumer_delivered_msgs[5m])
```

### Server Metrics
```bash
# Connections
nats_core_num_connections

# Memory usage
nats_jetstream_stream_memory_bytes
```

## ⚡ Performance Tuning

### Scrape Interval Optimization

| Interval | Use Case | Impact |
|----------|----------|---------|
| **15s** | Default | Good balance of freshness vs load |
| **30s** | High-scale | Lower load, less frequent updates |
| **5s** | Debugging | High resolution, higher load |

### Storage Optimization

Configure in VictoriaMetrics:

```yaml
# Retention period
retentionPeriod: 30d

# Downsampling for long-term storage
downsampling:
  enabled: true
  interval: 1h  # Downsample to 1h intervals after 7 days
```

### VMAgent Resource Limits

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "200m"
```

## 🛠️ Integration Methods

### Method A: Add to Existing VMAgent

1. **Extract current config**:
   ```bash
   kubectl get configmap vmagent-config -o yaml > vmagent-config.yaml
   ```

2. **Add NATS scrape config** from `nats-jetstream-scrape.yaml`

3. **Update and restart**:
   ```bash
   kubectl apply -f vmagent-config.yaml
   kubectl rollout restart deployment/vmagent
   ```

### Method B: Separate ConfigMap (Recommended)

1. **Apply the config**:
   ```bash
   kubectl apply -f data-plane/nats/vmagent-config.yaml
   ```

2. **Configure VMAgent to watch additional ConfigMaps**:
   ```yaml
   args:
     - -promscrape.config=/etc/vmagent/config/*.yaml
   volumeMounts:
     - name: extra-config
       mountPath: /etc/vmagent/config
   volumes:
     - name: extra-config
       configMap:
         name: nats-vmagent-scrape-config
   ```

### Method C: VictoriaMetrics Single/Cluster

1. **Create secret**:
   ```bash
   kubectl apply -f data-plane/nats/vmagent-config.yaml
   ```

2. **Mount in VictoriaMetrics**:
   ```yaml
   volumes:
     - name: extra-scrape-config
       secret:
         secretName: nats-vm-extra-scrape-config
   volumeMounts:
     - name: extra-scrape-config
       mountPath: /etc/victoria-metrics/extra-scrape-configs
   ```

## 🔍 Troubleshooting

### No Metrics in VictoriaMetrics

1. **Check VMAgent targets**:
   ```bash
   curl http://vmagent:8429/targets | grep nats
   ```

2. **Check exporter endpoint**:
   ```bash
   curl http://nats-exporter.default.svc.cluster.local:7777/metrics | head -5
   ```

3. **Check VMAgent logs**:
   ```bash
   kubectl logs deployment/vmagent | grep -i nats
   ```

4. **Verify ConfigMap mounting**:
   ```bash
   kubectl exec deployment/vmagent -- ls -la /etc/vmagent/config/
   ```

### High Scrape Latency

1. **Check scrape duration**:
   ```bash
   curl http://vmagent:8429/metrics | grep vmagent_scrape_duration_seconds
   ```

2. **Reduce scrape interval**:
   ```yaml
   scrape_interval: 30s  # Increase from 15s to 30s
   ```

3. **Optimize metric relabeling**:
   ```yaml
   # Drop unnecessary labels
   - source_labels: [pod]
     regex: '.*'
     action: labeldrop
   ```

### Alert Not Firing

1. **Check VMAlert configuration**:
   ```bash
   kubectl get configmap vmalert-config -o yaml | grep -A5 nats
   ```

2. **Verify rule evaluation**:
   ```bash
   curl http://vmalert:8880/api/v1/groups | jq '.data[] | select(.name=="nats_jetstream_backpressure")'
   ```

3. **Check alert expression**:
   ```bash
   curl -g 'http://victoriametrics:8428/api/v1/query?query=nats_jetstream_stream_total_bytes{stream="DOCUMENTS"}/nats_jetstream_stream_config_max_bytes{stream="DOCUMENTS"}'
   ```

## 📊 Alert Thresholds

| Alert | Threshold | Duration | Severity | Action |
|-------|-----------|----------|----------|---------|
| **Stream Backpressure** | >80% | 5m | Warning | Increase stream limits |
| **Stream Backpressure** | >90% | 5m | Critical | Immediate action required |
| **Pending Messages** | >1000 | 2m | Warning | Scale consumers |
| **Server Down** | 0 up | 1m | Critical | Check pod status |

## 🔄 Multi-cluster Monitoring

For monitoring multiple NATS clusters:

```yaml
scrape_configs:
  - job_name: 'nats-jetstream-{{CLUSTER_NAME}}'
    static_configs:
      - targets: ['nats-exporter.{{NAMESPACE}}.svc.cluster.local:7777']
        labels:
          cluster: '{{CLUSTER_NAME}}'
          environment: 'production'
```

## 📚 Useful VictoriaMetrics Queries

### Stream Health Overview
```bash
# All streams backpressure
curl -g 'http://victoriametrics:8428/api/v1/query?query=nats_jetstream_stream_total_bytes/nats_jetstream_stream_config_max_bytes*100'

# Top 3 streams by size
curl -g 'http://victoriametrics:8428/api/v1/query?query=topk(3, nats_jetstream_stream_total_bytes)'
```

### Consumer Performance
```bash
# Slowest consumers
curl -g 'http://victoriametrics:8428/api/v1/query?query=topk(5, nats_jetstream_stream_consumer_pending_msgs)'

# Consumer delivery rate
curl -g 'http://victoriametrics:8428/api/v1/query?query=rate(nats_jetstream_stream_consumer_delivered_msgs[5m])'
```

### Server Performance
```bash
# Connection count over time
curl -g 'http://victoriametrics:8428/api/v1/query_range?query=nats_core_num_connections&start=$(date -d "1 hour ago" +%s)&end=$(date +%s)&step=30s'

# Memory usage trend
curl -g 'http://victoriametrics:8428/api/v1/query_range?query=nats_jetstream_stream_memory_bytes&start=$(date -d "1 hour ago" +%s)&end=$(date +%s)&step=30s'
```

## 🎯 Best Practices

### 1. Label Consistency
- Use consistent label names across all metrics
- Include `cluster`, `environment`, `component` labels
- Avoid high-cardinality labels in alerts

### 2. Retention Strategy
- Keep 30 days of high-resolution data
- Downsample to 1h intervals after 7 days
- Archive older data to object storage

### 3. Alert Design
- Use meaningful alert names and descriptions
- Include actionable instructions in annotations
- Set appropriate `for` durations to prevent flapping

### 4. Dashboard Design
- Use variables for cluster and stream selection
- Include both current values and trends
- Add documentation panels with links to runbooks

## 🔗 References

- [VictoriaMetrics Documentation](https://docs.victoriametrics.com/)
- [VMAgent Configuration](https://docs.victoriametrics.com/vmagent.html)
- [VMAlert Rules](https://docs.victoriametrics.com/vmalert.html)
- [NATS Metrics Documentation](https://docs.nats.io/running-a-nats-service/nats_admin/monitoring)
- [Grafana VictoriaMetrics Integration](https://grafana.com/docs/grafana/latest/datasources/victoriametrics/)