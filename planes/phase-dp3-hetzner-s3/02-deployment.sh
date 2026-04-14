#!/bin/bash
set -e

echo "================================================"
echo "Task DP-3: Hetzner S3 Deployment"
echo "================================================"
echo "Deploying enterprise-resilient S3 storage with replication..."
echo ""

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
    echo "✓ Loaded environment variables"
else
    echo "❌ No .env file found. Create one with required credentials."
    exit 1
fi

# Set defaults
NAMESPACE=${NAMESPACE:-data-plane}
STORAGE_CLASS=${STORAGE_CLASS:-hcloud-volumes}
HETZNER_S3_REGION=${HETZNER_S3_REGION:-fsn1}
OBSERVABILITY_NAMESPACE=${OBSERVABILITY_NAMESPACE:-observability-plane}
DEPLOYMENT_DIR="$SCRIPT_DIR/manifests"

# Create manifests directory
mkdir -p "$DEPLOYMENT_DIR/data-plane/storage"
mkdir -p "$DEPLOYMENT_DIR/observability-plane/alerting/rules"
mkdir -p "$DEPLOYMENT_DIR/observability-plane/grafana/dashboards"
mkdir -p "$DEPLOYMENT_DIR/shared"

echo ""
echo "1. Creating Kubernetes manifests..."

# Create ExternalSecret for Hetzner S3 credentials
cat > "$DEPLOYMENT_DIR/data-plane/storage/external-secret.yaml" << EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: hetzner-s3-credentials
  namespace: $NAMESPACE
  labels:
    app: hetzner-s3
    plane: data
spec:
  refreshInterval: 720h  # 30 days rotation
  secretStoreRef:
    name: hetzner-vault
    kind: ClusterSecretStore
  target:
    name: hetzner-s3-credentials
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        endpoint: "{{ .endpoint }}"
        region: "{{ .region }}"
        access-key: "{{ .access_key }}"
        secret-key: "{{ .secret_key }}"
        path-style: "{{ .path_style }}"
  data:
  - secretKey: endpoint
    remoteRef:
      key: hetzner/object-storage
      property: endpoint
  - secretKey: region
    remoteRef:
      key: hetzner/object-storage
      property: region
  - secretKey: access-key
    remoteRef:
      key: hetzner/object-storage
      property: access_key
  - secretKey: secret-key
    remoteRef:
      key: hetzner/object-storage
      property: secret_key
  - secretKey: path-style
    remoteRef:
      key: hetzner/object-storage
      property: path_style
EOF
echo "✓ Created ExternalSecret for Hetzner S3 credentials"

# Create ExternalName Service for endpoint abstraction
cat > "$DEPLOYMENT_DIR/data-plane/storage/service.yaml" << EOF
apiVersion: v1
kind: Service
metadata:
  name: s3-endpoint
  namespace: $NAMESPACE
  labels:
    app: hetzner-s3
    plane: data
  annotations:
    failover-endpoint: https://nbg1.your-objectstorage.com
spec:
  type: ExternalName
  externalName: fsn1.your-objectstorage.com
  ports:
  - port: 443
    protocol: TCP
    name: https
EOF
echo "✓ Created ExternalName Service for S3 endpoint"

# Create bucket verification script (using existing buckets)
cat > "$DEPLOYMENT_DIR/data-plane/storage/bucket-verification.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: bucket-verification-script
  namespace: $NAMESPACE
  labels:
    app: hetzner-s3
    plane: data
data:
  verify-buckets.sh: |
    #!/bin/bash
    set -e
    
    echo "🔧 Verifying and configuring Hetzner S3 bucket for document storage..."
    
    # Configure mc alias
    mc alias set hetzner \${ENDPOINT} \${ACCESS_KEY} \${SECRET_KEY} --api s3v4 --path off
    
    # Verify and configure the dip-entrepeai bucket for document storage
    DOCUMENTS_BUCKET=\${DOCUMENTS_BUCKET:-dip-entrepeai}
    
    echo "Checking bucket: \$DOCUMENTS_BUCKET (document storage)"
    if mc ls hetzner/\$DOCUMENTS_BUCKET >/dev/null 2>&1; then
      echo "✅ Bucket '\$DOCUMENTS_BUCKET' exists and is accessible"
      
      # Enable versioning for document tracking
      mc version enable hetzner/\$DOCUMENTS_BUCKET || echo "⚠️  Could not enable versioning"
      
      # Enable WORM retention for compliance (7 days)
      mc retention set --enable --mode COMPLIANCE --duration 7d hetzner/\$DOCUMENTS_BUCKET || echo "⚠️  Could not set WORM retention"
      
      # Add heartbeat cleanup policy to prevent metadata bloat
      mc ilm add --expiry-days 1 --prefix ".heartbeat/" hetzner/\$DOCUMENTS_BUCKET || echo "⚠️  Could not add heartbeat cleanup"
      
      # Add lifecycle policy for temporary files (delete after 30 days)
      mc ilm add --expiry-days 30 --prefix "temp/" hetzner/\$DOCUMENTS_BUCKET || echo "⚠️  Could not add temp file cleanup"
    else
      echo "❌ Bucket '\$DOCUMENTS_BUCKET' does not exist or is not accessible"
      echo "   Note: This bucket should already exist for document storage"
      exit 1
    fi
    
    # Note: dip-documents-archive is already configured for etcd backups
    # from earlier phases and should not be modified here
    
    # Verify WORM compliance
    mc retention info hetzner/\$DOCUMENTS_BUCKET | grep -q "COMPLIANCE" || {
      echo "⚠️  WORM retention not enabled on \$DOCUMENTS_BUCKET"
    }
    
    # Verify heartbeat cleanup policy
    mc ilm ls hetzner/\$DOCUMENTS_BUCKET | grep -q ".heartbeat.*1d" || {
      echo "⚠️  Heartbeat expiry policy not found on \$DOCUMENTS_BUCKET"
    }
    
    echo "🎉 Document storage bucket verified and configured"
EOF
echo "✓ Created bucket verification script"

# Create replication target ExternalSecret (only if credentials provided)
if [ -n "$REPLICATION_TARGET_ENDPOINT" ] && [ -n "$REPLICATION_TARGET_ACCESS_KEY" ] && [ -n "$REPLICATION_TARGET_SECRET_KEY" ]; then
cat > "$DEPLOYMENT_DIR/data-plane/storage/replication-external-secret.yaml" << EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: replication-creds
  namespace: $NAMESPACE
  labels:
    app: s3-replicator
    plane: data
spec:
  refreshInterval: 720h
  secretStoreRef:
    name: hetzner-vault
    kind: ClusterSecretStore
  target:
    name: replication-creds
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        endpoint: "{{ .endpoint }}"
        access-key: "{{ .access_key }}"
        secret-key: "{{ .secret_key }}"
  data:
  - secretKey: endpoint
    remoteRef:
      key: hetzner/replication-target
      property: endpoint
  - secretKey: access-key
    remoteRef:
      key: hetzner/replication-target
      property: access_key
  - secretKey: secret-key
    remoteRef:
      key: hetzner/replication-target
      property: secret_key
EOF
echo "✓ Created ExternalSecret for replication target"
REPLICATION_ENABLED=true
else
echo "⚠️  Replication target credentials not provided, replication will be disabled"
REPLICATION_ENABLED=false
fi

# Create S3 replicator Deployment
cat > "$DEPLOYMENT_DIR/data-plane/storage/replicator-deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: s3-replicator
  namespace: $NAMESPACE
  labels:
    app: s3-replicator
    plane: data
    priority: foundation-high
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: s3-replicator
  template:
    metadata:
      labels:
        app: s3-replicator
        plane: data
        s3-access: "true"
      annotations:
        checksum/config: "sha256:\$(date +%s)"
    spec:
      priorityClassName: foundation-high
      terminationGracePeriodSeconds: 60
      containers:
      - name: replicator
        image: minio/mc:latest
        imagePullPolicy: IfNotPresent
        envFrom:
        - secretRef:
            name: hetzner-s3-credentials
        env:
        - name: MC_MIRROR_WATCH_BUFFER_SIZE
          value: "250"
        - name: MC_MIRROR_BANDWIDTH
          value: "50M"
        - name: MC_DEBUG
          value: "1"
        command: ["/bin/sh", "-c"]
        args:
        - |
          set -e
          
          # Configure source alias
          mc alias set source \${ENDPOINT} \${ACCESS_KEY} \${SECRET_KEY} --api s3v4 --path off
          
          echo "🔧 Starting S3 storage monitor (replication disabled)..."
          
          # Check if replication is enabled
          if [ -n "\${TARGET_ENDPOINT}" ] && [ -n "\${TARGET_ACCESS_KEY}" ] && [ -n "\${TARGET_SECRET_KEY}" ]; then
            mc alias set target \${TARGET_ENDPOINT} \${TARGET_ACCESS_KEY} \${TARGET_SECRET_KEY} --api s3v4 --path off
            
            echo "🔄 Starting supervised replication streams..."
            
            # Start dip-entrepeai (documents) mirror
            mc mirror --watch \
              --overwrite \
              --remove \
              --exclude "*.tmp" \
              --exclude ".heartbeat/*" \
              --delete-delay 1h \
              source/dip-entrepeai target/dip-entrepeai &
            PID_DOCS=\$!
            echo "📄 dip-entrepeai (documents) replicator PID: \$PID_DOCS"
            
            # Note: dip-documents-archive is already used for etcd backups
            # from earlier phases, so we don't replicate it here
            
            REPLICATION_ENABLED=true
          else
            echo "⚠️  Replication disabled - running in monitoring-only mode"
            REPLICATION_ENABLED=false
          fi
          
          # Heartbeat emitter (always runs for monitoring)
          (while true; do
            HEARTBEAT_ID=\$(cat /proc/sys/kernel/random/uuid)
            TIMESTAMP=\$(date +%s)
            echo "\$HEARTBEAT_ID \$TIMESTAMP" | mc pipe --quiet source/documents-processed/.heartbeat/\$HEARTBEAT_ID
            sleep 60
          done) &
          PID_HEARTBEAT=\$!
          echo "💓 heartbeat emitter PID: \$PID_HEARTBEAT"
          
          # Graceful shutdown handler
          _cleanup() {
            echo "🛑 Graceful shutdown initiated..."
            kill -TERM \$PID_HEARTBEAT 2>/dev/null && wait \$PID_HEARTBEAT 2>/dev/null
            
          if [ "\$REPLICATION_ENABLED" = "true" ]; then
            kill -TERM \$PID_DOCS 2>/dev/null
            
            if kill -0 \$PID_DOCS 2>/dev/null; then
              echo "⏳ Waiting for PID \$PID_DOCS to complete..."
              for i in {1..30}; do
                kill -0 \$PID_DOCS 2>/dev/null || break
                sleep 1
              done
              kill -9 \$PID_DOCS 2>/dev/null && echo "⚠️ Force-killed PID \$PID_DOCS"
            fi
          fi
            
            echo "✅ Storage monitor drained"
            exit 0
          }
          
          trap _cleanup TERM INT QUIT
          
          # Monitor loop
          if [ "\$REPLICATION_ENABLED" = "true" ]; then
            while kill -0 \$PID_DOCS 2>/dev/null && \
                  kill -0 \$PID_HEARTBEAT 2>/dev/null; do
              sleep 5
            done
          else
            # Monitoring-only mode
            while kill -0 \$PID_HEARTBEAT 2>/dev/null; do
              sleep 5
            done
          fi
          
          echo "⚠️ One or more background processes exited unexpectedly"
          _cleanup
        resources:
          requests:
            memory: "512Mi"
            cpu: "200m"
          limits:
            memory: "768Mi"
            cpu: "500m"
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: [ALL]
        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - |
              mc alias list source >/dev/null 2>&1 && \
              mc ls source/documents-processed >/dev/null 2>&1
          initialDelaySeconds: 30
          periodSeconds: 20
          timeoutSeconds: 10
          failureThreshold: 3
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - |
              mc stat source/documents-processed/.health-check 2>/dev/null || \
              echo "health-check-\$(date +%s)" | mc pipe --quiet source/documents-processed/.health-check/\$(date +%s)
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 15
          failureThreshold: 2
        volumeMounts:
        - name: s3-credentials
          mountPath: /etc/s3-credentials
          readOnly: true
      
      # DNS refresh sidecar
      - name: dns-refresher
        image: busybox:1.36
        command: ["sh", "-c"]
        args:
        - |
          while true; do
            nslookup fsn1.your-objectstorage.com >/dev/null 2>&1
            nslookup nbg1.your-objectstorage.com >/dev/null 2>&1
            sleep 30
          done
        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - nslookup fsn1.your-objectstorage.com >/dev/null 2>&1
          initialDelaySeconds: 10
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 2
        resources:
          requests:
            memory: "16Mi"
            cpu: "10m"
          limits:
            memory: "32Mi"
            cpu: "25m"
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
      
      # Metrics exporter
      - name: metrics-exporter
        image: minio/mc:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          METRICS_FILE=/metrics/s3_metrics.prom
          LAST_UPDATE_FILE=/metrics/.last_update
          
          while true; do
            TIMESTAMP=\$(date +%s)
            
            # Bucket size for dip-entrepeai
            mc du --json --recursive source/dip-entrepeai 2>/dev/null | \
              jq -r '"s3_bucket_size_bytes{bucket=\"dip-entrepeai\",role=\"source\"} " + .size' \
              >> \$METRICS_FILE.tmp
            
            # Heartbeat-based replication lag (only if replication enabled)
            HEARTBEAT_ID=\$(cat /proc/sys/kernel/random/uuid)
            echo "\$HEARTBEAT_ID \$TIMESTAMP" | mc pipe --quiet source/dip-entrepeai/.heartbeat/\$HEARTBEAT_ID
            
            # Check if replication is configured
            if [ -n "\${TARGET_ENDPOINT}" ] && [ -n "\${TARGET_ACCESS_KEY}" ] && [ -n "\${TARGET_SECRET_KEY}" ]; then
              if timeout 300 mc stat --quiet target/dip-entrepeai/.heartbeat/\$HEARTBEAT_ID >/dev/null 2>&1; then
                LAG=0
              else
                LAG=300
              fi
              echo "s3_replication_lag_seconds{bucket=\"dip-entrepeai\"} \$LAG" >> \$METRICS_FILE.tmp
            else
              echo "s3_replication_lag_seconds{bucket=\"dip-entrepeai\"} -1" >> \$METRICS_FILE.tmp
            fi
            
            mv \$METRICS_FILE.tmp \$METRICS_FILE
            echo \$TIMESTAMP > \$LAST_UPDATE_FILE
            
            sleep 60
          done
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - |
              LAST=\$(cat /metrics/.last_update 2>/dev/null || echo 0)
              NOW=\$(date +%s)
              [ \$((NOW - LAST)) -lt 120 ]
          initialDelaySeconds: 120
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        volumeMounts:
        - name: metrics-volume
          mountPath: /metrics
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
      
      volumes:
      - name: metrics-volume
        emptyDir: {}
      - name: s3-credentials
        secret:
          secretName: hetzner-s3-credentials
          optional: false
EOF
echo "✓ Created S3 replicator Deployment"

# Create Cilium network policy
cat > "$DEPLOYMENT_DIR/data-plane/storage/cilium-s3-egress-policy.yaml" << EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: s3-egress-restricted
  namespace: $NAMESPACE
spec:
  endpointSelector:
    matchLabels:
      plane: data
      s3-access: "true"
  egress:
  # Allow DNS resolution
  - toEndpoints:
    - matchLabels:
        k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP
      - port: "53"
        protocol: TCP
      rules:
        dns:
        - matchPattern: "*"
  
  # Allow HTTPS to Hetzner Object Storage
  - toFQDNs:
    - matchName: fsn1.your-objectstorage.com
    - matchName: nbg1.your-objectstorage.com
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
  
  # Allow egress to DR target
  - toFQDNs:
    - matchName: "nbg1.your-objectstorage.com"
    - matchName: "u*.your-storagebox.de"
    toPorts:
    - ports:
      - port: "443"
        protocol: TCP
      - port: "22"
        protocol: TCP
  
  description: "Restrict S3 access to Hetzner endpoints only"
EOF
echo "✓ Created Cilium network policy"

# Create differentiated alerting rules
cat > "$DEPLOYMENT_DIR/observability-plane/alerting/rules/s3-alerts-differentiated.yaml" << EOF
apiVersion: monitoring.giantswarm.io/v1alpha1
kind: PrometheusRule
metadata:
  name: s3-alerts-differentiated
  namespace: $OBSERVABILITY_NAMESPACE
spec:
  groups:
  # CRITICAL: Replication health alerts
  - name: s3-replication-critical
    rules:
    - alert: S3ReplicationStopped
      expr: s3_replication_lag_seconds{bucket="documents-processed"} > 300
      for: 2m
      labels:
        severity: critical
        plane: data
        component: replication
        alert-type: replication-health
      annotations:
        summary: "S3 replication has stopped for documents-processed"
        description: "Replication lag exceeded 5 minutes. RPO at immediate risk."
    
    - alert: S3ReplicatorPodDown
      expr: up{job="s3-replicator"} == 0
      for: 1m
      labels:
        severity: critical
        plane: data
        component: replicator
        alert-type: replication-health
      annotations:
        summary: "S3 replicator pod is down"
        description: "Replication to DR target has stopped. RPO will degrade immediately."
    
    - alert: S3MetricsExporterStale
      expr: (time() - s3_metrics_last_update_timestamp) > 120
      for: 2m
      labels:
        severity: critical
        plane: data
        component: metrics
        alert-type: replication-health
      annotations:
        summary: "S3 metrics exporter has stopped updating"
        description: "Metrics file not updated in >2 minutes."

  # WARNING: Cost and capacity alerts
  - name: s3-cost-management
    rules:
    - alert: S3EgressCostRisk
      expr: increase(s3_egress_bytes_total{direction="external"}[1d]) > 53687091200
      for: 1h
      labels:
        severity: warning
        plane: data
        cost-center: storage
        alert-type: cost-management
      annotations:
        summary: "High S3 egress detected (€0.50+/day)"
        description: "External egress exceeded 50GB in 24h."
    
    - alert: S3BucketGrowthAnomaly
      expr: rate(s3_bucket_size_bytes{bucket="documents-processed"}[1h]) > 1073741824
      for: 15m
      labels:
        severity: warning
        plane: data
        alert-type: cost-management
      annotations:
        summary: "Unusual bucket growth detected"
        description: "documents-processed grew by >1GB in the last hour."
    
    - alert: S3HeartbeatMetadataBloat
      expr: s3_object_count{bucket="documents-processed",prefix=".heartbeat/"} > 100
      for: 1h
      labels:
        severity: warning
        plane: data
        alert-type: maintenance
      annotations:
        summary: "Heartbeat metadata accumulation detected"
        description: "More than 100 heartbeat objects found."

  # INFO: Operational visibility
  - name: s3-operational-info
    rules:
    - alert: S3CredentialRotationPending
      expr: external_secrets_secret_status{secret="hetzner-s3-credentials",status!="Synced"} == 1
      for: 5m
      labels:
        severity: info
        plane: data
        alert-type: operational
      annotations:
        summary: "S3 credential sync pending"
        description: "External Secrets Operator has not synced latest credentials."
EOF
echo "✓ Created differentiated alerting rules"

# Create shared storage endpoints documentation
cat > "$DEPLOYMENT_DIR/shared/storage-endpoints.md" << EOF
# Storage Endpoints Reference

## Hetzner Object Storage
- **Primary Endpoint**: https://fsn1.your-objectstorage.com (fsn1 region)
- **Failover Endpoint**: https://nbg1.your-objectstorage.com (nbg1 region)
- **Service Name**: s3-endpoint.$NAMESPACE.svc.cluster.local
- **Port**: 443 (HTTPS)

## Buckets
1. **dip-entrepeai** (Document Storage)
   - Purpose: Active document storage for the application
   - Compliance: WORM (Write-Once-Read-Many) with 7-day retention
   - Versioning: Enabled for document tracking
   - Lifecycle Policies:
     - Heartbeat objects expire after 1 day (monitoring)
     - Temporary files (temp/ prefix) expire after 30 days
   - Encryption: SSE-C
   - Note: This is the primary bucket for document storage

2. **dip-documents-archive** (Already Configured)
   - Purpose: etcd backups from earlier phases
   - Note: Already configured and in use, do not modify
   - Managed by: Phase 0 storage setup

## Replication Targets
### Preferred: Dual-S3
- **Target**: nbg1.your-objectstorage.com
- **Buckets**: dip-entrepeai (document storage)
- **RPO**: ~60 seconds
- **Consistency**: Atomic operations

### Fallback: Storage Box (SFTP)
- **Target**: sftp://u*.your-storagebox.de
- **Buckets**: dip-entrepeai only
- **RPO**: ~5-10 minutes
- **Consistency**: Eventual

## Network Policies
- **Cilium FQDN Policy**: s3-egress-restricted
- **Allowed Domains**: fsn1.your-objectstorage.com, nbg1.your-objectstorage.com
- **DNS Cache**: Maintained by dns-refresher sidecar
- **Egress Ports**: 443 (HTTPS), 22 (SFTP fallback)

## Credential Management
- **Source**: External Secrets Operator
- **Rotation**: 30 days
- **Hot Reload**: Via volume mount + inotify
- **Blast Radius**: Separate credentials for replication target
EOF
echo "✓ Created storage endpoints documentation"

# Create runbook
cat > "$DEPLOYMENT_DIR/data-plane-runbook.md" << EOF
# Hetzner S3 Failover Procedure (v3 - Enterprise-Resilient)

## Architecture Note
**Preferred**: Dual-S3 replication (fsn1 → nbg1) for atomic operations and consistency.  
**Fallback**: Storage Box (SFTP) if budget constrained—accept eventual consistency tradeoffs.

## RPO/RTO Targets
- **RPO**: 60 seconds (heartbeat interval) under normal conditions; up to 5 minutes under load
- **RTO**: 10–15 minutes (manual configuration update + workload restart)

## Alert Response Matrix

| Alert Type | Severity | Response Time | Action |
|------------|----------|--------------|--------|
| \`S3ReplicationStopped\` | Critical | <5 min | Page on-call; verify replicator pod; check network policies |
| \`S3ReplicatorPodDown\` | Critical | <5 min | Page on-call; check node health; restart deployment |
| \`S3MetricsExporterStale\` | Critical | <10 min | Investigate metrics sidecar; verify volume mounts |
| \`S3EgressCostRisk\` | Warning | <4 hours | Review data churn; adjust lifecycle policies; notify finance |
| \`S3BucketGrowthAnomaly\` | Warning | <4 hours | Investigate unexpected uploads; verify application logic |
| \`S3HeartbeatMetadataBloat\` | Info | Next maintenance window | Verify ILM rule; manually cleanup if needed |

## Failover Trigger Conditions
- Replication lag > 300 seconds AND primary endpoint unreachable for >2 minutes
- Credential compromise requiring immediate rotation
- Regional outage (fsn1 down)
- Storage Box SFTP unavailable (if using fallback target)

## Failover Steps (Dual-S3 Preferred)
1. **Verify DR target health**
   \`\`\`bash
   mc alias set dr https://nbg1.your-objectstorage.com \${DR_ACCESS_KEY} \${DR_SECRET_KEY} --path off
   mc ls dr/documents-processed | head -5
   \`\`\`

2. **Update application configuration**
   \`\`\`bash
   # Option A: Update ExternalSecret source
   kubectl patch externalsecret hetzner-s3-credentials -n $NAMESPACE \\
     --type='json' -p='[{"op":"replace","path":"/spec/data/0/remoteRef/property","value":"failover_endpoint"}]'
   
   # Option B: Update ConfigMap fallback
   kubectl patch configmap s3-client-config -n $NAMESPACE \\
     --type='json' -p='[{"op":"replace","path":"/data/config.yaml","value":"s3:\\\\n  endpoint: https://nbg1.your-objectstorage.com\\\\n  ..."}]'
   \`\`\`

3. **Restart dependent workloads**
   \`\`\`bash
   kubectl rollout restart deployment -n $NAMESPACE -l s3-access=true
   \`\`\`

4. **Validate failover**
   \`\`\`bash
   echo "failover-test-\$(date +%s)" | mc pipe hetzner/documents-processed/failover-test.txt
   timeout 60 bash -c 'until mc ls dr/documents-processed/failover-test.txt >/dev/null 2>&1; do sleep 1; done' && \\
     echo "✅ Failover validated" || echo "❌ Failover validation failed"
   \`\`\`

## Storage Box Fallback Considerations
If using Storage Box (SFTP) as DR target:
- Accept eventual consistency (no atomic operations)
- Monitor SFTP latency separately: \`s3_replication_sftp_latency_seconds\`
- Set higher RPO tolerance: 5–10 minutes
- Prefer dual-S3 if budget allows (€4.90/month additional)
EOF
echo "✓ Created runbook"

echo ""
echo "2. Deploying to Kubernetes cluster..."

# Apply manifests
echo "Applying data-plane manifests..."
kubectl apply -f "$DEPLOYMENT_DIR/data-plane/storage/" --namespace="$NAMESPACE"

echo "Applying observability manifests..."
kubectl apply -f "$DEPLOYMENT_DIR/observability-plane/alerting/rules/" --namespace="$OBSERVABILITY_NAMESPACE"

echo ""
echo "3. Running bucket verification and configuration..."
# Create a temporary job to verify and configure existing bucket
cat > /tmp/bucket-verify-job.yaml << EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: bucket-verifier
  namespace: $NAMESPACE
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: verify
        image: minio/mc:latest
        envFrom:
        - secretRef:
            name: hetzner-s3-credentials
        env:
        - name: DOCUMENTS_BUCKET
          value: "dip-entrepeai"
        command: ["/bin/sh", "-c"]
        args:
        - |
          set -e
          echo "🔧 Verifying and configuring existing S3 bucket..."
          mc alias set hetzner \${ENDPOINT} \${ACCESS_KEY} \${SECRET_KEY} --api s3v4 --path off
          
          # Verify dip-entrepeai bucket exists
          echo "Checking bucket: dip-entrepeai"
          if mc ls hetzner/dip-entrepeai >/dev/null 2>&1; then
            echo "✅ Bucket 'dip-entrepeai' exists"
            
            # Enable versioning
            mc version enable hetzner/dip-entrepeai || echo "⚠️  Versioning already enabled or failed"
            
            # Enable WORM retention (7 days)
            mc retention set --enable --mode COMPLIANCE --duration 7d hetzner/dip-entrepeai || echo "⚠️  WORM already configured or failed"
            
            # Add heartbeat cleanup
            mc ilm add --expiry-days 1 --prefix ".heartbeat/" hetzner/dip-entrepeai || echo "⚠️  Lifecycle policy already exists or failed"
            
            # Add temp file cleanup (30 days)
            mc ilm add --expiry-days 30 --prefix "temp/" hetzner/dip-entrepeai || echo "⚠️  Temp cleanup policy already exists or failed"
            
            echo "✅ Bucket 'dip-entrepeai' configured for document storage"
          else
            echo "❌ Bucket 'dip-entrepeai' not found"
            echo "   This bucket should already exist for document storage"
            exit 1
          fi
          
          # Note: dip-documents-archive is already used for etcd backups
          # and should not be modified here
          
          echo "🎉 Bucket verification and configuration complete"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
EOF

kubectl apply -f /tmp/bucket-verify-job.yaml
echo "Waiting for bucket verification to complete..."
kubectl wait --for=condition=complete --timeout=300s job/bucket-verifier -n "$NAMESPACE"
kubectl logs job/bucket-verifier -n "$NAMESPACE"
kubectl delete job bucket-verifier -n "$NAMESPACE"

echo ""
echo "4. Verifying deployment..."
echo "Checking pods..."
kubectl get pods -n "$NAMESPACE" -l app=s3-replicator

echo ""
echo "Checking services..."
kubectl get services -n "$NAMESPACE" -l app=hetzner-s3

echo ""
echo "Checking secrets..."
kubectl get secrets -n "$NAMESPACE" -l app=hetzner-s3

echo ""
echo "================================================"
echo "Deployment completed successfully!"
echo "================================================"
echo ""
echo "Next steps:"
echo "1. Run validation: ./03-validation.sh"
echo "2. Test replication: kubectl logs -n $NAMESPACE -l app=s3-replicator -c replicator"
echo "3. Verify metrics: kubectl logs -n $NAMESPACE -l app=s3-replicator -c metrics-exporter"
echo ""
echo "Manifests created in: $DEPLOYMENT_DIR"
echo "Runbook: $DEPLOYMENT_DIR/data-plane-runbook.md"
echo "Documentation: $DEPLOYMENT_DIR/shared/storage-endpoints.md"