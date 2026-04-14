#!/bin/bash
set -e

echo "Creating NATS JetStream streams directly in NATS pod..."

# Create streams using nats CLI if available in the pod
kubectl exec -n data-plane nats-0 -- sh -c '
  echo "Checking for nats CLI..."
  if command -v nats > /dev/null 2>&1; then
    echo "nats CLI found, creating streams..."
    
    # Create DOCUMENTS stream
    nats stream add DOCUMENTS \
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
    
    # Create EXECUTION stream
    nats stream add EXECUTION \
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
    
    # Create OBSERVABILITY stream
    nats stream add OBSERVABILITY \
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
    
    # Display stream info
    echo ""
    echo "Stream Information:"
    echo "==================="
    nats stream info DOCUMENTS
    echo ""
    nats stream info EXECUTION
    echo ""
    nats stream info OBSERVABILITY
    
  else
    echo "nats CLI not found in NATS pod"
    echo "Trying to create streams using HTTP API..."
    
    # Try using HTTP API
    if command -v curl > /dev/null 2>&1; then
      echo "curl found, attempting HTTP API..."
      # This would require the HTTP API to be accessible
      echo "HTTP API approach would go here"
    else
      echo "Neither nats CLI nor curl available in NATS pod"
      echo "Please install nats CLI in the NATS pod or use external management"
    fi
  fi
'

echo "Stream creation attempt completed!"