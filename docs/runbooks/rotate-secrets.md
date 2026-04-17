# Runbook - Rotate Secrets

Rotate the secrets used by `llm-stack`: JWT signing key, registry push/pull tokens, OPA bundle signing key, model registry API keys, and any other material managed through External Secrets Operator and Vault.

## When to use

- Scheduled quarterly rotation.
- Ad-hoc after an employee leaves or privileged access changes.
- After a suspected compromise (see also [`incident-response.md`](./incident-response.md)).

## Prerequisites

- Operator access to Vault (write permission on the relevant paths).
- `kubectl` access to the release namespace.
- A short maintenance window if rotating the JWT signing key (existing tokens will be invalidated).

## Scope

| Secret | Owner | Rotation cadence |
|--------|-------|------------------|
| JWT signing key (gateway) | Platform | Quarterly, or after incident |
| Vault root token | Security | Never exposed; use short-lived tokens |
| Vault kubernetes auth role tokens | Platform | 24h default |
| Registry push token | CI/CD | After each mirror operation |
| Registry pull secret | Cluster | Quarterly |
| KMS key versions | Cloud | Automatic (Terraform sets rotation policy) |
| Qdrant API key | Application | Quarterly |
| OPA decision logging token | Security | Quarterly |

## Procedure

### Rotate a secret stored in Vault (reconciled by ESO)

1. Update the value in Vault:

   ```bash
   vault kv put -mount=secret llm-stack/jwt signing_key="$(openssl rand -base64 64)"
   ```

2. Force ESO to reconcile immediately (optional; default refresh is every 1h):

   ```bash
   kubectl -n llm-stack annotate externalsecret llm-stack-jwt \
     force-sync=$(date +%s) --overwrite
   ```

3. Verify the managed Kubernetes Secret was updated:

   ```bash
   kubectl -n llm-stack get secret llm-stack-jwt -o jsonpath='{.metadata.annotations}'
   ```

   Expected: `reconcile.external-secrets.io/data-hash` has changed.

4. Restart the consumer workload so it picks up the new value:

   ```bash
   kubectl -n llm-stack rollout restart deployment/llm-stack-gateway
   kubectl -n llm-stack rollout status deployment/llm-stack-gateway --timeout=5m
   ```

5. Run smoke test:

   ```bash
   ./scripts/smoke-test.sh --namespace llm-stack
   ```

### Rotate a registry pull secret

1. Create a new push credential at the registry (ACR: `az acr token create`, ECR: `aws ecr get-login-password`, Artifact Registry: service-account key).
2. Update Vault:

   ```bash
   vault kv put -mount=secret llm-stack/registry token="<new-token>"
   ```

3. The `ExternalSecret` `llm-stack-model-registry` reconciles within 1h; re-create imagePullSecrets from it as needed. If the cluster uses a cluster-wide pull secret, also update it.
4. Revoke the old credential once the new one is in use and confirmed.

### Rotate the KMS key version

The Terraform modules set a rotation policy (90 days for Key Vault keys, `rotation_period = 7776000s` on GCP). AWS KMS has `enable_key_rotation = true`.

Manual rotation:

- **Azure:** `az keyvault key rotate --vault-name <kv> --name <key>`
- **AWS:** KMS keys auto-rotate; to force, create a new alias pointing to a new key and update the EKS cluster's `encryption_config`.
- **GCP:** `gcloud kms keys versions create --location <region> --keyring <kr> --key <key>`

Existing data remains accessible; new data uses the new key version.

### Rotate OPA policy signing key

If the OPA bundle is signed (out-of-scope for the default chart, but common in regulated environments):

1. Generate the new keypair.
2. Update the public key in the OPA sidecar ConfigMap. Restart the gateway.
3. Sign new bundles with the new private key only.
4. Destroy the old private key.

## Verification

For each rotation:

- [ ] Vault reports the new value at the expected path.
- [ ] The dependent Kubernetes Secret hash has changed.
- [ ] The consumer Deployment has been restarted successfully.
- [ ] Smoke tests pass.
- [ ] The old secret has been revoked at the source of truth.

## Audit

Record the following in the ticket or change record:

- Operator identity
- Timestamps (start, complete)
- Path(s) rotated
- Verification commands run and their output
- Whether the old value was explicitly revoked (required for security-driven rotations)

## Rollback

If a rotation causes an outage:

1. Re-write the old value to Vault:

   ```bash
   vault kv put -mount=secret llm-stack/<path> <key>=<old-value>
   ```

2. Force ESO sync and restart the consumer.
3. Investigate the failure before retrying. Common causes: the rotated secret is also referenced outside Vault (e.g. hardcoded in a CI job).

## Emergency rotation (post-compromise)

Follow the above procedure but with these differences:

- Use the [`incident-response.md`](./incident-response.md) process to declare a SEV event first.
- Rotate _all_ secrets in the namespace, not just the suspected one.
- Revoke cluster credentials (cloud IAM session tokens) in parallel.
- Capture a diagnostic bundle before restarting any workload: `./scripts/collect-diag-bundle.sh`.
