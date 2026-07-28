# Enterprise Readiness Notes - llm-onprem-deployment-kit

Updated: 2026-05-30

This note defines what an enterprise security reviewer, public-sector operator, serious user, or technical evaluator can safely infer from this repository today. It is intentionally conservative: public proof is separated from production claims.

## Scope

| Field | Notes |
|---|---|
| Repository | `llm-onprem-deployment-kit` |
| Lane | B2B private AI deployment |
| Primary reader | Regulated enterprises, AI vendors, platform teams, and security architects. |
| Core wedge | Terraform/Helm/private deployment kit for LLM workloads that cannot use uncontrolled hosted endpoints. |
| Stack | Terraform, Helm |
| Readiness posture | Readiness-sprint baseline; not a turnkey, certified, or production-ready platform. |

## Enterprise Controls

| Control | Current expectation |
|---|---|
| Data boundary | Customer documents require approved storage, document-rights checks, redaction policy, and inspectable retrieval/evaluation logs. |
| Identity and access | The chart can require one vLLM API key. Customer identity, tenant authorization, quotas, rate limits, service accounts, and access reviews are separate acceptance work. |
| Auditability | CI, render, and mapping artifacts show design intent only. Customer runtime logs, immutable retention, request audit, and evidence of operation must be implemented and retained by the customer. |
| Observability | Collector and scrape configuration are starters. Customer endpoints, redaction, alerts, retention, SLOs, and incident ownership require in-environment evidence. |
| Release gate | Review gate: README, CI workflow, docs, fixtures, and demo artifacts |
| Support handoff | Name the owner, escalation path, rollback path, known limits, and review cadence before production testing. |

## Verification Surface

| Purpose | Command |
|---|---|
| Review gate | `README, CI workflow, docs, fixtures, and demo artifacts` |

## CI Surface

- .github/workflows/architecture-blueprint.yml
- .github/workflows/ci.yml
- .github/workflows/dependency-review.yml
- .github/workflows/helm-lint.yml
- .github/workflows/repository-health.yml
- .github/workflows/repository-surface.yml
- .github/workflows/secret-scan.yml
- .github/workflows/shellcheck.yml
- .github/workflows/terraform-validate.yml

## Acceptance Criteria

- README, CI workflow, docs, fixtures, and demo artifacts can be run or the equivalent CI gate is visible.
- README, repository review guide, quality notes, service model, and this readiness note agree on the same scope.
- Demo, fixture, synthetic, or public-data boundaries are explicit before a security reviewer sees outputs.
- A security reviewer can identify the first useful outcome without reading implementation details.
- Production claims stay behind customer-specific validation, access control, monitoring, and support handoff.

## Integration Path

- Run a synthetic-data walkthrough with the security approver and document the acceptance criteria.
- Scope a controlled pilot using approved data, named users, secrets, and rollback paths.
- Convert the pilot into an operating handoff with monitoring, review cadence, support owner, and renewal metric.

## Proof Points

- make validate passes
- Terraform/Helm/Shell checks pass
- Runbooks are current

## Operating Metrics

- Deployment lead time
- Control mapping coverage
- Runbook completeness

## Open Risks

- Templates are not certifications
- Customer threat model required
- Secrets/IAM must be customer-specific
- Qdrant is intentionally single-node; the chart rejects unconfigured multi-replica state.
- ESO copies values into Kubernetes Secrets; actual etcd encryption, RBAC, rotation, and audit depend on customer controls.
- API-key auth is not identity, tenant policy, quota, rate limiting, or an authorization gateway.
- Rendered templates do not prove private routing, backup recovery, high availability, audit completeness, or an SLO.

## Finish Line

- Keep the public repository honest, runnable, and easy to review.
- Keep sensitive data, secrets, private tenant details, and unsupported claims out of public artifacts.
- Treat this repository as a proof surface until an approved pilot defines users, data, access, monitoring, support, and success metrics.
