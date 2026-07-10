# ADR 005 - Secrets Management (External Secrets Operator + HashiCorp Vault)

## Status

Accepted.

## Context

Production LLM deployments have two classes of secrets:

1. **Platform secrets.** Registry pull tokens, TLS certificates, OPA bundle signing keys, Vault unseal keys. Managed by the platform team; cadence: quarterly or on incident.
2. **Application secrets.** JWT signing keys for the gateway, model registry API keys, Qdrant API keys (if enabled), observability endpoint tokens. Managed by the app team; cadence: monthly or on rotation.

Requirements:

- **No secrets in Git.** Values files, Helm charts, and Terraform state must never contain secret material.
- **Works across three clouds.** Same tooling, same workflow; cloud-specific secret managers are implementation detail.
- **Rotatable without redeploy.** Rotation must not require a helm upgrade; a Deployment restart is acceptable.
- **Auditable.** Every secret read from the source of truth must be logged.
- **Airgap-compatible.** No mandatory phone-home; tooling image must be mirrorable.
- **Kubernetes-native consumption.** Workloads mount Kubernetes Secrets as files or env vars.

Candidate patterns:

- **A1** - External Secrets Operator (ESO) reading from HashiCorp Vault.
- **A2** - ESO reading directly from cloud-native secret stores (Key Vault / Secrets Manager / Secret Manager).
- **A3** - Vault Agent Injector sidecar pattern.
- **A4** - SealedSecrets (Bitnami) - encrypted secrets in Git.
- **A5** - Helm values with Sops-encrypted layers (sops + age + helm-secrets).

## Decision

We adopt **ESO + HashiCorp Vault (A1)** as the default secrets management stack.

- The chart renders `ExternalSecret` resources for each secret the application consumes.
- `ClusterSecretStore` is expected to be pre-created by the operator, pointed at the customer's Vault, with Kubernetes auth (per-namespace `role`).
- Vault is assumed to be customer-deployed and operated; the chart does not install Vault.
- Vault's storage backend is sealed by the cloud KMS (`auto-unseal`), which is provisioned by the Terraform modules.

The values file's `externalSecrets.secrets[]` array enumerates each secret by name and mapping. Adding a new secret is a values edit + git PR.

## Consequences

### Positive

- **Single source of truth.** All secrets live in Vault. One place to audit, rotate, and revoke.
- **Portable.** Vault + ESO work identically on AKS, EKS, and GKE. Cloud-native secret stores differ materially; abstracting over them via Vault keeps our Helm chart cloud-agnostic.
- **Rotatable.** Updating a value in Vault triggers ESO reconciliation within the `refreshInterval` (default 1h); a Deployment restart picks it up.
- **Auditable.** Vault's audit log captures every secret read with caller identity.
- **Compliant.** Maps cleanly to SOC 2 CC6.1 and ISO 27001 A.5.17.
- **Operator-familiar.** Vault is broadly deployed in enterprise infra; our approach reuses something they already know.

### Negative

- **Customer dependency.** Customers without Vault must deploy it. We do not ship a Vault helm chart here, because Vault's DR story is customer-specific and we do not want to take on operational responsibility for a critical piece of infra we don't own.
- **Two moving parts.** ESO + Vault. Each can fail independently. Mitigation: incident runbook has explicit sections for ESO-error and Vault-unreachable scenarios.
- **Secret visibility.** ESO produces a Kubernetes Secret; anyone with `secrets.get` in the namespace can read it. Addressed by least-privilege RBAC.
- **Refresh latency.** Default 1h; accept this for most workloads, or force sync via annotation for urgent rotations.

### Mitigations

- Vault's bootstrap and DR are the customer's responsibility; runbooks reference the customer's Vault DR plan rather than defining one.
- K8s RBAC for Secrets is locked down by default in the `llm-stack` namespace (not addressed in this chart directly, but recommended via admission controllers).
- ESO status is monitored via Prometheus metrics; the incident response runbook includes the canonical alert on `externalsecret_sync_calls_error_total`.

## Alternatives Considered

### A2 - ESO reading directly from cloud-native stores

Simpler in a single-cloud deployment; no Vault needed. Rejected as default because:

- Cross-cloud customers need Vault anyway for DR or consistency across regions.
- Cloud-native stores differ in their audit logging granularity and IAM model; we'd have to document three different patterns.
- Vault gives us a clean abstraction that survives customer cloud swaps.

**When to prefer:** single-cloud customer, small team, no existing Vault. To switch: swap `ClusterSecretStore` provider to Key Vault / Secrets Manager / Google Secret Manager; no chart changes needed.

### A3 - Vault Agent Injector sidecar

Vault's official pattern: a sidecar in each pod that renders secrets into templates. Rejected because:

- Adds a container and a ConfigMap per workload.
- Secret material appears as a file inside the pod; ESO produces a Kubernetes Secret that is consistent with the rest of the ecosystem.
- Rotation requires more coordination (template rendering + reloader sidecar).

**When to prefer:** customers that want zero Kubernetes Secret objects at all (e.g. policy forbids it). To switch: replace `externalsecret.yaml` with Vault Agent templates; chart has the extension points.

### A4 - SealedSecrets (Bitnami)

Encrypted secrets committed to Git, decrypted by a controller. Rejected because:

- Rotation requires a Git commit, which couples security rotations to PR review.
- Controller holds a private key that is itself a critical secret (what rotates the rotator?).
- Audit trail is "look at Git history", which is weaker than Vault's audit log.

**When to prefer:** offline-first environments where Vault is not available and GitOps is the only deployment mechanism.

### A5 - sops + age + helm-secrets

Encrypted values files. Rejected because:

- Same rotation coupling problem as SealedSecrets.
- Decryption keys (age / KMS) are a key-management problem by themselves.
- Poor fit for secrets that rotate frequently.

**When to prefer:** bootstrapping before Vault is available; OK for early-stage installs that have not yet deployed Vault.

## Operational implications

- **Onboarding.** Operator pre-creates `ClusterSecretStore` pointing at Vault; this is a cluster-level one-time setup.
- **Per-secret.** Application team populates `llm-stack/<path>` in Vault; the chart's `ExternalSecret` picks it up.
- **Rotation.** See `docs/runbooks/rotate-secrets.md`.
- **Incident.** See `docs/runbooks/incident-response.md` for ESO and Vault symptom-to-action mapping.

## Follow-ups

- Consider Vault secret leasing with short TTLs for database credentials (ESO supports `ttl`).
- Add pre-install hook that validates `ClusterSecretStore` exists before proceeding with install.
- Consider vso (Vault Secrets Operator, HashiCorp's direct Kubernetes operator) as an alternative to ESO once it matures. ESO remains the more ecosystem-agnostic choice as of v0.1.0.
