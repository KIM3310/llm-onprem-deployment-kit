# Security Model

This document describes the threat model, trust boundaries, and controls implemented in `llm-onprem-deployment-kit`. It is intended to survive a security review by a customer's CISO office.

## Objective

Operate a vendor-supplied LLM application inside a customer-controlled cloud environment such that:

- The customer retains control over their data and keys.
- The vendor cannot exfiltrate data via the running workload.
- The vendor cannot exfiltrate data via the deployment tooling.
- A compromise of any single component is bounded.

## Assets

| Asset | Sensitivity |
|-------|-------------|
| Inference prompts and completions | High (may contain PII, proprietary text) |
| Vector DB embeddings | High (derivable to source documents) |
| Model weights | Medium (licensed, not necessarily confidential) |
| Cluster credentials | Critical |
| KMS key material | Critical |
| Vault unseal keys | Critical |
| Container image digests | Low (but tampering must be detected) |

## Adversary model

### In scope

- **Network attacker** on the public internet, unable to reach the private VNet.
- **Compromised workstation** of a vendor engineer during deployment.
- **Malicious third-party image** mirrored from a public registry.
- **Insider in the customer's non-privileged tenant** attempting to read data from the llm-stack namespace.
- **Malicious prompt** attempting to exfiltrate secrets from the model environment.

### Out of scope

- Compromise of the cloud provider's control plane. The kit assumes the underlying IaaS is trustworthy.
- Physical access to the customer's data center.
- Compromise of the customer's Active Directory / IdP. Mitigations are downstream of IdP compromise.
- Side-channel attacks against GPU memory.

## Trust boundaries

1. **Public internet boundary.** Crossed only by TLS to the customer's IdP (OIDC discovery). No inbound public traffic to the workload.
2. **VNet boundary.** Operator access is via cloud-native IAM on a private control plane (bastion or IAP tunnel or equivalent). No public kubeconfig.
3. **Namespace boundary.** Default-deny NetworkPolicy; only explicit allows cross namespaces.
4. **Pod security boundary.** `runAsNonRoot`, `readOnlyRootFilesystem`, dropped capabilities, `seccompProfile=RuntimeDefault`.
5. **Data-at-rest boundary.** PVCs encrypted with cloud-managed keys; etcd encrypted with customer-managed key via KMS.
6. **Image supply boundary.** Only images mirrored by `airgap-mirror.sh` with validated digests; image tags are IMMUTABLE at the registry level.

## Controls (by theme)

### Authentication

- Cluster access: Azure AD / IAM / Google IAM. Local accounts disabled on AKS.
- Gateway: OIDC to customer IdP; bearer tokens validated by OPA against JWKS of the IdP.
- Service-to-service: Kubernetes Workload Identity / IRSA for cloud API calls; ServiceAccount tokens for intra-cluster.

### Authorization

- Cluster RBAC: least-privilege Role and RoleBinding per component. Operator access via named cloud IAM groups, never user accounts.
- Gateway: OPA policy bundle distributed as a ConfigMap; decision point at every request.
- Vault: per-ServiceAccount policies; no root tokens in running workloads.

### Confidentiality

- TLS in transit at the gateway; mTLS between Traefik and backend services (planned follow-up: `ingressRoute + middleware.tls`).
- Secrets mounted as `tmpfs` in-memory volumes; never persisted to node disk.
- OPA policy explicitly allows only `/v1/*` routes; admin endpoints are not exposed.

### Integrity

- Immutable image tags at the registry. The module sets `IMMUTABLE` (AWS), `retention_policy.enabled = true` (Azure), and `immutable_tags = true` (GCP).
- Container image signatures verified by cosign (out of scope for this repo; the helm chart exposes `imagePullSecrets` and the Binary Authorization policy on GKE enforces verification).
- Terraform plans are the change-management artifact; CI gates on `terraform validate`.

### Availability

- PodDisruptionBudget on inference (minAvailable=1) and on Qdrant (replicas-1) and gateway (minAvailable=1).
- HPA on vLLM scales to maxReplicas=8 on GPU utilization.
- Qdrant pod anti-affinity spreads replicas across zones.
- Terraform applies are idempotent; the runbook specifies rollback via `terraform apply -target=...` where needed.

### Auditability

- AKS / EKS / GKE control-plane logs to the cloud log sink.
- OTel collector ships request metadata (no content) to customer-controlled Loki.
- OPA decision logs captured and shipped to Loki.
- `collect-diag-bundle.sh` strips Secret values from collected manifests.

## Specific attack scenarios

### Malicious prompt tries to exfiltrate secrets

- Secrets are injected via ESO as environment variables or mounted files on a `tmpfs` volume. They are not accessible over the network.
- The vLLM process does not have network access to the internet (egress restricted by NetworkPolicy + userDefinedRouting / NAT / Cloud NAT). An attacker that convinces the model to encode a secret in its output still cannot ship it anywhere useful.
- Request content is not written to logs (`--disable-log-requests`) and OTel logs carry metadata only.

### Compromised vendor CI pushes a malicious image

- Images are pulled from the customer's private registry, not from `docker.io` at runtime.
- Mirroring is an explicit operator step (`airgap-mirror.sh`) triggered from a trusted workstation.
- Tags are immutable at the registry level.
- Binary Authorization (GKE) / image signature checks (out of scope) reject unsigned images.

### Insider in a neighboring namespace scans the llm-stack pods

- NetworkPolicy default-deny rejects all cross-namespace traffic except the allowlisted monitoring namespace.
- ServiceAccount RBAC prevents listing or executing into pods across namespace boundaries.

### Operator laptop compromised during deploy

- Terraform state is stored in the customer's remote backend (operator ships a backend config).
- Cluster credentials are short-lived (cloud-native OIDC).
- Secrets are never present on the operator's laptop; ESO reads them directly from Vault at pod start.

## Residual risks

- **Large-scale model denial of service.** An authenticated caller can consume GPU time until the HPA saturates. Mitigation: rate limiting at the gateway (planned follow-up).
- **Prompt-injection-driven tool misuse.** The inference service does not directly execute tools; this kit does not ship the tool layer. Consumers (e.g. `stage-pilot`) are responsible for tool-call guardrails.
- **Vault seal key management.** Vault unseal is the customer's responsibility; this kit assumes Vault is already operational.

## Review cadence

- Security model reviewed at every major release.
- Compliance mappings updated whenever a control framework revision is published (SOC 2, ISO 27001).
- Threat model re-exercised after any SEV-1 incident (see [`docs/runbooks/incident-response.md`](./runbooks/incident-response.md)).
