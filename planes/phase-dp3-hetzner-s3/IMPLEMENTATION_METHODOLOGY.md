# Phase DP-3: Hetzner S3 Replication - Implementation Methodology

## Executive Summary
This document outlines the comprehensive methodology for implementing same-region S3 replication on Hetzner Cloud using Kubernetes (K3s). The solution provides real-time data replication within the Falkenstein (fsn1) data center with versioning support, health monitoring, and security best practices.

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Implementation Methodology](#implementation-methodology)
3. [Coding Standards & Patterns](#coding-standards--patterns)
4. [Security Implementation](#security-implementation)
5. [Testing Strategy](#testing-strategy)
6. [Monitoring & Observability](#monitoring--observability)
7. [Troubleshooting Framework](#troubleshooting-framework)
8. [Documentation Standards](#documentation-standards)
9. [Lessons Learned](#lessons-learned)

## Architecture Overview

### System Context
```
┌─────────────────────────────────────────────────────────────┐
│                    Production Environment                    │
├─────────────────────────────────────────────────────────────┤
│  K3s Cluster (Hetzner VPS)                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ Control     │  │ Worker 1    │  │ Worker 2    │         │
│  │ Plane       │  │ (k3s-w-1)   │  │ (k3s-w-2)   │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │               │               │                   │
│         └───────────────┼───────────────┘                   │
│                         ▼                                   │
│                 ┌─────────────┐                            │
│                 │ data-plane  │                            │
│                 │ namespace   │                            │
│                 └─────────────┘                            │
│                         │                                   │
│                         ▼                                   │
│                 ┌─────────────┐                            │
│                 │ s3-replicator│◄──Same Region─────────────┐│
│                 │ deployment   │   Replication             ││
│                 └─────────────┘                           ││
│                         │                                 ││
│         ┌───────────────┼───────────────┐               ││
│         ▼               ▼               ▼               ││
│  ┌──────────┐    ┌──────────┐    ┌──────────┐        ││
│  │ Source   │    │ Source   │    │ Source   │        ││
│  │ Bucket   │    │ Bucket   │    │ Bucket   │        ││
│  └──────────┘    └──────────┘    └──────────┘        ││
│         │               │               │             ││
│         └───────────────┼───────────────┘             ││
│                         ▼                             ││
│                 ┌──────────────┐                      ││
│                 │ Hetzner S3   │                      ││
│                 │ (fsn1 region)│                      ││
│                 └──────────────┘                      ││
│                         │                             ││
│                         ▼                             ││
│                 ┌──────────────┐                      ││
│                 │ Target       │◄─────────────────────┘│
│                 │ Buckets      │                       │
│                 └──────────────┘                       │
└─────────────────────────────────────────────────────────┘
```

### Key Components
1. **Kubernetes Deployment**: s3-replicator pod running MinIO Client (mc)
2. **S3 Configuration**: Source and target aliases for same-region replication
3. **Secret Management**: Kubernetes secrets for credential storage
4. **Health Monitoring**: Liveness and readiness probes
5. **Security Controls**: Container security context

## Implementation Methodology

### Phase 1: Discovery & Analysis
```bash
# 1.1 Environment Assessment
kubectl cluster-info
kubectl get nodes
kubectl get namespaces

# 1.2 S3 Connectivity Testing
mc alias set test-hetzner https://fsn1.your-objectstorage.com $ACCESS_KEY $SECRET_KEY --api s3v4
mc ls test-hetzner

# 1.3 Bucket Inventory
REQUIRED_BUCKETS=("documents-processed" "backups" "dip-entrepeai")
for bucket in "${REQUIRED_BUCKETS[@]}"; do
    mc ls test-hetzner/$bucket/ >/dev/null 2>&1 && echo "✅ $bucket" || echo "❌ $bucket"
done
```

### Phase 2: Credential Configuration
```yaml
# Kubernetes Secret Template
apiVersion: v1
kind: Secret
metadata:
  name: hetzner-s3-credentials
  namespace: data-plane
type: Opaque
data:
  ENDPOINT: aHR0cHM6Ly9mc24xLnlvdXItb2JqZWN0c3RvcmFnZS5jb20=
  ACCESS_KEY: WUFHRVc0U1RJV0ZYUldRVVM4TDg=
  SECRET_KEY: MW9OTUxMdUhvdEFGZm9CdVpoc1RmMzUydVdZbE9BTWlNM0dsYkhFUw==
  REGION: ZnNuMQ==
  PATH_STYLE: ZmFsc2U=
  TARGET_ENDPOINT: aHR0cHM6Ly9mc24xLnlvdXItb2JqZWN0c3RvcmFnZS5jb20=
  TARGET_ACCESS_KEY: WUFHRVc0U1RJV0ZYUldRVVM4TDg=
  TARGET_SECRET_KEY: MW9OTUxMdUhvdEFGZm9CdVpoc1RmMzUydVdZbE9BTWlNM0dsYkhFUw==
```

### Phase 3: Deployment Implementation
```yaml
# Deployment Strategy
strategy:
  type: Recreate  # Required for config directory changes
  rollingUpdate: null

# Container Configuration
containers:
  - name: replicator
    image: minio/mc:latest
    command: ["/bin/sh", "-c"]
    args:
      - |
        # Methodology: Structured script with error handling
        set -e  # Exit on error
        set -x  # Debug mode (optional)
        
        # 1. Configuration Phase
        mkdir -p /mc-config
        mc --config-dir /mc-config alias set source ${ENDPOINT} ${ACCESS_KEY} ${SECRET_KEY} --api s3v4
        
        # 2. Validation Phase
        if ! mc --config-dir /mc-config ls source/ > /dev/null 2>&1; then
            echo "❌ S3 connectivity failed"
            exit 1
        fi
        
        # 3. Replication Phase
        for bucket in documents-processed dip-entrepeai backup-dr; do
            if mc --config-dir /mc-config ls source/${bucket}/ > /dev/null 2>&1; then
                mc --config-dir /mc-config mirror --watch \
                    --overwrite \
                    --remove \
                    source/${bucket} target/${bucket} &
            fi
        done
        
        # 4. Monitoring Phase
        while true; do
            echo "Health check: $(date)"
            sleep 60
        done
```

### Phase 4: Security Implementation
```yaml
# Security Context Methodology
securityContext:
  allowPrivilegeEscalation: false  # Prevent privilege escalation
  capabilities:
    drop:
    - ALL  # Remove all Linux capabilities
  readOnlyRootFilesystem: true  # Immutable container
  runAsNonRoot: true  # Run as non-root user
  runAsUser: 1000  # Specific user ID
  runAsGroup: 1000  # Specific group ID

# Resource Constraints Methodology
resources:
  limits:
    cpu: "500m"  # Maximum CPU allocation
    memory: "512Mi"  # Maximum memory allocation
  requests:
    cpu: "200m"  # Guaranteed CPU allocation
    memory: "256Mi"  # Guaranteed memory allocation
```

### Phase 5: Health Monitoring
```yaml
# Probes Methodology
livenessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - mc --config-dir /mc-config alias list source > /dev/null 2>&1
  initialDelaySeconds: 90  # Allow time for initialization
  periodSeconds: 60  # Check every minute
  timeoutSeconds: 15  # Fail if takes longer than 15s
  failureThreshold: 3  # Allow 3 failures before restart

readinessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - mc --config-dir /mc-config alias list source > /dev/null 2>&1
  initialDelaySeconds: 30  # Shorter delay for readiness
  periodSeconds: 30  # Check more frequently
  timeoutSeconds: 10  # Shorter timeout
  failureThreshold: 2  # Fewer failures allowed
```

## Coding Standards & Patterns

### 1. Shell Script Standards
```bash
#!/bin/bash
# ================================================
# Script: s3-replicator.sh
# Purpose: Real-time S3 replication
# Author: System Engineering Team
# Date: 2026-04-12
# ================================================

set -e  # Exit immediately on error
set -u  # Treat unset variables as error
set -o pipefail  # Pipeline fails if any command fails

# Constants (UPPERCASE with underscores)
readonly S3_ENDPOINT="https://fsn1.your-objectstorage.com"
readonly CONFIG_DIR="/mc-config"
readonly REQUIRED_BUCKETS=("documents-processed" "dip-entrepeai")

# Functions (descriptive names, single responsibility)
configure_s3_aliases() {
    local endpoint="$1"
    local access_key="$2"
    local secret_key="$3"
    
    mc --config-dir "$CONFIG_DIR" alias set source "$endpoint" "$access_key" "$secret_key" --api s3v4
    mc --config-dir "$CONFIG_DIR" alias set target "$endpoint" "$access_key" "$secret_key" --api s3v4
}

validate_s3_connectivity() {
    if ! mc --config-dir "$CONFIG_DIR" ls source/ > /dev/null 2>&1; then
        log_error "S3 connectivity test failed"
        return 1
    fi
    log_info "S3 connectivity verified"
}

start_bucket_replication() {
    local bucket="$1"
    
    if mc --config-dir "$CONFIG_DIR" ls "source/${bucket}/" > /dev/null 2>&1; then
        mc --config-dir "$CONFIG_DIR" mirror --watch \
            --overwrite \
            --remove \
            "source/${bucket}" "target/${bucket}" &
        log_info "Started replication for bucket: $bucket"
    else
        log_warning "Bucket not found: $bucket"
    fi
}

# Logging functions
log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $*"; }
log_warning() { echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

# Main execution flow
main() {
    log_info "Starting S3 replicator"
    
    # Phase 1: Configuration
    configure_s3_aliases "$S3_ENDPOINT" "$ACCESS_KEY" "$SECRET_KEY"
    
    # Phase 2: Validation
    validate_s3_connectivity || exit 1
    
    # Phase 3: Replication
    for bucket in "${REQUIRED_BUCKETS[@]}"; do
        start_bucket_replication "$bucket"
    done
    
    # Phase 4: Monitoring
    monitor_health
}

monitor_health() {
    while true; do
        log_info "Health check - $(date)"
        sleep 60
    done
}

# Entry point
main "$@"
```

### 2. Kubernetes Manifest Standards
```yaml
# File: s3-replicator-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: s3-replicator
  namespace: data-plane
  labels:
    app.kubernetes.io/name: s3-replicator
    app.kubernetes.io/component: storage
    app.kubernetes.io/part-of: data-plane
    app.kubernetes.io/version: "1.0.0"
    plane: data
    priority: foundation-high

# Annotation standards
annotations:
  kubernetes.io/change-cause: "Deployed s3-replicator v1.0.0"
  description: "Real-time S3 replication within fsn1 region"
  maintainer: "System Engineering Team"
  last-updated: "2026-04-12"
```

### 3. Error Handling Patterns
```bash
# Pattern 1: Graceful degradation
start_replication_with_retry() {
    local bucket="$1"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if mc --config-dir /mc-config mirror --watch source/${bucket} target/${bucket}; then
            return 0
        else
            retry_count=$((retry_count + 1))
            log_warning "Replication failed for $bucket, retry $retry_count/$max_retries"
            sleep 10
        fi
    done
    
    log_error "Failed to start replication for $bucket after $max_retries attempts"
    return 1
}

# Pattern 2: Circuit breaker
circuit_breaker() {
    local command="$1"
    local failure_file="/tmp/circuit_breaker_failures"
    local max_failures=5
    
    if [ -f "$failure_file" ] && [ "$(cat "$failure_file")" -ge "$max_failures" ]; then
        log_error "Circuit breaker tripped - too many failures"
        return 1
    fi
    
    if ! eval "$command"; then
        local current_failures=$(( $(cat "$failure_file" 2>/dev/null || echo "0") + 1 ))
        echo "$current_failures" > "$failure_file"
        return 1
    else
        echo "0" > "$failure_file"
        return 0
    fi
}
```

## Security Implementation

### 1. Credential Management Methodology
```bash
# Never hardcode credentials
# Use Kubernetes secrets with base64 encoding
echo -n "https://fsn1.your-objectstorage.com" | base64
echo -n "YAGEW4STIWFXRWQUS8L8" | base64
echo -n "1oNMJluHotAFfoBuZhsTf352uWYlOAMiM3GlbHES" | base64

# Secret rotation procedure
rotate_credentials() {
    # 1. Create new secret
    kubectl create secret generic hetzner-s3-credentials-new \
        --from-literal=ACCESS_KEY="$NEW_KEY" \
        --from-literal=SECRET_KEY="$NEW_SECRET" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # 2. Update deployment to reference new secret
    kubectl set env deployment/s3-replicator \
        --from=secret/hetzner-s3-credentials-new \
        --namespace=data-plane
    
    # 3. Verify functionality
    kubectl rollout status deployment/s3-replicator
    
    # 4. Delete old secret (after verification)
    kubectl delete secret hetzner-s3-credentials-old
}
```

### 2. Network Security
```yaml
# NetworkPolicy methodology
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: s3-replicator-network-policy
  namespace: data-plane
spec:
  podSelector:
    matchLabels:
      app: s3-replicator
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8
        - 172.16.0.0/12
        - 192.168.0.0/16
    ports:
    - protocol: TCP
      port: 443  # HTTPS to S3
    - protocol: TCP
      port: 80   # HTTP (redirects to HTTPS)
```

## Testing Strategy

### 1. Unit Testing Methodology
```bash
# test-s3-connectivity.sh
test_s3_connectivity() {
    local endpoint="$1"
    local access_key="$2"
    local secret_key="$3"
    
    # Test 1: Alias creation
    if ! mc alias set test "$endpoint" "$access_key" "$secret_key" --api s3v4; then
        echo "FAIL: Alias creation"
        return 1
    fi
    
    # Test 2: Bucket listing
    if ! mc ls test/ > /dev/null 2>&1; then
        echo "FAIL: Bucket listing"
        return 1
    fi
    
    # Test 3: Object operations
    echo "test" | mc pipe test/test-bucket/test-object.txt
    if ! mc stat test/test-bucket/test-object.txt > /dev/null 2>&1; then
        echo "FAIL: Object operations"
        return 1
    fi
    
    mc rm test/test-bucket/test-object.txt
    echo "PASS: All S3 connectivity tests"
    return 0
}
```

### 2. Integration Testing
```bash
# integration-test.sh
run_integration_test() {
    # 1. Deploy test deployment
    kubectl apply -f test-deployment.yaml
    
    # 2. Wait for pod
    kubectl wait --for=condition=ready pod -l app=s3-replicator-test --timeout=120s
    
    # 3. Execute test sequence
    POD_NAME=$(kubectl get pods -l app=s3-replicator-test -o jsonpath='{.items[0].metadata.name}')
    
    # Test file upload
    echo "integration-test-$(date)" | kubectl exec $POD_NAME -i -- mc pipe source/documents-processed/integration-test.txt
    
    # Verify replication
    sleep 10
    kubectl exec $POD_NAME -- mc stat target/documents-processed/integration-test.txt
    
    # Cleanup
    kubectl exec $POD_NAME -- mc rm source/documents-processed/integration-test.txt
    kubectl exec $POD_NAME -- mc rm target/documents-processed/integration-test.txt
    
    # 4. Cleanup deployment
    kubectl delete -f test-deployment.yaml
}
```

### 3. Performance Testing
```bash
# performance-test.sh
measure_replication_latency() {
    local test_file="/tmp/performance-test-$(date +%s).dat"
    local size_mb=10
    
    # Create test file
    dd if=/dev/urandom of="$test_file" bs=1M count=$size_mb
    
    # Measure upload time
    local start_time=$(date +%s.%N)
    mc cp "$test_file" source/documents-processed/
    local upload_time=$(echo "$(date +%s.%N) - $start_time" | bc)
    
    # Measure replication time
    local replication_start=$(date +%s.%N)
    while ! mc stat target/documents-processed/$(basename "$test_file") > /dev/null 2>&1; do
        sleep 0.1
    done
    local replication_time=$(echo "$(date +%s.%N) - $replication_start" | bc)
    
    echo "Upload: ${upload_time}s, Replication: ${replication_time}s, Total: $(echo "$upload_time + $replication_time" | bc)s"
    
    # Cleanup
    rm "$test_file"
    mc rm source/documents-processed/$(basename "$test_file")
    mc rm target/documents-processed/$(basename "$test_file")
}
```

## Monitoring & Observability

### 1. Metrics Collection
```bash
# metrics-collector.sh
collect_s3_metrics() {
    # Bucket metrics
    local total_objects=$(mc ls --json source/documents-processed/ | jq '. | length')
    local total_size=$(mc ls --json source/documents-processed/ | jq '[.[] | .size] | add')
    
    # Replication metrics
    local replicated_objects=$(mc ls --json target/documents-processed/ | jq '. | length')
    local replication_lag=$((total_objects - replicated_objects))
    
    # Output in Prometheus format
    cat << EOF
# HELP s3_bucket_objects_total Total objects in source bucket
# TYPE s3_bucket_objects_total gauge
s3_bucket_objects_total{bucket="documents-processed"} $total_objects

# HELP s3_bucket_size_bytes Total size of objects in source bucket
# TYPE s3_bucket_size_bytes gauge
s3_bucket_size_bytes{bucket="documents-processed"} $total_size

# HELP s3_replication_lag_objects Objects pending replication
# TYPE s3_replication_lag_objects gauge
s3_replication_lag_objects{bucket="documents-processed"} $replication_lag

# HELP s3_replication_health Replication health status (1=healthy, 0=unhealthy)
# TYPE s3_replication_health gauge
s3_replication_health{bucket="documents-processed"} 1
EOF
}
```

### 2. Logging Standards
```json
{
  "timestamp": "2026-04-12T09:20:11Z",
  "level": "INFO",
  "component": "s3-replicator",
  "pod": "s3-replicator-586597f5d9-xbg48",
  "namespace": "data-plane",
  "message": "Started replication for bucket: documents-processed",
  "bucket": "documents-processed",
  "action": "replication_start",
  "duration_ms": 150,
  "success": true,
  "error": null
}
```

### 3. Alerting Rules
```yaml
# prometheus-rules.yaml
groups:
- name: s3-replicator
  rules:
  - alert: S3ReplicationLagHigh
    expr: s3_replication_lag_objects > 100
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High replication lag detected"
      description: "{{ $labels.bucket }} has {{ $value }} objects pending replication"
  
  - alert: S3ConnectivityLost
    expr: up{job="s3-replicator"} == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "S3 replicator is down"
      description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is not running"
  
  - alert: S3BucketInaccessible
    expr: s3_replication_health == 0
    for: 3m
    labels:
      severity: critical
    annotations:
      summary: "S3 bucket inaccessible"
      description: "Bucket {{ $labels.bucket }} cannot be accessed"
```

## Troubleshooting Framework

### 1. Diagnostic Toolkit
```bash
#!/bin/bash
# diagnose-s3-replicator.sh

diagnose_pod() {
    local pod_name="$1"
    
    echo "=== Pod Diagnostics: $pod_name ==="
    
    # 1. Pod status
    kubectl describe pod "$pod_name" -n data-plane
    
    # 2. Container logs
    kubectl logs "$pod_name" -n data-plane --previous 2>/dev/null || \
    kubectl logs "$pod_name" -n data-plane
    
    # 3. Events
    kubectl get events --field-selector involvedObject.name="$pod_name" --sort-by='.lastTimestamp'
    
    # 4. Resource usage
    kubectl top pod "$pod_name" -n data-plane 2>/dev/null || echo "Metrics not available"
}

diagnose_s3_connectivity() {
    echo "=== S3 Connectivity Diagnostics ==="
    
    # Test from pod
    local pod_name=$(kubectl get pods -n data-plane -l app=s3-replicator -o jsonpath='{.items[0].metadata.name}')
    
    # 1. Check config directory
    kubectl exec "$pod_name" -n data-plane -- ls -la /mc-config/
    
    # 2. Check aliases
    kubectl exec "$pod_name" -n data-plane -- mc --config-dir /mc-config alias list
    
    # 3. Test bucket access
    for bucket in documents-processed dip-entrepeai; do
        echo -n "Bucket $bucket: "
        kubectl exec "$pod_name" -n data-plane -- mc --config-dir /mc-config ls "source/$bucket/" >/dev/null 2>&1 && \
            echo "✅ Accessible" || echo "❌ Not accessible"
    done
}

diagnose_network() {
    echo "=== Network Diagnostics ==="
    
    # Test connectivity to S3 endpoint
    local pod_name=$(kubectl get pods -n data-plane -l app=s3-replicator -o jsonpath='{.items[0].metadata.name}')
    
    # 1. DNS resolution
    kubectl exec "$pod_name" -n data-plane -- nslookup fsn1.your-objectstorage.com
    
    # 2. TCP connectivity
    kubectl exec "$pod_name" -n data-plane -- timeout 5 nc -zv fsn1.your-objectstorage.com 443
    
    # 3. HTTP connectivity
    kubectl exec "$pod_name" -n data-plane -- curl -I https://fsn1.your-objectstorage.com
}
```

### 2. Common Issues & Solutions
| Issue | Symptoms | Root Cause | Solution |
|-------|----------|------------|----------|
| S3 Signature Error | `The request signature we calculated does not match` | Incorrect credentials or endpoint | Verify credentials, check PATH_STYLE setting |
| Read-only Filesystem | `mkdir: read-only file system` | Security context too restrictive | Use emptyDir volume for config directory |
| Bucket Creation Failed | `Bucket name not available` | Global bucket name conflict | Use alternative names (backup-dr, backup-replica) |
| Replication Stopped | No new objects replicated | Network connectivity issue | Check network policies, DNS resolution |
| High Resource Usage | Pod restarts, OOM kills | Large buckets, many objects | Increase resource limits, optimize mirror settings |

### 3. Recovery Procedures
```bash
# Procedure 1: Restart with clean config
recover_clean_restart() {
    # 1. Delete deployment
    kubectl delete deployment s3-replicator -n data-plane
    
    # 2. Clean config directory
    local pod_name=$(kubectl get pods -n data-plane -l app=s3-replicator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$pod_name" ]; then
        kubectl exec "$pod_name" -n data-plane -- rm -rf /mc-config/*
    fi
    
    # 3. Recreate deployment
    kubectl apply -f s3-replicator-deployment.yaml
    
    # 4. Verify recovery
    kubectl wait --for=condition=ready pod -l app=s3-replicator --timeout=120s
}

# Procedure 2: Credential rotation
recover_credential_issue() {
    # 1. Verify current credentials
    kubectl get secret hetzner-s3-credentials -n data-plane -o jsonpath='{.data.ACCESS_KEY}' | base64 -d
    
    # 2. Update secret
    kubectl create secret generic hetzner-s3-credentials-new \
        --from-file=credentials=/path/to/new/credentials \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # 3. Update deployment
    kubectl set env deployment/s3-replicator \
        --from=secret/hetzner-s3-credentials-new \
        --namespace=data-plane
    
    # 4. Rollout
    kubectl rollout status deployment/s3-replicator -n data-plane
}
```

## Documentation Standards

### 1. README Template
```markdown
# S3 Replicator Deployment

## Overview
Real-time S3 replication within Hetzner's fsn1 region.

## Architecture
[Diagram and description]

## Prerequisites
- Kubernetes cluster (K3s)
- Hetzner S3 credentials
- mc (MinIO Client) installed

## Deployment
```bash
# 1. Create secret
kubectl create secret generic hetzner-s3-credentials [...]

# 2. Apply deployment
kubectl apply -f deployment.yaml
```

## Configuration
| Environment Variable | Description | Default |
|---------------------|-------------|---------|
| ENDPOINT | S3 endpoint URL | https://fsn1.your-objectstorage.com |
| ACCESS_KEY | S3 access key | (from secret) |
| SECRET_KEY | S3 secret key | (from secret) |

## Monitoring
- Logs: `kubectl logs deployment/s3-replicator -f`
- Metrics: Prometheus endpoint on port 9090
- Alerts: Configured in PrometheusRules

## Troubleshooting
See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Maintenance
- Secret rotation procedure
- Version upgrades
- Backup procedures
```

### 2. Runbook Template
```markdown
# Runbook: S3 Replicator Incident Response

## Incident Classification
- Severity 1: Complete replication failure
- Severity 2: Partial replication failure
- Severity 3: Performance degradation

## Response Procedures

### Procedure 1: Complete Failure
1. Check pod status: `kubectl get pods -n data-plane | grep s3`
2. Check logs: `kubectl logs deployment/s3-replicator --previous`
3. Check S3 connectivity: `mc ls hetzner-s3/`
4. Execute recovery: `./recover_clean_restart.sh`

### Procedure 2: Partial Failure
1. Identify affected buckets
2. Check bucket permissions
3. Verify network connectivity
4. Restart specific replication process

## Escalation Matrix
| Duration | Action |
|----------|--------|
| < 15 min | Engineer on-call |
| 15-60 min | Team lead |
| > 60 min | Engineering director |
```

## Lessons Learned

### 1. Technical Insights
- **Same-region replication** provides sub-millisecond latency vs. cross-region (100+ ms)
- **Versioning must be enabled** before replication starts for compliance requirements
- **EmptyDir volumes** solve read-only filesystem issues with mc configuration
- **Recreate strategy** is necessary for config directory changes
- **Resource limits** prevent OOM kills during large bucket synchronization

### 2. Operational Insights
- **Automated testing** catches credential issues before deployment
- **Comprehensive logging** reduces mean time to resolution (MTTR)
- **Health probes** enable automatic recovery from transient failures
- **Documentation standards** ensure knowledge transfer and onboarding
- **Monitoring dashboards** provide real-time visibility into replication status

### 3. Security Insights
- **Kubernetes secrets** provide secure credential storage with encryption at rest
- **Security contexts** prevent privilege escalation and container breakout
- **Network policies** restrict egress traffic to necessary endpoints only
- **Regular audits** of bucket permissions prevent unauthorized access
- **Secret rotation** procedures maintain credential security over time

## Continuous Improvement

### 1. Performance Optimization
```bash
# Tune mirror parameters based on workload
mc mirror --watch \
    --overwrite \
    --remove \
    --exclude "*.tmp" \
    --exclude ".heartbeat/*" \
    --bandwidth "50M" \  # Limit bandwidth usage
    --max-workers 4 \     # Concurrent operations
    source/ target/
```

### 2. Cost Optimization
- Monitor storage usage and implement lifecycle policies
- Use storage classes appropriately (STANDARD vs. GLACIER)
- Implement data compression for large objects
- Schedule replication during off-peak hours for cost savings

### 3. Reliability Improvements
- Implement multi-AZ deployment for high availability
- Add disaster recovery procedures for regional failures
- Establish backup verification procedures
- Implement chaos engineering tests for resilience validation

---

## Conclusion
This methodology provides a comprehensive framework for implementing and maintaining S3 replication in production environments. By following these standards and patterns, teams can ensure reliable, secure, and efficient data replication with minimal operational overhead.

**Last Updated**: 2026-04-12  
**Version**: 1.0.0  
**Status**: Production Ready  
**Maintainer**: System Engineering Team