#!/bin/bash
set -e

echo "Creating NATS JetStream streams..."

# Create stream configs
cat > /tmp/documents.json << 'EOF'
{
  "name": "DOCUMENTS",
  "subjects": ["data.doc.>"],
  "retention": "workqueue",
  "max_msgs": 100000,
  "max_bytes": 5368709120,
  "storage": "file",
  "num_replicas": 1,
  "discard": "old",
  "duplicate_window": 120000000000,
  "max_msg_size": 1048576,
  "max_age": 0,
  "max_msgs_per_subject": -1,
  "allow_rollup": false,
  "deny_delete": false,
  "deny_purge": false,
  "description": "Document processing stream with work queue retention"
}
EOF

cat > /tmp/execution.json << 'EOF'
{
  "name": "EXECUTION",
  "subjects": ["exec.task.>"],
  "retention": "interest",
  "max_age": 86400000000000,
  "storage": "file",
  "num_replicas": 1,
  "discard": "old",
  "duplicate_window": 60000000000,
  "max_msg_size": 524288,
  "max_bytes": 2147483648,
  "max_msgs": 50000,
  "max_msgs_per_subject": -1,
  "allow_rollup": false,
  "deny_delete": false,
  "deny_purge": false,
  "description": "Task execution stream with 24h retention, 2GB limit"
}
EOF

cat > /tmp/observability.json << 'EOF'
{
  "name": "OBSERVABILITY",
  "subjects": ["obs.metric.>"],
  "retention": "limits",
  "max_bytes": 1073741824,
  "storage": "file",
  "num_replicas": 1,
  "discard": "old",
  "duplicate_window": 30000000000,
  "max_msg_size": 131072,
  "max_age": 0,
  "max_msgs_per_subject": -1,
  "allow_rollup": false,
  "deny_delete": false,
  "deny_purge": false,
  "description": "Observability metrics stream with size limits"
}
EOF

# Create streams
echo "Creating DOCUMENTS stream..."
nats --server nats://nats:4222 stream add --config=/tmp/documents.json 2>&1 || echo "Note: Stream might already exist or there was an error"

echo "Creating EXECUTION stream..."
nats --server nats://nats:4222 stream add --config=/tmp/execution.json 2>&1 || echo "Note: Stream might already exist or there was an error"

echo "Creating OBSERVABILITY stream..."
nats --server nats://nats:4222 stream add --config=/tmp/observability.json 2>&1 || echo "Note: Stream might already exist or there was an error"

# List streams
echo ""
echo "Current streams:"
nats --server nats://nats:4222 stream list || echo "Could not list streams"

echo ""
echo "Done!"