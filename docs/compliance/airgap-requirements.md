# Airgap Requirements

A concise checklist for deploying `llm-onprem-deployment-kit` into a customer environment with no public egress. Share this directly with the customer's platform or compliance team.

## Definitions

- **Airgapped** - The cluster and its workloads have no route to the public internet. Outbound traffic is either dropped or confined to a customer-controlled allow-list.
- **Semi-airgapped / regulated** - A limited allow-list is permitted (e.g. NTP, customer-controlled log ingestion endpoint).

Both modes are supported. True airgapped mode requires all images and model weights to be staged in-environment before install.

## Prerequisite checklist

### Infrastructure

- [ ] A Kubernetes 1.28+ cluster in a private VNet.
- [ ] Private control plane (AKS `private_cluster_enabled`, EKS `endpoint_private_access`, GKE `enable_private_endpoint`).
- [ ] A private container registry (ACR / ECR / Artifact Registry or customer-run Harbor/Nexus/Artifactory).
- [ ] Cloud KMS with HSM-backed key for etcd encryption.
- [ ] 3+ worker nodes for system workloads.
- [ ] 1+ GPU nodes (A100 40GB or equivalent) for inference.
- [ ] StorageClass with encryption at rest for PVCs.
- [ ] Cloud-native log sink reachable from nodes (optional but recommended).

### Identity

- [ ] OIDC or SAML identity provider reachable from the cluster (for gateway auth).
- [ ] Cloud IAM groups mapped for operator access (not individual user accounts).
- [ ] HashiCorp Vault reachable from the cluster at a known internal endpoint.

### Connectivity

- [ ] Operator workstations can reach the API server via a bastion, IAP tunnel, or VPN.
- [ ] Workstations can push to the private container registry (via VPN or bastion push proxy).
- [ ] Cluster can reach the customer's internal Prometheus / Loki / Tempo endpoints.

### DNS

- [ ] Internal DNS resolves `privatelink.*.azure.com` / `*.compute.internal` / `*.googleapis.com` for the relevant cloud.
- [ ] The gateway hostname (e.g. `llm.internal.example.com`) is wired to the internal LB.

### Security and compliance

- [ ] Baseline CIS Kubernetes Benchmark reviewed and gaps acknowledged.
- [ ] Customer has an incident response contact matrix.
- [ ] Customer has approved the image inventory (see `scripts/airgap-mirror.sh --list`).
- [ ] Binary Authorization / image signature policy defined (GKE only; other clouds via admission controller).

## Image inventory

Run `scripts/airgap-mirror.sh --list` for the canonical, versioned list. As of v0.1.0 the list is:

- `docker.io/vllm/vllm-openai:v0.4.3`
- `docker.io/qdrant/qdrant:v1.9.2`
- `docker.io/traefik:v3.0.3`
- `docker.io/openpolicyagent/opa:0.65.0-envoy`
- `docker.io/otel/opentelemetry-collector-contrib:0.100.0`
- `docker.io/hashicorp/vault:1.16.2`
- `ghcr.io/external-secrets/external-secrets:v0.9.18`
- `quay.io/prometheus/prometheus:v2.52.0`
- `docker.io/grafana/loki:2.9.8`
- `docker.io/grafana/tempo:2.5.0`
- `nvcr.io/nvidia/k8s/dcgm-exporter:3.3.5-3.4.0-ubuntu22.04`

All images are pinned by tag. Immutable tags at the mirror registry are strongly recommended.

## Model weights

Model weights are staged on a dedicated PVC. Two supported patterns:

1. **Pre-baked ReadWriteMany PVC.** An operator copies the weights into a PVC once; vLLM pods mount it read-only. Recommended.
2. **InitContainer copy.** An initContainer pulls from a customer-hosted S3-compatible store (Azure Blob, S3, GCS, MinIO). Simpler but requires egress to the store.

The chart's `values-airgap.yaml` uses pattern 1 via `inference.modelVolume.enabled = true`.

## External services (if any)

If the customer permits a narrow allow-list:

| Host | Purpose | Protocol |
|------|---------|----------|
| IdP discovery endpoint | OIDC JWKS refresh | HTTPS |
| Customer Vault internal FQDN | ESO secret fetch | HTTPS (internal only) |
| Private registry | Image pull | HTTPS (internal only) |
| Observability sink | OTel/OTLP, Loki, Prometheus RW | HTTPS (internal only) |

If none of the above are reachable externally, the deployment is considered fully airgapped.

## Procurement questionnaire answers

These are the most common questions we are asked by customer procurement teams. Copy these answers into your response document.

> **Does the workload require public internet egress at runtime?**
> No. When installed from the airgap values file, no component initiates public connections.

> **How are secrets managed?**
> External Secrets Operator reads from the customer's HashiCorp Vault. Secrets are mounted as in-memory `tmpfs` volumes; they never land on disk and are not persisted to Git.

> **Who holds the encryption keys?**
> The customer. Terraform provisions CMEK via Azure Key Vault Premium / AWS KMS / GCP Cloud KMS. The vendor has no key material at any point.

> **What data leaves the customer environment?**
> Nothing. All logs, metrics, and traces are shipped only to customer-controlled endpoints specified in `values-airgap.yaml`.

> **How are container images validated?**
> Images are mirrored by an operator using `scripts/airgap-mirror.sh` to the customer's private registry. Tags are immutable at the registry level. Cosign signature verification can be enforced via Binary Authorization (GKE) or an admission controller (all clouds).

> **How are vulnerabilities handled?**
> The registry's native scanner (ECR / ACR Premium / Artifact Registry) scans each image on push. Findings are reviewed by the platform team per the customer's SLA.
