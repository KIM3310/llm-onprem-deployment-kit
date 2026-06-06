# Review Guide - llm-onprem-deployment-kit

Updated: 2026-05-30

Use this page as the short path through the repository. It keeps the review grounded in the code, docs, commands, and boundaries that are already present.

## Summary

| Field | Notes |
|---|---|
| Lane | B2B private AI deployment |
| Core idea | Terraform/Helm/private deployment kit for LLM workloads that cannot use uncontrolled hosted endpoints. |
| Primary reader | Regulated enterprises, AI vendors, platform teams, and security architects. |
| Stack | Terraform, Helm |

## Open First

1. Start with the README fast path and architecture section.
2. Open `docs/service-launch-playbook.md` only when reviewing the product or service angle.
3. Check the commands below before making claims about quality.
4. Skim the CI workflows and fixture data before deeper implementation review.
5. Read the boundaries section before presenting the project externally.

## Checks

| Purpose | Command |
|---|---|
| Review gate | `Review README fast path, CI workflow, and documented demo artifacts` |

## CI

- .github/workflows/architecture-blueprint.yml
- .github/workflows/ci.yml
- .github/workflows/dependency-review.yml
- .github/workflows/helm-lint.yml
- .github/workflows/repository-health.yml
- .github/workflows/repository-surface.yml
- .github/workflows/secret-scan.yml
- .github/workflows/shellcheck.yml
- .github/workflows/terraform-validate.yml

## Evidence

- infrastructure-as-code review surface
- Kubernetes packaging surface
- make validate passes
- Terraform/Helm/Shell checks pass
- Runbooks are current

## Commercial Notes

| Possible offer | Working scope assumption |
|---|---|
| Readiness review | Scope after buyer intake |
| Private deployment setup | Scope after buyer intake |
| Airgap runbook and compliance workshop | Scope after buyer intake |

## Boundaries

- Templates are not certifications
- Customer threat model required
- Secrets/IAM must be customer-specific

## Useful Metrics

- Deployment lead time
- Control mapping coverage
- Runbook completeness
