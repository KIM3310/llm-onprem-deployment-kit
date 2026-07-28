# Security Model

This document describes the threat model, current chart controls, and customer acceptance responsibilities for `llm-onprem-deployment-kit`. It is a review aid, not a security certification or proof that controls operate in a deployed environment.

## Objective

Evaluate a vendor-supplied LLM workload inside a customer-controlled cloud environment while making the following goals testable:

- The customer retains control over their data and keys.
- Vendor access and workload egress are explicitly bounded and evidenced.
- Deployment tooling is reviewed before it runs with customer credentials.
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

1. **Public internet boundary.** Modules and annotations request private routing, but the customer must prove there is no public path and must control any IdP or approved egress.
2. **VNet boundary.** Operator access is via cloud-native IAM on a private control plane (bastion or IAP tunnel or equivalent). No public kubeconfig.
3. **Namespace boundary.** The baseline leaves NetworkPolicy off. The air-gap overlay enables default-deny plus explicit gateway, DNS, monitoring, and collector paths; enforcement depends on the cluster CNI.
4. **Pod security boundary.** `runAsNonRoot`, `readOnlyRootFilesystem`, dropped capabilities, `seccompProfile=RuntimeDefault`.
5. **Data-at-rest boundary.** Terraform exposes encryption options, but effective PVC and etcd encryption must be verified in the customer account.
6. **Image supply boundary.** The mirror script defines an inventory. Digest verification, signature policy, vulnerability acceptance, registry immutability, and model-weight provenance are customer acceptance items.

## Controls (by theme)

### Authentication

- Cluster access: Azure AD / IAM / Google IAM. Local accounts disabled on AKS.
- Inference: vLLM validates one bearer API key from a customer-owned Kubernetes Secret.
- End-user identity: not included. OIDC/SAML and user/session lifecycle belong in a customer gateway or application layer.
- Service-to-service: Kubernetes Workload Identity / IRSA for cloud API calls; ServiceAccount tokens for intra-cluster.

### Authorization

- Cluster RBAC: least-privilege Role and RoleBinding per component. Operator access via named cloud IAM groups, never user accounts.
- Request authorization: tenant policy, route/tool policy, quotas, and rate limits are not included.
- Vault: per-ServiceAccount policies; no root tokens in running workloads.

### Confidentiality

- TLS can terminate at Traefik when the customer supplies a TLS Secret.
- Traefik-to-vLLM traffic is plain HTTP inside the cluster; east-west mTLS is not included.
- Kubernetes Secrets may be persisted in etcd. Customer encryption-at-rest, RBAC, rotation, audit, and node controls determine confidentiality.
- The reverse proxy routes all paths to vLLM; customer policy must restrict externally reachable routes.

### Integrity

- Immutable image tags at the registry. The module sets `IMMUTABLE` (AWS), `retention_policy.enabled = true` (Azure), and `immutable_tags = true` (GCP).
- Container image signatures verified by cosign (out of scope for this repo; the helm chart exposes `imagePullSecrets` and the Binary Authorization policy on GKE enforces verification).
- Terraform plans are the change-management artifact; CI gates on `terraform validate`.

### Availability

- PodDisruptionBudget on inference and gateway.
- HPA on vLLM scales to maxReplicas=8 on GPU utilization.
- Qdrant is single-node and is not highly available. The chart rejects multiple replicas until distributed consensus is implemented.
- Terraform applies are idempotent; the runbook specifies rollback via `terraform apply -target=...` where needed.

### Auditability

- AKS / EKS / GKE control-plane logs to the cloud log sink.
- OTel collector config can scrape metrics and receive OTLP when components emit it.
- Per-request audit, redaction, immutable retention, alerts, and evidence of effective operation are not implemented by the chart.
- `collect-diag-bundle.sh` strips Secret values from collected manifests.

## Specific attack scenarios

### Malicious prompt tries to exfiltrate secrets

- vLLM receives only the inference API key configured by the chart; avoid injecting unrelated credentials.
- In the air-gap profile, network policy and cloud routing must be tested to prove egress denial. The baseline may need model-registry egress.
- `--disable-log-requests` reduces vLLM request logging, but customer proxies, applications, collectors, and support bundles need separate redaction review.

### Compromised vendor CI pushes a malicious image

- Air-gap images are intended to be pulled from the customer's private registry. Baseline values still reference public repositories.
- Mirroring is an explicit operator step (`airgap-mirror.sh`) triggered from a trusted workstation.
- Registry immutability and signature admission are customer controls and must be evidenced.

### Insider in a neighboring namespace scans the llm-stack pods

- With the air-gap overlay and a compatible CNI, NetworkPolicy rejects non-allowlisted traffic. The readiness sprint must test this rather than infer it from YAML.
- ServiceAccount RBAC prevents listing or executing into pods across namespace boundaries.

### Operator laptop compromised during deploy

- Terraform state is stored in the customer's remote backend (operator ships a backend config).
- Cluster credentials are short-lived (cloud-native OIDC).
- Operator credentials and generated evaluation secrets may be present on the workstation during setup. Use a customer-approved secret workflow and remove temporary material.

## Residual risks

- **Large-scale model denial of service.** An authenticated caller can consume GPU time until the HPA saturates. Mitigation: rate limiting at the gateway (planned follow-up).
- **Single shared API key.** The built-in API key cannot identify users or tenants and provides no per-user revocation or attribution.
- **Single-node vector state.** Qdrant failure is an outage and recovery depends on customer snapshots and a tested restore.
- **Static evidence gap.** Terraform/Helm validation does not prove routing, encryption, identity, audit, backup recovery, capacity, cost, or SLOs.
- **Prompt-injection-driven tool misuse.** The inference service does not directly execute tools; this kit does not ship the tool layer. Consumers (e.g. `stage-pilot`) are responsible for tool-call guardrails.
- **Vault seal key management.** Vault unseal is the customer's responsibility; this kit assumes Vault is already operational.

## Review cadence

- Security model reviewed at every major release.
- Compliance mappings updated whenever a control framework revision is published (SOC 2, ISO 27001).
- Threat model re-exercised after any SEV-1 incident (see [`docs/runbooks/incident-response.md`](./runbooks/incident-response.md)).
