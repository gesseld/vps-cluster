# Phase 2: Data Plane

**Deployment Sequence:** After Phase 1 (Shared Foundations), before Phase 3 (Control Plane)

## Purpose
The **memory and nervous system**: persistent storage, event streaming, caching, and object storage. I/O bound, optimized for throughput. Contains the only stateful data in the foundation.

## Components
1. **PostgreSQL**: Primary + async read replica with RLS, connection pooling
2. **NATS JetStream**: 3-replica HA cluster with backpressure controls
3. **Temporal Server**: 2-replica HA workflow engine (corrected: in Data Plane)
4. **MinIO**: S3-compatible storage with lifecycle policies and replication
5. **Redis**: Cache tier with RDB-only snapshots and memory protection

## Deployment Order
1. PostgreSQL (database)
2. NATS (messaging)
3. Redis (caching)
4. MinIO (storage)
5. Temporal (workflow engine)

## Validation
```bash
./scripts/validate-phase-gates.sh 2
```

## Important Notes
- **Temporal in Data Plane**: Corrected from architectural specification (was incorrectly in Control Plane)
- **Topology Awareness**: PostgreSQL and MinIO scheduled to `node-role=storage-heavy` nodes
- **Resource Budget**: 4.2GB RAM request, 7.1GB RAM limit for Data Plane
