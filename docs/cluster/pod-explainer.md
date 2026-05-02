# Kubernetes Cluster Pod Reference

**Cluster:** 3-node K3s cluster (k3s-cp-1 control-plane, k3s-w-1, k3s-w-2 workers)  
**Generated:** 2026-05-02  
**Node IPs:** 10.0.0.2 (cp), 10.0.0.3 (w1), 10.0.0.4 (w2)  
**CNI:** Cilium | **OS:** Ubuntu 24.04 | **K3s:** v1.35.3+k3s1

---

## Namespace: `backup-system`

Backup and disaster recovery automation for cluster state and application data.

| # | Pod Name | Status | Node | IP | Description |
|---|----------|--------|------|----|-------------|
| 1 | `controller-lite-29628370-qfsvb` | Completed | k3s-cp-1 | 10.42.0.110 | **Kubernetes Job** — Triggered by CronJob every 5 minutes. Performs a lightweight controller reconciliation check for the backup system. Completes and records success/failure; if it fails, alerts fire. |
| 2 | `controller-lite-29628375-tpzts` | Completed | k3s-cp-1 | 10.42.0.111 | Same as above; subsequent CronJob invocation (next 5-minute interval). |
| 3 | `controller-lite-29628380-9dj49` | Completed | k3s-cp-1 | 10.42.0.112 | Same as above; latest invocation. |
| 4 | `ntp-checker-6wjvb` | Running | k3s-w-1 | 10.0.0.3 | **DaemonSet Pod** — Runs on every node. Checks that system time is synchronized via NTP. Essential for backup integrity (timestamps, incremental backups, consistency). |
| 5 | `ntp-checker-nrr82` | Running | k3s-cp-1 | 10.0.0.2 | Same; runs on control-plane node. |
| 6 | `ntp-checker-rqs47` | Running | k3s-w-2 | 10.0.0.4 | Same; runs on worker-2 node. |
| 7 | `restore-verify-daily-29628240-68fwv` | Error | k3s-cp-1 | 10.42.0.71 | **Kubernetes Job** — CronJob scheduled daily at 04:00. Attempts a dry-run restore of the latest backup to verify backup integrity. This invocation exited with an error, indicating the restore verification failed. |
| 8 | `restore-verify-daily-29628240-7bwx4` | Error | k3s-cp-1 | 10.42.0.73 | Same job; second retry pod for the same failed CronJob invocation. Both failed, which indicates a backup issue requiring investigation. |

---

## Namespace: `cnpg-system` (operator only)

CloudNative PostgreSQL operator — manages PostgreSQL clusters declaratively.

| # | Pod Name | Status | Node | IP | Description |
|---|----------|--------|------|----|-------------|
| 9 | `cnpg-cloudnative-pg-66f5b9cb7d-xh4dv` | Running | k3s-cp-1 | 10.42.0.77 | **Deployment Pod** — The CloudNativePG operator controller. Watches `Cluster`, `Backup`, and `ScheduledBackup` CRDs to manage PostgreSQL cluster lifecycle (reconciliation, failover, backup/restore, rolling updates). One replica is sufficient for operator leadership. |

---

## Namespace: `default`

Default Kubernetes namespace — application workloads and system utilities.

| # | Pod Name | Status | Node | IP | Description |
|---|----------|--------|------|----|-------------|
| 10 | `entrepeai-app-placeholder-6ccb566957-d56tv` | Running | k3s-w-2 | 10.42.2.10 | **Deployment Pod** — Placeholder application pod for "EntrepeAI" (likely a business-domain app). Single replica; serves as the initial deployment while the full application stack is being developed. |
| 11 | `health-test` | Completed | k3s-w-1 | 10.42.3.112 | **Kubernetes Job** — One-shot health-check job that validates cluster health. Completed successfully 4 days ago. |
| 12 | `v55` | Completed | k3s-w-2 | 10.42.2.125 | **Kubernetes Job** — Likely a version-check or migration job. Completed successfully. Naming suggests it validates or applies version 5.5 compatibility. |
| 13 | `vrl-check` | Completed | k3s-w-2 | 10.42.2.71 | **Kubernetes Job** — Vector Remap Language (VRL) validation job. Tests or validates VRL transformations used in the Vector observability pipeline. Completed 4 days ago. |

---

## Namespace: `dip-control-data`

DIP (Data Intelligence Platform) control-plane data services — the core data processing and storage layer.

| # | Pod Name | Status | Node | IP | Description |
|---|----------|--------|------|----|-------------|
| 16 | `audit-anchor-workflow-29628240-x7mh2` | Completed | k3s-cp-1 | 10.42.0.72 | **Kubernetes Job** — CronJob (every hour) that runs a Temporal workflow to cryptographically anchor audit logs to a public blockchain or similar append-only ledger. Provides tamper-evident audit trail. |
| 17 | `audit-anchor-workflow-29628300-xvhrf` | Completed | k3s-cp-1 | 10.42.0.88 | Same CronJob; next hourly invocation. |
| 18 | `audit-anchor-workflow-29628360-tx8f6` | Completed | k3s-cp-1 | 10.42.0.102 | Same CronJob; most recent hourly invocation. |
| 19 | `audit-pg-sink-c9ff8c88-9rvpx` | Running | k3s-w-2 | 10.42.2.91 | **Deployment Pod** — Streams audit events from NATS/Vectr into PostgreSQL. Acts as the persistence layer for the audit trail, ensuring all audit records are durably stored. |
| 20 | `dip-metadata-sync-64b5476497-m2m4b` | Running | k3s-cp-1 | 10.42.0.223 | **Deployment Pod** — Webhook-based metadata synchronization service. Keeps metadata consistent across DIP data plane components. 2 restarts (14h ago). |
| 21 | `minio-0` | Running | k3s-cp-1 | 10.42.0.105 | **StatefulSet Pod** — MinIO object storage instance (hot-cache tier). Provides S3-compatible object storage for DIP application data, audit artifacts, and temporary processing data. Single-replica statefulset. |
| 22 | `minio-batch-replicate-29628360-dkhmx` | Error | k3s-cp-1 | 10.42.0.104 | **Kubernetes Job** — CronJob (every 6 hours) that performs batch S3 replication from MinIO to remote storage. This invocation errored, indicating a replication failure that needs investigation. |
| 23 | `minio-batch-replicate-29628360-kt2kz` | Error | k3s-cp-1 | 10.42.0.106 | Same CronJob invocation; retry pod that also errored. Replication to external storage is currently failing. |
| 24 | `minio-hetzner-mirror-5854cfd6cb-d6cgt` | Running | k3s-cp-1 | 10.42.0.108 | **Deployment Pod** — Continuous mirroring service that replicates MinIO buckets to Hetzner Object Storage (external S3-compatible storage). 3 containers (sidecar pattern); provides geo-redundancy for object storage. |
| 25 | `minio-metadata-backup-29628120-4k9wq` | Error | k3s-cp-1 | 10.42.0.42 | **Kubernetes Job** — CronJob (daily at 02:00) that backs up MinIO bucket metadata (bucket policies, lifecycle rules, notifications). This invocation failed. |
| 26 | `minio-metadata-backup-29628120-zf7qt` | Error | k3s-cp-1 | 10.42.0.41 | Same CronJob invocation; retry pod that also failed. MinIO metadata backup is broken. |
| 27 | `nats-0` | Running | k3s-cp-1 | 10.42.0.129 | **StatefulSet Pod** — Stateful NATS message broker for the DIP data plane. Provides reliable, persistent messaging for inter-service communication within the data processing pipeline. Version: 2.12.6. |
| 28 | `nats-audit-8549b99685-hgdmv` | Running | k3s-w-2 | 10.42.2.42 | **Deployment Pod** — Dedicated NATS instance for audit event transport. Isolates audit message traffic from general-purpose data-plane messaging, ensuring audit events are never dropped or delayed by other traffic. |
| 29 | `postgres-6` | Running | k3s-w-1 | 10.42.3.27 | **StatefulSet Pod (CNPG)** — CloudNativePG-managed PostgreSQL 15 replica. Handles read-only queries, distributing read load away from the primary. Part of a 2-node PostgreSQL cluster managed by the CNPG operator. |
| 30 | `postgres-7` | Running | k3s-cp-1 | 10.42.0.90 | **StatefulSet Pod (CNPG)** — CloudNativePG-managed PostgreSQL 15 primary. Handles all write operations and serves as the source of truth for audit records, DIP metadata, and application state. |
| 31 | `redis-node-0` | Running | k3s-cp-1 | 10.42.0.70 | **StatefulSet Pod** — Redis node (shard 0) for in-memory caching and pub/sub messaging. Used by Temporal, auth services, and DIP data processing for high-speed data access. |
| 32 | `redis-node-1` | Running | k3s-w-1 | 10.42.3.137 | **StatefulSet Pod** — Redis node (shard 1). Second shard in a multi-node Redis cluster for horizontal scaling of cache capacity. |
| 33 | `retention-promoter-29628120-hhrdc` | Completed | k3s-cp-1 | 10.42.0.40 | **Kubernetes Job** — CronJob (daily at 02:00) that manages data lifecycle by promoting objects/data from hot to cold storage tiers based on retention policy. Completed successfully. |
| 34 | `temporal-frontend-56564d97b4-lqw2x` | Running | k3s-cp-1 | 10.42.0.170 | **Deployment Pod** — Temporal frontend service (gRPC + HTTP API gateway). Accepts all external workflow requests (start, signal, query, describe). Entry point for DIP workflow orchestration. 3 restarts (4d15h ago). Version 1.30.3. |
| 35 | `temporal-history-cf67476f-b5qft` | Running | k3s-cp-1 | 10.42.0.160 | **Deployment Pod** — Temporal history service. Stores and manages workflow execution history (event store). Each workflow's complete execution history is recorded here. Horizontally scalable. 3 restarts. |
| 36 | `temporal-matching-74bdb56cfd-vw474` | Running | k3s-w-1 | 10.42.3.56 | **Deployment Pod** — Temporal matching service. Manages task queues — matches pending tasks to available workflow/activity workers. Critical for task dispatch. 3 restarts. |
| 37 | `temporal-worker-646fd8ddc9-wlgs5` | Running | k3s-w-2 | 10.42.2.219 | **Deployment Pod** — Temporal worker service. Executes DIP workflow definitions and activity tasks. Contains the business logic for data-processing workflows. 3 restarts. |
| 38 | `vector-audit-5b997cf759-8mdc9` | Running | k3s-cp-1 | 10.42.0.9 | **Deployment Pod** — Vector (data pipeline) agent dedicated to audit log collection. Ingests, transforms (via VRL), and routes audit events to their sink destinations (NATS, PostgreSQL, object storage). |

---

## Namespace: `dip-control-infra`

DIP control-plane infrastructure — shared platform services (GitOps, auth, monitoring, networking, secrets).

| # | Pod Name | Status | Node | IP | Description |
|---|----------|--------|------|----|-------------|
| 39 | `argocd-application-controller-0` | Running | k3s-cp-1 | 10.42.0.241 | **StatefulSet Pod** — ArgoCD Application Controller. Continuously compares desired state (from Git repositories) against live cluster state and reconciles differences. The core reconciliation engine of GitOps. |
| 40 | `argocd-applicationset-controller-7c977b6d97-jlrg9` | Running | k3s-cp-1 | 10.42.0.225 | **Deployment Pod** — ArgoCD ApplicationSet Controller. Generates ArgoCD Applications from templates (ApplicationSet CRDs) based on generators like Git directories, SCM providers, clusters, or matrix combinations. Enables multi-cluster and multi-environment deployments. |
| 41 | `argocd-redis-6f8846445c-cjsnw` | Running | k3s-cp-1 | 10.42.0.228 | **Deployment Pod** — Redis cache for ArgoCD. Used for caching Git repository data, application state, and session information to reduce API server load and improve ArgoCD response times. |
| 42 | `argocd-repo-server-78f4c779c-68g7p` | Running | k3s-cp-1 | 10.42.0.226 | **Deployment Pod** — ArgoCD Repository Server. Clones Git repositories, caches their contents, and generates Kubernetes manifests (supports Helm, Kustomize, Jsonnet, etc.). Keeps repo credentials and serves manifest generation requests. |
| 43 | `argocd-server-78fff5cd6d-8wkfn` | Running | k3s-cp-1 | 10.42.0.236 | **Deployment Pod** — ArgoCD API Server. Serves the ArgoCD web UI, gRPC/REST API, and handles user authentication (SSO, OIDC, LDAP). Entry point for all user interactions with ArgoCD. |
| 44 | `audit-examiner-747fb459f6-qflgb` | Running | k3s-w-2 | 10.42.2.167 | **Deployment Pod** — Audit examination service. Queries and analyzes the audit trail stored in PostgreSQL/object storage. Provides API endpoints for audit log search, filtering, and export. Part of a 2-replica HA pair. |
| 45 | `audit-examiner-747fb459f6-r82bg` | Running | k3s-w-1 | 10.42.3.64 | Same deployment; second replica on a different node for HA. |
| 46 | `auth-service-89b945bbd-b4pw9` | Running | k3s-cp-1 | 10.42.0.203 | **Deployment Pod** — Authentication and authorization service (v4.2). Handles user login, JWT token issuance/validation, RBAC enforcement, and API key management. Exposes Prometheus metrics on :8080/metrics. Part of a 2-replica HA pair. |
| 47 | `auth-service-89b945bbd-t5bc2` | Running | k3s-w-1 | 10.42.3.163 | Same deployment; second replica. |
| 48 | `cert-manager-6cfb64df86-qf7hk` | Running | k3s-w-1 | 10.42.3.43 | **Deployment Pod** — Cert-Manager controller. Automates TLS certificate issuance and renewal from issuers (Let's Encrypt, internal CA, Venafi, etc.). Watches `Certificate` and `Issuer` CRDs. 3 restarts (4d15h ago). |
| 49 | `cert-manager-cainjector-798668947-d9fr7` | Running | k3s-w-1 | 10.42.3.46 | **Deployment Pod** — Cert-Manager CA Injector. Injects CA certificates (from `Issuer`/`ClusterIssuer` resources) into `MutatingWebhookConfiguration` and `ValidatingWebhookConfiguration` resources so that webhook servers trust the TLS connection. |
| 50 | `cert-manager-webhook-57d775bfd9-5dwxk` | Running | k3s-w-1 | 10.42.3.39 | **Deployment Pod** — Cert-Manager Admission Webhook. Validates `Certificate`, `Issuer`, and `ClusterIssuer` resources upon creation/update via admission webhooks. Prevents misconfigured certificate resources. |
| 51 | `e2e-all` | Completed | k3s-w-1 | 10.42.3.97 | **Kubernetes Job** — End-to-end integration test job. Runs the full E2E test suite against the infrastructure to validate all services are functioning correctly. Completed 3 days ago. |
| 52 | `echo-backend-74bc79db64-kgrvx` | Running | k3s-w-2 | 10.42.2.232 | **Deployment Pod** — Simple HTTP echo server used for network connectivity testing and ingress validation. Returns request headers/body for debugging. 3 restarts (4d15h ago). |
| 53 | `fluent-bit-fluent-bit-loki-5t88r` | Running | k3s-w-1 | 10.42.3.51 | **DaemonSet Pod** — Fluent Bit log collector (Loki output plugin). Runs on every node; tails container logs, adds Kubernetes metadata, and forwards to Loki. 3 restarts. |
| 54 | `fluent-bit-fluent-bit-loki-f87lr` | Running | k3s-w-2 | 10.42.2.234 | Same DaemonSet; runs on worker-2. |
| 55 | `fluent-bit-fluent-bit-loki-pm42w` | Running | k3s-cp-1 | 10.42.0.169 | Same DaemonSet; runs on control-plane node. |
| 56 | `grafana-9cb99d658-q6ztg` | Running | k3s-w-2 | 10.42.2.187 | **Deployment Pod** — Grafana dashboarding and visualization platform. 2 containers (Grafana + sidecar). Connects to Victoria Metrics (metrics), Loki (logs), and other data sources for observability dashboards. |
| 57 | `hcloud-snapshot-29627760-srnq4` | Completed | k3s-cp-1 | 10.42.0.192 | **Kubernetes Job** — CronJob (every 4 hours). Creates a server snapshot of the Hetzner Cloud VMs via the Hetzner API. Provides VM-level recovery point. |
| 58 | `hcloud-snapshot-29628000-gnx44` | Completed | k3s-cp-1 | 10.42.0.4 | Same CronJob; subsequent invocation. |
| 59 | `hcloud-snapshot-29628240-jxfjh` | Completed | k3s-cp-1 | 10.42.0.67 | Same CronJob; most recent invocation. |
| 60 | `hcloud-snapshot-backup-29627760-2bswb` | Completed | k3s-cp-1 | 10.42.0.193 | **Kubernetes Job** — CronJob (every 4 hours). Takes a Hetzner Cloud snapshot specifically labeled as a backup (distinct from regular snapshots for DR purposes). |
| 61 | `hcloud-snapshot-backup-29628000-mdcsh` | Completed | k3s-cp-1 | 10.42.0.7 | Same CronJob; subsequent invocation. |
| 62 | `hcloud-snapshot-backup-29628240-fg7xn` | Error | k3s-cp-1 | 10.42.0.68 | Same CronJob; this invocation errored (one of the retries). |
| 63 | `hcloud-snapshot-backup-29628240-jx6mk` | Completed | k3s-cp-1 | 10.42.0.74 | Same CronJob invocation; second retry pod completed successfully. |
| 64 | `kyverno-admission-controller-85878558-qh9ql` | Running | k3s-w-2 | 10.42.2.239 | **Deployment Pod** — Kyverno Admission Controller. Validates and mutates incoming Kubernetes resource requests against defined policies. Enforces security, compliance, and operational policies at admission time. |
| 65 | `kyverno-admission-controller-85878558-t7t65` | Running | k3s-w-1 | 10.42.3.45 | Same deployment; second replica for HA. |
| 66 | `kyverno-background-controller-778bffc669-88blv` | Running | k3s-w-2 | 10.42.2.230 | **Deployment Pod** — Kyverno Background Controller. Handles background scans for existing resources (not just incoming admission requests). Generates policy reports and handles periodic policy reconciliation. |
| 67 | `kyverno-cleanup-controller-7cf9b4d458-jkp6s` | Running | k3s-w-2 | 10.42.2.223 | **Deployment Pod** — Kyverno Cleanup Controller. Manages cleanup policies — automatically deletes old or non-compliant resources based on time-based or condition-based cleanup rules defined in `CleanupPolicy` CRDs. |
| 68 | `kyverno-reports-controller-6c666d96-8p25l` | Running | k3s-w-1 | 10.42.3.34 | **Deployment Pod** — Kyverno Reports Controller. Generates and manages `PolicyReport` and `ClusterPolicyReport` CRDs. Provides audit results showing which resources pass/fail each policy. |
| 69 | `loki-0` | Running | k3s-w-2 | 10.42.2.241 | **StatefulSet Pod** — Grafana Loki log aggregation system. 2 containers (Loki + sidecar). Stores compressed, indexed log data from Fluent Bit. Single-replica statefulset for log storage. |
| 70 | `loki-gateway-558dd84bf5-jl4tv` | Running | k3s-w-1 | 10.42.3.48 | **Deployment Pod** — Loki Gateway (nginx-based). Acts as a reverse proxy/load balancer for Loki, providing authentication, rate limiting, and multi-tenant request routing to the Loki backend. |
| 71 | `nats-stateless-74bb9d9889-bmgqc` | Running | k3s-cp-1 | 10.42.0.128 | **Deployment Pod** — Stateless NATS messaging for the control-plane infrastructure. Provides lightweight publish-subscribe and request-reply messaging without JetStream persistence. Cross-replica for HA. |
| 72 | `nats-stateless-74bb9d9889-htz92` | Running | k3s-cp-1 | 10.42.0.130 | Same deployment; second replica for high availability. |
| 73 | `node-exporter-585jv` | Running | k3s-w-1 | 10.0.0.3 | **DaemonSet Pod** — Prometheus Node Exporter. Runs on every node; exports hardware and OS metrics (CPU, memory, disk, network, filesystem) to Prometheus/Victoria Metrics. Collects node-level telemetry. |
| 74 | `node-exporter-95msl` | Running | k3s-w-2 | 10.0.0.4 | Same DaemonSet; runs on worker-2. |
| 75 | `node-exporter-z72lq` | Running | k3s-cp-1 | 10.0.0.2 | Same DaemonSet; runs on control-plane node. |
| 76 | `spire-agent-mcff2` | Running | k3s-cp-1 | 10.0.0.2 | **DaemonSet Pod** — SPIRE Agent (SPIFFE Runtime Environment). Runs on every node; attests node identity and workloads, issues SPIFFE Verifiable Identity Documents (SVIDs) for mTLS between services. Enforces workload identity. |
| 77 | `spire-agent-nwvsb` | Running | k3s-w-1 | 10.0.0.3 | Same DaemonSet; runs on worker-1. |
| 78 | `spire-agent-wdxs5` | Running | k3s-w-2 | 10.0.0.4 | Same DaemonSet; runs on worker-2. |
| 79 | `spire-server-0` | Running | k3s-w-1 | 10.42.3.60 | **StatefulSet Pod** — SPIRE Server. Acts as the Certificate Authority (CA) for the SPIFFE identity system. Issues and rotates SVID certificates, manages trust bundles, and handles node/workload attestation. Runs 2 containers (server + sidecar). |
| 80 | `ssh-installer-w1` | Completed | k3s-w-1 | 10.42.3.200 | **Kubernetes Job** — One-shot job that installs SSH keys on worker-1 for emergency administrative access. Completed successfully. |
| 81 | `ssh-installer-w2` | Completed | k3s-w-2 | 10.42.2.199 | Same; SSH key installation on worker-2. |
| 82 | `test-jwks-server-cb68df78b-vwvzh` | Running | k3s-w-1 | 10.42.3.47 | **Deployment Pod** — Mock JWKS (JSON Web Key Set) server for testing. Serves JWKS endpoints used by JWT validation tests. Validates that the auth service and JWT validator can correctly fetch and cache signing keys. |
| 83 | `velero-78b5d874d5-qsd5v` | Running | k3s-cp-1 | 10.42.0.216 | **Deployment Pod** — Velero backup and restore tool. Manages Kubernetes resource backups and VolumeSnapshot backups to object storage (S3-compatible). Handles scheduled backups, on-demand backups, and disaster recovery restores. |
| 84 | `vmsingle-victoria-metrics-single-server-0` | Running | k3s-cp-1 | 10.42.0.31 | **StatefulSet Pod** — VictoriaMetrics Single-Node server. The primary time-series database for metrics storage. Ingests Prometheus-format metrics, supports PromQL, and serves as the metrics backend for Grafana. Single-replica. |
| 85 | `vmoperator-victoria-metrics-operator-8455b44b77-qjgrb` | Running | k3s-w-1 | 10.42.3.53 | **Deployment Pod** — Victoria Metrics Operator. Manages Victoria Metrics stack components (`VMSingle`, `VMCluster`, `VMAlert`, `VMServiceScrape`) via CRDs. Creates and configures Victoria Metrics instances declaratively. |

---

## Namespace: `docintel-auth`

Document Intelligence authentication — JWT validation and caching.

| # | Pod Name | Status | Node | IP | Description |
|---|----------|--------|------|----|-------------|
| 86 | `jwt-validator-69fdf7fb7-24xwk` | Running | k3s-w-2 | 10.42.2.235 | **Deployment Pod** — JWT validation sidecar/service. Validates JWT tokens for the document intelligence application. Fetches JWKS from the auth service, caches public keys, and validates token signatures, expiry, and claims. |
| 87 | `jwt-validator-69fdf7fb7-lmtjg` | Running | k3s-cp-1 | 10.42.0.147 | Same deployment; second replica for HA. |
| 88 | `redis-69666c67f5-pjjbj` | Running | k3s-cp-1 | 10.42.0.146 | **Deployment Pod** — Redis cache for JWKS key material and JWT validation results. Reduces auth service load by caching validated tokens and public keys locally for the docintel-auth domain. |

---

## Namespace: `external-secrets`

External Secrets Operator — syncs secrets from external providers into Kubernetes.

| # | Pod Name | Status | Node | IP | Description |
|---|----------|--------|------|----|-------------|
| 89 | `external-secrets-679b89b4c8-pxhgx` | Running | k3s-w-1 | 10.42.3.54 | **Deployment Pod** — External Secrets Operator controller. Watches `ExternalSecret` CRDs and syncs secrets from external providers (AWS Secrets Manager, HashiCorp Vault, Azure Key Vault, etc.) into native Kubernetes Secrets. |
| 90 | `external-secrets-cert-controller-65c74dc756-rzhwv` | Running | k3s-cp-1 | 10.42.0.158 | **Deployment Pod** — External Secrets cert-controller. Manages TLS certificate lifecycle for the External Secrets webhook. 16 restarts (potentially related to cert rotation). |
| 91 | `external-secrets-webhook-6c9d87f974-mh2m2` | Running | k3s-cp-1 | 10.42.0.165 | **Deployment Pod** — External Secrets admission webhook. Validates `ExternalSecret`, `ClusterSecretStore`, and `SecretStore` resources. Enforces schema correctness and provider configuration validation. 16 restarts (high). |

---

## Namespace: `kube-state-metrics`

Kubernetes state metrics exporter.

| # | Pod Name | Status | Node | IP | Description |
|---|----------|--------|------|----|-------------|
| 92 | `kube-state-metrics-5b8b9f5f8f-g6q94` | Running | k3s-w-2 | 10.42.2.227 | **Deployment Pod** — kube-state-metrics. Generates Prometheus metrics about the state of Kubernetes API objects (deployments, pods, nodes, etc.). Does NOT collect individual pod resource usage (that's metrics-server); instead reports object counts, statuses, and labels. |

---

## Namespace: `kube-system`

Core Kubernetes system components — networking, storage, DNS, scheduling, service mesh.

| # | Pod Name | Status | Node | IP | Description |
|---|----------|--------|------|----|-------------|
| 93 | `cilium-dlmqv` | Running | k3s-w-2 | 10.0.0.4 | **DaemonSet Pod** — Cilium agent (networking, security, observability). Runs on every node; manages eBPF programs for pod networking, network policies, load balancing, and encryption. Core CNI dataplane component. |
| 94 | `cilium-envoy-fdpxz` | Running | k3s-w-1 | 10.0.0.3 | **DaemonSet Pod** — Cilium Envoy proxy sidecar. Runs on every node; provides Envoy-based L7 proxy functionality for Cilium (HTTP/HTTPS policy enforcement, L7 load balancing, ingress support). |
| 95 | `cilium-envoy-qj6dz` | Running | k3s-cp-1 | 10.0.0.2 | Same DaemonSet; runs on control-plane node. |
| 96 | `cilium-envoy-s6gh2` | Running | k3s-w-2 | 10.0.0.4 | Same DaemonSet; runs on worker-2. |
| 97 | `cilium-g9cr9` | Running | k3s-cp-1 | 10.0.0.2 | **DaemonSet Pod** — Cilium agent (same as #93) on the control-plane node. |
| 98 | `cilium-operator-5f87b6546f-bc4qw` | Running | k3s-cp-1 | 10.0.0.2 | **Deployment Pod** — Cilium Operator. Handles cluster-wide Cilium tasks that should run once (not per-node): IPAM (IP allocation management), service synchronization, endpoint garbage collection, and CRD management. |
| 99 | `cilium-sdgw4` | Running | k3s-w-1 | 10.0.0.3 | **DaemonSet Pod** — Cilium agent on worker-1 (same as #93). |
| 100 | `coredns-f76775cf9-65b5c` | Running | k3s-w-1 | 10.42.3.103 | **Deployment Pod** — CoreDNS. Provides DNS resolution for cluster services and pods. Resolves Kubernetes Service names (e.g., `service.namespace.svc.cluster.local`) to ClusterIPs. Just restarted (21s ago). |
| 101 | `hcloud-cloud-controller-manager-7d5b6cb44-jss6t` | Running | k3s-cp-1 | 10.42.0.174 | **Deployment Pod** — Hetzner Cloud Controller Manager. Integrates K3s with Hetzner Cloud APIs. Manages Load Balancers (`Services` of type `LoadBalancer`), node lifecycle (removing nodes deleted from Hetzner), and routes. |
| 102 | `hcloud-csi-controller-7ffcc86b66-7wfbc` | Running | k3s-w-2 | 10.42.2.228 | **Deployment Pod** — Hetzner CSI Controller. Container Storage Interface controller; manages persistent volume lifecycle (create, attach, detach, delete) on Hetzner Cloud volumes. 5 containers (CSI attacher, provisioner, resizer, snapshotter, driver). |
| 103 | `hcloud-csi-node-4wl7k` | Running | k3s-w-2 | 10.42.2.224 | **DaemonSet Pod** — Hetzner CSI Node plugin. Runs on every node; handles volume attachment/mounting to pods on its node. 3 containers (node-driver-registrar, CSI node driver, liveness probe). |
| 104 | `hcloud-csi-node-jj5r9` | Running | k3s-cp-1 | 10.42.0.161 | Same DaemonSet; runs on control-plane node. |
| 105 | `hcloud-csi-node-r7dml` | Running | k3s-w-1 | 10.42.3.40 | Same DaemonSet; runs on worker-1. |
| 106 | `hubble-relay-68ddcf7f55-7j2g2` | Running | k3s-cp-1 | 10.42.0.142 | **Deployment Pod** — Hubble Relay. Aggregates network flow data from all Cilium/Hubble agents across the cluster. Provides a cluster-wide API to query network flows, service maps, and connectivity health. |
| 107 | `hubble-ui-67d8bff4c4-ww5z5` | Running | k3s-cp-1 | 10.42.0.157 | **Deployment Pod** — Hubble UI. Web UI that visualizes the Cilium/Hubble service map, network flows, and connectivity. 2 containers (UI frontend + backend API). 66 restarts (high — may need investigation). |
| 108 | `local-path-provisioner-5c4dc5d66d-69fdb` | Running | k3s-cp-1 | 10.42.0.149 | **Deployment Pod** — K3s built-in local path provisioner. Dynamically provisions `hostPath`-based PersistentVolumes using local disk paths (default: `/var/lib/rancher/k3s/storage`). Default StorageClass for clusters without a cloud CSI. |
| 109 | `metrics-server-786d997795-qd555` | Running | k3s-cp-1 | 10.42.0.153 | **Deployment Pod** — Kubernetes Metrics Server. Collects resource usage metrics (CPU/memory) from the kubelet on each node and exposes them via the Metrics API. Required for `kubectl top` and Horizontal Pod Autoscaler (HPA). |
| 110 | `node-debugger-k3s-w-1-hv5qn` | Completed | k3s-w-1 | 10.0.0.3 | **Kubernetes Job** — One-shot debug container that ran on worker-1 for troubleshooting. Gave ephemeral access to the node filesystem for diagnostics. |
| 111 | `node-debugger-k3s-w-1-phntj` | Completed | k3s-w-1 | 10.0.0.3 | Same; another debug session on worker-1. |
| 112 | `node-debugger-k3s-w-2-ffgth` | Completed | k3s-w-2 | 10.0.0.4 | Debug container on worker-2. |
| 113 | `node-debugger-k3s-w-2-w9647` | Completed | k3s-w-2 | 10.0.0.4 | Another debug session on worker-2. |
| 114 | `sealed-secrets-594b7c765c-xjwkb` | Running | k3s-cp-1 | 10.42.0.144 | **Deployment Pod** — Sealed Secrets controller. Encrypts Kubernetes Secrets into `SealedSecret` CRDs that can be safely stored in public Git repositories. The controller is the only entity that can decrypt them back into native Secrets. |
| 115 | `snapshot-controller-c4f4579c4-hdknn` | Running | k3s-cp-1 | 10.42.0.75 | **Deployment Pod** — Kubernetes CSI Snapshot Controller. Watches `VolumeSnapshot` and `VolumeSnapshotContent` CRDs to manage the lifecycle of volume snapshots. Coordinates with CSI drivers for snapshot creation/deletion. |
| 116 | `snapshot-controller-c4f4579c4-jq8vq` | Running | k3s-w-1 | 10.42.3.71 | Same deployment; second replica on worker-1 for HA. |
| 117 | `svclb-traefik-6a3f3c49-4gkzx` | Running | k3s-w-2 | 10.42.2.145 | **DaemonSet Pod** — Service Load Balancer for Traefik. K3s creates this as part of a `Service` of type `LoadBalancer`. 3 containers: FRR (routing), and likely proxy/health-check containers. Routes external traffic to Traefik ingress. |
| 118 | `svclb-traefik-6a3f3c49-f9zc2` | Running | k3s-cp-1 | 10.42.0.175 | Same DaemonSet; runs on control-plane node. |
| 119 | `svclb-traefik-6a3f3c49-s4lhw` | Running | k3s-w-1 | 10.42.3.177 | Same DaemonSet; runs on worker-1. |
| 120 | `vpa-crds-admission-controller-6bd69c4f9-fbjm8` | Running | k3s-w-1 | 10.42.3.52 | **Deployment Pod** — Vertical Pod Autoscaler Admission Controller. Mutates pod resource requests (CPU/memory) at admission time based on VPA recommendations. Intercepts pod creation to apply optimized resource limits. |
| 121 | `vpa-crds-recommender-67584fcf68-nbx82` | Running | k3s-w-2 | 10.42.2.222 | **Deployment Pod** — Vertical Pod Autoscaler Recommender. Analyzes historical and current resource usage metrics, then computes recommended CPU/memory requests for pods. Stores recommendations in `VerticalPodAutoscaler` status. |
| 122 | `vpa-crds-updater-649d55d796-fmv52` | Running | k3s-w-1 | 10.42.3.38 | **Deployment Pod** — Vertical Pod Autoscaler Updater. Evicts pods that are not using their recommended resource amounts, triggering recreation with updated resource requests. Works with the recommender to right-size pods. |

---

## Namespace: `system-upgrade`

K3s system upgrade controller.

| # | Pod Name | Status | Node | IP | Description |
|---|----------|--------|------|----|-------------|
| 123 | `system-upgrade-controller-5665d65766-8vdws` | Running | k3s-cp-1 | 10.42.0.162 | **Deployment Pod** — K3s System Upgrade Controller. Watches `Plan` CRDs to orchestrate rolling upgrades of K3s across all nodes. Manages upgrade order (control-plane first, then workers), cordon/drain logic, and rollback on failure. |

---

## Namespace: `traefik`

Traefik ingress controller — edge routing and reverse proxy.

| # | Pod Name | Status | Node | IP | Description |
|---|----------|--------|------|----|-------------|
| 124 | `traefik-79f7bb5bff-8c5bf` | Running | k3s-w-2 | 10.42.2.161 | **Deployment Pod** — Traefik ingress controller. Routes external HTTP/HTTPS traffic to internal services based on `Ingress` and `IngressRoute` (CRD) definitions. Handles TLS termination, middleware (rate limiting, auth), and service discovery. |
| 125 | `traefik-79f7bb5bff-g7pgp` | Running | k3s-w-2 | 10.42.2.162 | Same deployment; second replica for HA. Both replicas are on k3s-w-2. |

---

## Summary Statistics

| Metric | Count |
|--------|-------|
| **Total Pods** | 123 |
| **Running** | 93 |
| **Completed** | 23 |
| **Error** | 7 |
| **Namespaces** | 10 actively used |

### Pods Currently in Error State (Requiring Investigation)

| # | Namespace | Pod | Last Error Time |
|---|-----------|-----|-----------------|
| 7 | backup-system | `restore-verify-daily-29628240-68fwv` | 141m ago |
| 8 | backup-system | `restore-verify-daily-29628240-7bwx4` | 141m ago |
| 22 | dip-control-data | `minio-batch-replicate-29628360-dkhmx` | 21m ago |
| 23 | dip-control-data | `minio-batch-replicate-29628360-kt2kz` | 21m ago |
| 25 | dip-control-data | `minio-metadata-backup-29628120-4k9wq` | 4h21m ago |
| 26 | dip-control-data | `minio-metadata-backup-29628120-zf7qt` | 4h21m ago |
| 62 | dip-control-infra | `hcloud-snapshot-backup-29628240-fg7xn` | 141m ago |

### Pods with Elevated Restart Counts (5+ restarts)

| Namespace | Pod | Restarts | Age |
|-----------|-----|----------|-----|
| kube-system | `hubble-ui-67d8bff4c4-ww5z5` | 66 | 23d |
| kube-system | `hcloud-csi-controller-7ffcc86b66-7wfbc` | 48 | 6d18h |
| kube-system | `metrics-server-786d997795-qd555` | 39 | 23d |
| kube-system | `local-path-provisioner-5c4dc5d66d-69fdb` | 20 | 23d |
| external-secrets | `external-secrets-webhook-6c9d87f974-mh2m2` | 16 | 20d |
| external-secrets | `external-secrets-cert-controller-65c74dc756-rzhwv` | 16 | 20d |
