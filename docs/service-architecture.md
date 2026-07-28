# Service Architecture - llm-onprem-deployment-kit

This is the supported boundary for a `private-ai-readiness-sprint`. The repository is a customer-owned pilot baseline, not a vendor-hosted control plane.

## Ownership Boundary

```text
Public architecture and private scope intake
  -> customer cloud account and network
  -> customer identity / API gateway / quotas / rate limits
  -> internal load balancer
  -> Traefik TLS and reverse proxy
  -> API-key-protected vLLM
  -> optional single-node Qdrant
  -> customer metrics, logs, backup, and incident systems
```

| Resource | Owner | Repository contribution |
|---|---|---|
| Cloud account, billing, IAM, network | Customer | Terraform module starters and review checklist |
| Cluster, registry, KMS, secret manager | Customer | Helm references and optional ESO resources |
| Identity, tenant policy, quotas, rate limits | Customer | Explicit exclusion and integration requirement |
| Prompts, model weights, vector data | Customer | No vendor-hosted data path |
| Logs, audit, retention, alerts, incident evidence | Customer | Collector/scrape configuration starter and runbooks |
| Vendor access | Customer-approved | Time-bounded, least-privilege, recorded, and revocable |

## Current Helm Contract

- Traefik has a tested file-provider route to vLLM.
- vLLM requires a customer-owned API-key secret outside the dev override.
- The default chart fails when required secret references or TLS configuration are missing.
- Qdrant is fixed at one replica because distributed consensus is not configured.
- OPA, OIDC/SAML, tenant policy, quotas, rate limits, and east-west mTLS are not included.
- NetworkPolicy is off in the baseline and enabled by the air-gap overlay only with approved ingress sources.
- ESO is optional and assumes a customer-created `SecretStore` or `ClusterSecretStore`.

## Evidence Boundary

Terraform validation, Helm render/schema checks, ShellCheck, and repository tests prove static contracts. They do not prove actual provider routing, GPU availability, encryption, secret rotation, model licensing, identity, backup recovery, audit completeness, high availability, latency, capacity, cost, or an SLO. Those are customer-environment acceptance items.

## Promotion Beyond Readiness

The sprint ends with a go or no-go decision and production gap list. A production implementation is a separately scoped phase that must close identity, authorization, quota/rate limiting, clustered state or removal of Qdrant, backup/restore, immutable audit, observability, incident response, vulnerability management, capacity, cost, and support ownership.
