# Data Plane

## Purpose
The **memory and nervous system**: persistent storage, event streaming, caching, and object storage. I/O bound, optimized for throughput. Contains the only stateful data in the foundation.

## Components

### 1. PostgreSQL (Primary Database)
- Version: 15 with RLS (Row-Level Security)
- HA: Primary + async read replica
- Connection pooling with pgBouncer
- Automated backups to S3

### 2. NATS JetStream (Event Streaming)
- 3-replica HA cluster
- JetStream persistence
- Backpressure monitoring
- Streams: DOCUMENTS, EXECUTION, OBSERVABILITY

### 3. Redis (Caching)
- Multi-role: sessions, rate limiting, semantic cache
- RDB snapshots only (no AOF)
- Memory protection with LRU eviction

### 4. Hetzner S3 (Object Storage)
- S3-compatible object storage
- WORM compliance for auditability
- Streaming replication to DR target
- Lifecycle management

## Deployment Sequence
1. **After** Phase 0: Budget Scaffolding
2. **Before** Control Plane (Temporal dependency)
3. **Before** Observability Plane (metrics dependency)

## Resource Budget
- Requests: 4.2Gi memory, 2.8 CPU
- Limits: 7.1Gi memory, 4.8 CPU
- Priority: foundation-critical for PostgreSQL, NATS
