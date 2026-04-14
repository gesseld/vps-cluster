# Redis Phase DP-4: Multi-Role Cache Tier (RDB-only + Memory Protection)

## Objective
Deploy Redis 7+ as a cache tier with reduced I/O (AOF disabled), memory safeguards, and logical database separation for different use cases.

## Architecture
- **Redis 7+**: Single instance with RDB snapshots only
- **Persistence**: RDB-only (`save 900 1`, `save 300 10`, `save 60 10000`)
- **AOF**: Disabled to reduce disk I/O (`appendonly no`)
- **Memory**: 512MB limit with `allkeys-lru` eviction policy
- **Logical Databases**:
  - DB 0: Sessions (TTL 24h)
  - DB 1: Rate limiting (TTL 1h)
  - DB 2: Semantic cache for AI Plane (TTL 7d)
- **Monitoring**: Sidecar exporter for Prometheus metrics
- **Alerting**: Memory alerts (>450MB warning, >500MB critical)

## Prerequisites
1. Kubernetes cluster with kubectl access
2. Storage class (default: `hcloud-volumes`)
3. Prometheus monitoring stack (optional, for alerts)
4. Network policies allowing control plane to access Redis (port 6379)

## Deployment Steps

### 1. Pre-deployment Check
```bash
./01-pre-deployment-check.sh
```
Validates cluster access, storage classes, existing resources, and configuration.

### 2. Deployment
```bash
./02-deployment.sh
```
Deploys all components:
- Redis ConfigMap with RDB-only configuration
- Redis Deployment with sidecar exporter
- Service for Redis (6379) and metrics (9121)
- Prometheus alerts for memory monitoring

### 3. Validation
```bash
./03-validation.sh
```
Validates the deployment:
- Pod and service status
- Redis configuration (AOF disabled, memory limits)
- Database functionality and isolation
- Metrics endpoint
- Alert rules

## Configuration

### Environment Variables
Create `.env` file or set variables:
```bash
export NAMESPACE=default
export REDIS_VERSION=7.2
export STORAGE_CLASS=hcloud-volumes
```

### Redis Configuration (`data-plane/redis/configmap.yaml`)
- RDB persistence with 3 save points
- AOF disabled (`appendonly no`)
- Maxmemory: 512MB with `allkeys-lru` eviction
- 3 logical databases
- Performance tuning for cache workload

### Components

#### 1. Redis Deployment (`data-plane/redis/deployment.yaml`)
- Redis 7.2 Alpine image
- Resource limits: 512MB RAM, 500m CPU
- EmptyDir volume for data
- Liveness and readiness probes
- Security context with non-root user

#### 2. Redis Exporter Sidecar
- `oliver006/redis_exporter:v1.60.0`
- Exposes metrics at port 9121
- Scraped by Prometheus via annotations

#### 3. Service (`data-plane/redis/deployment.yaml`)
- ClusterIP service
- Port 6379 for Redis
- Port 9121 for metrics

#### 4. Prometheus Alerts (`data-plane/redis/metrics-alert.yaml`)
- Memory alerts: >450MB warning, >500MB critical
- Redis down detection
- Connection and performance alerts

## Validation Tests

### Configuration Validation
```bash
# Check AOF is disabled
redis-cli CONFIG GET appendonly  # should return "no"

# Check memory configuration
redis-cli CONFIG GET maxmemory    # should return "536870912" (512MB)
redis-cli CONFIG GET maxmemory-policy  # should return "allkeys-lru"

# Check RDB configuration
redis-cli CONFIG GET save  # should return "900 1 300 10 60 10000"
```

### Functionality Tests
```bash
# Test database isolation
redis-cli -n 0 SET session:test "data" EX 86400
redis-cli -n 1 SET ratelimit:test "data" EX 3600
redis-cli -n 2 SET semantic:test "data" EX 604800

# Verify TTL
redis-cli -n 0 TTL session:test    # ~86400 seconds
redis-cli -n 1 TTL ratelimit:test  # ~3600 seconds
redis-cli -n 2 TTL semantic:test   # ~604800 seconds
```

### Metrics Validation
```bash
# Check metrics endpoint
curl http://redis.default.svc.cluster.local:9121/metrics | grep redis_

# Check specific metrics
curl -s http://redis.default.svc.cluster.local:9121/metrics | grep -E "redis_up|redis_memory_used_bytes"
```

## Memory Management

### Eviction Policy: `allkeys-lru`
- Removes least recently used keys when memory limit is reached
- Suitable for cache workloads
- Preserves recent access patterns

### Alert Thresholds
- **Warning**: >450MB used memory (87.5% of limit)
- **Critical**: >500MB used memory (97.5% of limit)
- Alert triggers after 5 minutes of sustained high usage

### Database-specific TTL
1. **DB 0 (Sessions)**: 24h TTL
   - User sessions, authentication tokens
   - Automatic cleanup after 24h

2. **DB 1 (Rate limiting)**: 1h TTL
   - API rate limit counters
   - Short-lived, frequently updated

3. **DB 2 (Semantic cache)**: 7d TTL
   - AI model responses, embeddings
   - Longer retention for expensive computations

## Performance Considerations

### RDB-only Advantages
- Reduced disk I/O compared to AOF
- Periodic snapshots instead of continuous writes
- Faster restart recovery (loads single RDB file)

### Memory Optimization
- `lazyfree-lazy-eviction yes`: Non-blocking eviction
- `lazyfree-lazy-expire yes`: Non-blocking expiration
- `activerehashing yes`: Incremental rehashing

### Connection Management
- `maxclients 10000`: High connection limit
- Connection pooling recommended for applications
- Monitor `redis_connected_clients` metric

## Troubleshooting

### Pod Not Starting
1. Check resource limits: `kubectl describe pod <redis-pod>`
2. Check storage class: `kubectl get storageclass`
3. Check security policies: `kubectl get psp` or PodSecurity admission

### High Memory Usage
1. Check evicted keys: `redis-cli INFO stats | grep evicted_keys`
2. Analyze key patterns: `redis-cli --bigkeys`
3. Consider increasing memory limit or optimizing data

### Connection Issues
1. Check network policies: `kubectl get networkpolicies`
2. Verify service: `kubectl get service redis`
3. Test connectivity: `kubectl run -it --rm test --image=redis -- redis-cli -h redis`

### Metrics Not Available
1. Check exporter logs: `kubectl logs <redis-pod> -c redis-exporter`
2. Verify Prometheus scrape config
3. Check service annotations

## Cleanup
```bash
# Delete all Redis resources
kubectl delete -f data-plane/redis/
kubectl delete configmap redis-config
kubectl delete prometheusrules redis-memory-alert 2>/dev/null || true
```

## Deliverables Checklist
- [x] `data-plane/redis/configmap.yaml` (redis.conf)
- [x] `data-plane/redis/deployment.yaml`
- [x] `data-plane/redis/metrics-alert.yaml`
- [x] Pre-deployment script (`01-pre-deployment-check.sh`)
- [x] Deployment script (`02-deployment.sh`)
- [x] Validation script (`03-validation.sh`)

## Validation Requirements Met
- [x] `redis-cli CONFIG GET appendonly` returns "no"
- [x] `redis-cli INFO keyspace` shows 3 databases
- [x] Memory usage < 450MB under normal load
- [x] Memory alerts configured for >450MB
- [x] RDB snapshots configured (900 1, 300 10, 60 10000)
- [x] Logical databases with appropriate TTLs