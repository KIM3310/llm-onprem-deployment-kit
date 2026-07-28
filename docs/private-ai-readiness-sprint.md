# Private AI Readiness Sprint

This is the delivery contract for the `private-ai-readiness-sprint` lane. It produces a defensible go or no-go decision for one customer-owned use case. It is not a turnkey production deployment.

## Included

1. Use-case, data-sensitivity, residency, latency, capacity, and budget scorecard.
2. Customer/vendor responsibility matrix.
3. Cloud, network, identity, model, secret, data, logging, and support boundary map.
4. Customer-specific Terraform and Helm adaptation plan.
5. Static validation and one agreed dry-run or controlled evaluation path.
6. Cost, capacity, dependency, model-license, and operational risk register.
7. Evaluation, rollback, teardown, and evidence-retention plan.
8. Go or no-go decision record and production gap list.

## Customer Ownership

The customer owns the cloud account, billing, IAM, network, cluster, registry, KMS, secret manager, prompts, model weights, vector data, runtime logs, backups, and incident evidence. Any vendor access is time-bounded, least-privilege, approved, recorded, and revocable.

## Explicit Exclusions

- Vendor-hosted prompts, model weights, vector data, secrets, or runtime telemetry.
- End-user identity, tenant authorization, quotas, rate limiting, or policy gateway.
- Clustered Qdrant, high availability, disaster-recovery proof, or an SLO.
- Compliance certification, legal assurance, production SLA, or unattended rollout.

## Acceptance

- `make verify` and the agreed infrastructure validation commands pass.
- The Helm runtime contract shows a real Traefik-to-vLLM route and API-key secret reference.
- The customer confirms effective private routing, encryption, secret, identity, audit, backup, and recovery requirements.
- A named customer owner signs the go or no-go record and next-stage scope.

Start a private scoping request through the [Private AI Readiness Sprint intake](https://kim3310-doeon-kim-portfolio.pages.dev/?offer=llm-onprem-deployment-kit&inquiry=private-ai-readiness-sprint#private-inquiry). Do not include credentials or sensitive architecture details in the initial form.
