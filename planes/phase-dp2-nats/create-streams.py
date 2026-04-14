#!/usr/bin/env python3
import asyncio
import nats
import json

async def main():
    # Connect to NATS
    nc = await nats.connect("nats://nats:4222")
    
    # Create JetStream context
    js = nc.jetstream()
    
    # Stream configurations
    streams = [
        {
            "name": "DOCUMENTS",
            "subjects": ["data.doc.>"],
            "retention": "workqueue",
            "max_msgs": 100000,
            "max_bytes": 5368709120,  # 5GB
            "storage": "file",
            "num_replicas": 1,
            "discard": "old",
            "duplicate_window": 120,  # seconds
            "max_msg_size": 1048576,  # 1MB
            "max_age": 0,
            "max_msgs_per_subject": -1,
            "allow_rollup": False,
            "deny_delete": False,
            "deny_purge": False,
            "description": "Document processing stream with work queue retention"
        },
        {
            "name": "EXECUTION",
            "subjects": ["exec.task.>"],
            "retention": "interest",
            "max_age": 86400,  # 24 hours in seconds
            "storage": "file",
            "num_replicas": 1,
            "discard": "old",
            "duplicate_window": 60,  # seconds
            "max_msg_size": 524288,  # 512KB
            "max_bytes": 2147483648,  # 2GB
            "max_msgs": 50000,
            "max_msgs_per_subject": -1,
            "allow_rollup": False,
            "deny_delete": False,
            "deny_purge": False,
            "description": "Task execution stream with 24h retention, 2GB limit"
        },
        {
            "name": "OBSERVABILITY",
            "subjects": ["obs.metric.>"],
            "retention": "limits",
            "max_bytes": 1073741824,  # 1GB
            "storage": "file",
            "num_replicas": 1,
            "discard": "old",
            "duplicate_window": 30,  # seconds
            "max_msg_size": 131072,  # 128KB
            "max_age": 0,
            "max_msgs_per_subject": -1,
            "allow_rollup": False,
            "deny_delete": False,
            "deny_purge": False,
            "description": "Observability metrics stream with size limits"
        }
    ]
    
    # Create each stream
    for stream_config in streams:
        try:
            print(f"Creating stream: {stream_config['name']}")
            await js.add_stream(**stream_config)
            print(f"  ✓ Created {stream_config['name']}")
        except Exception as e:
            print(f"  ✗ Error creating {stream_config['name']}: {e}")
    
    # List streams to verify
    print("\nVerifying streams...")
    streams_info = await js.streams_info()
    for stream in streams_info:
        print(f"  - {stream.config.name}: {stream.state.messages} messages, {stream.state.bytes} bytes")
    
    await nc.close()

if __name__ == "__main__":
    asyncio.run(main())