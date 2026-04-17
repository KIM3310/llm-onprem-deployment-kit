# ADR 003 - Vector Database Selection (Qdrant vs. Weaviate vs. Milvus vs. pgvector)

## Status

Accepted. Revisit if pgvector catches up on operational characteristics at high-cardinality workloads, or if a customer has a hard Postgres-only policy.

## Context

The vector database stores embeddings produced upstream by the RAG pipeline (see [`enterprise-llm-adoption-kit`](https://github.com/KIM3310/enterprise-llm-adoption-kit)) and serves approximate-nearest-neighbor queries for retrieval. Requirements:

- **Airgap-friendly.** Single-container deployment with no mandatory external services.
- **Self-hosted K8s deployment.** Must ship as a StatefulSet with PVCs and pod anti-affinity; high availability across 2-3 zones.
- **HTTP and gRPC client support.** Most RAG pipelines assume HTTP; gRPC desirable for latency-sensitive paths.
- **Operational simplicity.** Snapshot/backup API, clear upgrade path, bounded memory footprint.
- **Scale envelope.** Tens of millions of vectors at 1024-1536 dimensions, with sub-100ms p95 retrieval at 50 QPS.

Candidates evaluated:

- **Qdrant** (Rust, Apache 2.0, single-binary).
- **Weaviate** (Go, BSD-3, richer feature set including inline modules).
- **Milvus** (Go + C++, Apache 2.0, designed for billions of vectors).
- **pgvector** (Postgres extension, reusing an existing DB).

## Decision

We adopt **Qdrant** as the default vector database for `llm-stack`.

- Default image: `qdrant/qdrant:v1.9.2`.
- Chart topology: StatefulSet with 3 replicas, one PVC per replica (`accessModes: [ReadWriteOnce]`, default 200 GiB, customer StorageClass).
- Anti-affinity: preferred across `topology.kubernetes.io/zone`.
- Services: both HTTP (6333) and gRPC (6334) exposed via a ClusterIP Service and a headless Service for StatefulSet DNS.

## Consequences

### Positive

- **Operationally simple.** Single binary, one process, sane defaults. Helm deployment is short and obvious.
- **Airgap-clean.** No mandatory external services; telemetry can be disabled (`QDRANT__TELEMETRY_DISABLED=true`).
- **Fast.** Rust implementation with well-tuned HNSW; consistently competitive on public benchmarks at 1-10M vector scale.
- **HTTP + gRPC.** Both interfaces first-class; gRPC matters for low-latency consumers (~20-40% faster in our measurements at equal payload sizes).
- **Snapshot API.** `/collections/<c>/snapshots` endpoint is trivial to integrate with the DR runbook.
- **License.** Apache 2.0. No worry about a license change mid-lifecycle.
- **Small image.** approx 200 MB; mirrors quickly.

### Negative

- **No SQL-style ad-hoc query.** Customers with existing Postgres-centric teams sometimes want to reuse their data warehouse; pgvector fits that better.
- **Fewer built-in modules than Weaviate.** Weaviate bundles reranking, generative, and hybrid-search modules; Qdrant delegates those to the application layer. For customers who want a batteries-included vector DB, Weaviate is more appealing out-of-the-box.
- **Cluster mode maturity.** Qdrant cluster mode (distributed collections) is newer than Milvus's distributed architecture. For billion-scale workloads, Milvus is still the stronger choice.
- **Smaller operator community.** Less K8s-specific tooling (compared to, say, Postgres).

### Mitigations

- Chart keeps the config surface narrow and documented in `values.yaml`. A customer who wants to swap to Weaviate / Milvus / pgvector can override `vectorDb.engine` and reuse the StatefulSet+Service wiring (engine-agnostic).
- Disaster recovery runbook includes an explicit Qdrant snapshot restore procedure.
- PVC anti-affinity + PDB protects against zonal loss.
- Observability surfaces both HTTP and gRPC metrics via the OTel collector.

## Alternatives Considered

### Weaviate

Leading alternative, and in many ways the more polished product.

**Why not default:**

- Built-in modules (openai-generative, cohere-reranker, etc.) are powerful but assume outbound HTTP; this creates friction in airgap.
- Default deployment topology (single StatefulSet) is simple, but the v2 multi-tenant model and its shard rebalancer add operational surface area we did not want to teach on the first deploy.
- License is BSD-3, also fine; not a differentiator.

**When to prefer:** customer wants built-in hybrid search and reranking with minimal application code, and has an airgap-compatible module configuration.

To swap to Weaviate: override `vectorDb.engine=weaviate`, `vectorDb.image.repository=semitechnologies/weaviate`, `vectorDb.service.httpPort=8080`, and update the `ExternalSecret` references accordingly.

### Milvus

Most capable at scale; designed for billions of vectors.

**Why not default:**

- Multi-component architecture (proxy, query node, data node, index node, root coord, etc.) plus a dependency on etcd/MinIO/Pulsar. The component count is 10+ pods for a production cluster. For the target workload (tens of millions of vectors), that is significant over-engineering.
- Airgap mirror is a lot more work: 5-7 upstream images vs. 1 for Qdrant.
- Backup and DR tooling is improving but still less polished than Qdrant's snapshot flow.

**When to prefer:** customer anticipates >100M vectors or has existing Milvus operators deployed elsewhere.

### pgvector

Reuses existing Postgres infrastructure.

**Why not default:**

- Scales well below Qdrant/Weaviate/Milvus at equivalent hardware on HNSW benchmarks. IVFFlat/HNSW support in pgvector is improving, but the baseline query latency at 10M+ vectors is higher.
- Operational model is "add a column to Postgres". For customers who view Postgres as a monolithic system of record, adding a high-QPS retrieval workload is politically fraught.
- Postgres HA (Patroni, Crunchy, etc.) is its own rabbit hole and is typically customer-managed rather than part of this kit.

**When to prefer:** customer has a strict Postgres-only policy; vector counts are modest (low millions).

## Operational implications

- Chart defaults 3 replicas with anti-affinity on zone. Minimum for HA.
- PVC size defaults to 200 GiB; override via `vectorDb.persistence.size`.
- Snapshot procedure: see `docs/runbooks/disaster-recovery.md` Scenario B.
- Memory footprint at 10M 1536-d vectors with HNSW is approximately 70-90 GiB total across replicas; resources.request should be sized accordingly.

## Open questions / follow-ups

- Evaluate Qdrant cluster mode for >50M vectors once customer workloads warrant.
- Consider pluggable reranker integration (Cohere reranker, Jina reranker-v2) at the application layer rather than in the vector DB.
- Track pgvector's hnsw performance improvements quarterly; may flip the default for Postgres-heavy customers.
