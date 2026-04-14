#!/bin/bash
set -e

echo "Creating NATS JetStream streams using server API..."

# Get NATS pod IP
NATS_POD_IP=$(kubectl get pod -n data-plane nats-0 -o jsonpath='{.status.podIP}')
echo "NATS pod IP: $NATS_POD_IP"

# Create streams using NATS server HTTP API
create_stream() {
  local stream_name=$1
  local config=$2
  
  echo "Creating $stream_name stream..."
  
  # Use kubectl exec to run nats CLI inside the container (if available)
  # or use curl to call the NATS HTTP API
  kubectl exec -n data-plane nats-0 -- sh -c "
    if command -v nats > /dev/null 2>&1; then
      echo 'Using nats CLI...'
      nats stream add $stream_name $config
    else
      echo 'nats CLI not found, using server API...'
      # Try to create stream using server's internal tools
      echo 'Stream creation requires nats CLI or admin API access'
    fi
  "
}

# Try to install nats CLI in the nats-box pod and create streams
echo "Installing nats CLI in nats-box pod..."
kubectl exec -n data-plane deployment/nats-box -- apk add --no-cache curl jq > /dev/null 2>&1 || true

echo "Downloading nats CLI..."
kubectl exec -n data-plane deployment/nats-box -- sh -c "
  wget -q https://github.com/nats-io/natscli/releases/download/v0.1.2/nats-0.1.2-linux-amd64.zip -O /tmp/nats.zip &&
  unzip -o /tmp/nats.zip -d /tmp/ &&
  mv /tmp/nats-0.1.2-linux-amd64/nats /usr/local/bin/ &&
  chmod +x /usr/local/bin/nats
" > /dev/null 2>&1 || echo "nats CLI installation may have failed, continuing..."

echo "Creating streams from nats-box pod..."
kubectl exec -n data-plane deployment/nats-box -- sh -c '
  echo "Waiting for NATS server to be ready..."
  until nats --server nats://nats:4222 server info 2>/dev/null; do
    echo "Waiting for NATS server..."
    sleep 2
  done
  
  echo "Creating DOCUMENTS stream..."
  nats --server nats://nats:4222 stream add DOCUMENTS \
    --subjects "data.doc.>" \
    --retention workqueue \
    --max-msgs 100000 \
    --max-bytes 5GB \
    --storage file \
    --replicas 1 \
    --discard old \
    --dupe-window 2m \
    --max-msg-size 1MB \
    --max-age 0 \
    --max-msgs-per-subject -1 \
    --no-allow-rollup \
    --no-deny-delete \
    --no-deny-purge \
    --description "Document processing stream with work queue retention"
  
  echo "Creating EXECUTION stream..."
  nats --server nats://nats:4222 stream add EXECUTION \
    --subjects "exec.task.>" \
    --retention interest \
    --max-age 24h \
    --storage file \
    --replicas 1 \
    --discard old \
    --dupe-window 1m \
    --max-msg-size 512KB \
    --max-bytes 2GB \
    --max-msgs 50000 \
    --max-msgs-per-subject -1 \
    --no-allow-rollup \
    --no-deny-delete \
    --no-deny-purge \
    --description "Task execution stream with 24h retention, 2GB limit"
  
  echo "Creating OBSERVABILITY stream..."
  nats --server nats://nats:4222 stream add OBSERVABILITY \
    --subjects "obs.metric.>" \
    --retention limits \
    --max-bytes 1GB \
    --storage file \
    --replicas 1 \
    --discard old \
    --dupe-window 30s \
    --max-msg-size 128KB \
    --max-age 0 \
    --max-msgs-per-subject -1 \
    --no-allow-rollup \
    --no-deny-delete \
    --no-deny-purge \
    --description "Observability metrics stream with size limits"
  
  echo "All streams created successfully!"
  
  echo ""
  echo "Stream Information:"
  echo "==================="
  nats --server nats://nats:4222 stream info DOCUMENTS
  echo ""
  nats --server nats://nats:4222 stream info EXECUTION
  echo ""
  nats --server nats://nats:4222 stream info OBSERVABILITY
'

echo "Stream creation completed!"