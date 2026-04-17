# SOC 2 Type II - Control Mapping

This document maps the 2017 Trust Services Criteria (Common Criteria + Availability + Confidentiality) to the artifacts delivered by `llm-onprem-deployment-kit`.

It is intended as a starting point for a customer's SOC 2 auditor or the vendor's own readiness team. It is not a SOC 2 report.

## Legend

- **Control** - Criterion ID from TSP Section 100 (2017 TSC, revised).
- **Intent** - Short restatement of the criterion.
- **This kit provides** - What is shipped in this repo.
- **Evidence artifact** - Where the auditor would point a tester.

## Common Criteria (CC)

### CC1 - Control Environment

| Control | Intent | This kit provides | Evidence artifact |
|---------|--------|-------------------|-------------------|
| CC1.1 | Commitment to integrity and ethical values | Code of conduct + ADRs capture decision rationale | `docs/adr/*.md` |
| CC1.4 | Attract, develop, retain competent individuals | Runbooks allow a mid-level SRE to operate the system | `docs/runbooks/*.md` |

### CC2 - Communication and Information

| Control | Intent | This kit provides | Evidence artifact |
|---------|--------|-------------------|-------------------|
| CC2.1 | Generate and use relevant, quality information | OTel-based observability pipeline | `helm/llm-stack/templates/otel-collector-configmap.yaml` |
| CC2.2 | Internal communication of objectives and responsibilities | README + architecture doc enumerate responsibilities per tier | `README.md`, `docs/architecture.md` |
| CC2.3 | External communication (customers) | Airgap requirements document + quickstarts | `docs/compliance/airgap-requirements.md` |

### CC3 - Risk Assessment

| Control | Intent | This kit provides | Evidence artifact |
|---------|--------|-------------------|-------------------|
| CC3.1 | Specify objectives for risk identification | Threat model enumerates adversary in and out of scope | `docs/security-model.md` |
| CC3.2 | Identify risks to achievement of objectives | Threat model + ADRs enumerate trade-offs | `docs/security-model.md`, `docs/adr/*.md` |
| CC3.4 | Identify and assess changes in risk | Change management via Terraform + Helm is captured by CI | `.github/workflows/terraform-validate.yml` |

### CC4 - Monitoring Activities

| Control | Intent | This kit provides | Evidence artifact |
|---------|--------|-------------------|-------------------|
| CC4.1 | Ongoing and/or separate evaluations | CI workflows on PRs; runbooks require weekly validation | `.github/workflows/*.yml` |
| CC4.2 | Communicate and rectify deficiencies | Incident response runbook defines SEV levels and paging | `docs/runbooks/incident-response.md` |

### CC5 - Control Activities

| Control | Intent | This kit provides | Evidence artifact |
|---------|--------|-------------------|-------------------|
| CC5.1 | Select and develop control activities | Default-deny NetworkPolicy + Pod security context | `helm/llm-stack/templates/networkpolicy.yaml`, `helm/llm-stack/values.yaml` (`podSecurityContext`) |
| CC5.2 | Select and develop general controls over technology | Terraform modules enforce versions; Helm chart enforces limits | `terraform/modules/*/versions.tf`, chart resource requests |
| CC5.3 | Deploy controls through policies and procedures | Runbooks are executable; CI enforces validation | `docs/runbooks/*.md` |

### CC6 - Logical and Physical Access

| Control | Intent | This kit provides | Evidence artifact |
|---------|--------|-------------------|-------------------|
| CC6.1 | Restricts access to information and assets | Private control plane, OPA at gateway, K8s RBAC | Cluster modules, `helm/.../gateway-deployment.yaml` |
| CC6.2 | Register and authorize new users | Access via cloud IAM groups only; no local accounts on AKS | `terraform/modules/azure-aks/main.tf` (`local_account_disabled = true`) |
| CC6.3 | Review user access periodically | Runbook requires quarterly access reviews | `docs/runbooks/rotate-secrets.md` |
| CC6.6 | Implements logical access security for data transmission | TLS at gateway; mTLS roadmap; private LB only | `helm/.../gateway-service.yaml` |
| CC6.7 | Restrict the transmission, movement, and removal of information | Egress restricted by NetworkPolicy + userDefinedRouting | `helm/.../networkpolicy.yaml` |
| CC6.8 | Implements controls to prevent unauthorized software installation | Immutable image tags, Binary Authorization on GKE | `terraform/modules/gcp-gke/main.tf` (`binary_authorization` block) |

### CC7 - System Operations

| Control | Intent | This kit provides | Evidence artifact |
|---------|--------|-------------------|-------------------|
| CC7.1 | Detect and prevent security events | Container Insights / CloudWatch logs / Cloud Logging + alerting | Cluster modules, ServiceMonitors |
| CC7.2 | Monitor system components | OTel collector + ServiceMonitors + HPA | `helm/.../otel-collector-configmap.yaml`, `helm/.../servicemonitor.yaml` |
| CC7.3 | Analyze incidents | Diag bundle script; incident runbook | `scripts/collect-diag-bundle.sh`, `docs/runbooks/incident-response.md` |
| CC7.4 | Respond to security incidents | Incident runbook with SEV levels and paging | `docs/runbooks/incident-response.md` |
| CC7.5 | Recover from identified incidents | Disaster recovery runbook | `docs/runbooks/disaster-recovery.md` |

### CC8 - Change Management

| Control | Intent | This kit provides | Evidence artifact |
|---------|--------|-------------------|-------------------|
| CC8.1 | Authorize, design, develop, configure, document, test, approve, and implement changes | Terraform plan / apply lifecycle, Helm diff, pre-commit CI | Makefile, CI workflows |

### CC9 - Risk Mitigation

| Control | Intent | This kit provides | Evidence artifact |
|---------|--------|-------------------|-------------------|
| CC9.1 | Identifies, selects, and develops risk mitigation activities | ADRs capture mitigation strategies per decision | `docs/adr/*.md` |
| CC9.2 | Vendor risk management | Pinned upstream image digests; image mirroring strategy | `scripts/airgap-mirror.sh` |

## Availability (A)

| Control | Intent | This kit provides | Evidence artifact |
|---------|--------|-------------------|-------------------|
| A1.1 | Maintain, monitor, and evaluate current processing capacity | HPA + DCGM; metrics dashboards | `helm/.../inference-hpa.yaml` |
| A1.2 | Data backup and recovery | DR runbook; Qdrant snapshots; cloud-native volume snapshots | `docs/runbooks/disaster-recovery.md` |
| A1.3 | Recovery infrastructure testing | DR runbook includes quarterly drill procedure | `docs/runbooks/disaster-recovery.md` (Testing section) |

## Confidentiality (C)

| Control | Intent | This kit provides | Evidence artifact |
|---------|--------|-------------------|-------------------|
| C1.1 | Identifies and maintains confidential information | PII-aware logging: content not logged by default | `helm/llm-stack/values.yaml` (`--disable-log-requests`) |
| C1.2 | Disposes of confidential information | PVC retention policy + KMS key deletion policy | Cluster modules (`soft_delete_retention_days`, `deletion_window_in_days`) |

## Gaps to close before a SOC 2 audit

- **Access review evidence.** The kit ships the runbook for rotation; the customer must actually rotate on a cadence and keep evidence. This kit cannot attest to operations.
- **Incident evidence.** SEV levels and paging are defined; customer must wire to their ticketing system.
- **Personnel controls (CC1.4, CC1.5).** Organizational controls are out of scope for a software kit.
- **Physical controls (CC6.4, CC6.5).** Cloud-provider inherited; reference SOC 2 reports from Azure / AWS / GCP.
