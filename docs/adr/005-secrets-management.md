# ADR 005 - Secrets Management Boundary

## Status

Amended.

## Context

Production LLM deployments have two classes of secrets:

1. **Platform secrets.** Registry pull tokens, TLS certificates, secret-store credentials, and any KMS/Vault recovery material.
2. **Application secrets.** The vLLM inference API key and any customer application or observability credentials added later.

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

The baseline references an existing Kubernetes Secret and keeps ESO disabled. For customer pilots, ESO may read from an approved `SecretStore` or `ClusterSecretStore`, including Vault or a cloud-native manager.

- The inference Deployment consumes `llm-stack-inference-api-key` by default.
- The air-gap overlay enables one `ExternalSecret` for that key.
- The operator must pre-create and validate the referenced store.
- The chart does not install Vault, a cloud secret manager, ESO, or a store resource.
- ESO creates a native Kubernetes Secret; customer etcd encryption, RBAC, rotation, and audit controls remain material.

The values file's `externalSecrets.secrets[]` array enumerates each secret by name and mapping. Adding a new secret is a values edit + git PR.

## Consequences

### Positive

- **Customer choice.** The chart does not force a vendor-owned store or custody model.
- **Portable reference.** Workloads consume a Kubernetes Secret regardless of which approved store or synchronization method creates it.
- **Rotatable.** Updating a value in Vault triggers ESO reconciliation within the `refreshInterval` (default 1h); a Deployment restart picks it up.
- **Auditable when integrated.** The customer store, ESO, Kubernetes audit, and access-review configuration determine evidence quality.

### Negative

- **Customer dependency.** Protected pilots need an approved secret manager, ownership, rotation, recovery, and break-glass path.
- **Optional moving parts.** When ESO is used, both ESO and its store can fail independently.
- **Secret visibility.** ESO produces a Kubernetes Secret; anyone with `secrets.get` in the namespace can read it. Addressed by least-privilege RBAC.
- **Refresh latency.** Default 1h; accept this for most workloads, or force sync via annotation for urgent rotations.

### Mitigations

- Secret-store bootstrap and DR are customer responsibilities.
- Kubernetes Secret RBAC is not created by this chart and must be reviewed.
- ESO status is monitored via Prometheus metrics; the incident response runbook includes the canonical alert on `externalsecret_sync_calls_error_total`.

## Alternatives Considered

### A2 - ESO reading directly from cloud-native stores

Simpler in a single-cloud deployment; no Vault needed. Rejected as default because:

- Cross-cloud customers need Vault anyway for DR or consistency across regions.
- Cloud-native stores differ in their audit logging granularity and IAM model; we'd have to document three different patterns.
- Vault gives us a clean abstraction that survives customer cloud swaps.

**When to prefer:** single-cloud customer, small team, no existing Vault. Supply the provider-specific store and remote key mapping in customer values.

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
