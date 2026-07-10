# ISO/IEC 27001:2022 - Control Mapping

This document maps the Annex A controls of ISO/IEC 27001:2022 (93 controls in 4 themes) to artifacts shipped by `llm-onprem-deployment-kit`.

The mapping is scoped to controls that a software deployment kit can meaningfully influence. Organizational controls such as HR and training are the customer's responsibility.

## Themes

- A.5 Organizational controls (37 controls)
- A.6 People controls (8 controls)
- A.7 Physical controls (14 controls)
- A.8 Technological controls (34 controls)

## A.5 Organizational controls (selected)

| Control | Title | This kit provides | Evidence artifact |
|---------|-------|-------------------|-------------------|
| A.5.1 | Policies for information security | Security model + ADRs document vendor-side policy | `docs/security-model.md`, `docs/adr/*.md` |
| A.5.7 | Threat intelligence | Image supply runbook mandates digest tracking | `docs/runbooks/airgap-image-mirror.md` |
| A.5.15 | Access control | Cloud IAM + K8s RBAC; no local accounts | Cluster modules |
| A.5.16 | Identity management | Workload Identity / IRSA + ESO + Vault | `helm/.../externalsecret.yaml`, cluster modules |
| A.5.17 | Authentication information | Secrets via ESO from Vault; never committed to Git | `helm/.../externalsecret.yaml`, `.gitignore` |
| A.5.18 | Access rights | Least-privilege RBAC; runbook requires quarterly review | `docs/runbooks/rotate-secrets.md` |
| A.5.23 | Information security for use of cloud services | Private endpoints + CMK across all three modules | Cluster modules |
| A.5.24 | Information security incident management planning and preparation | Incident response runbook | `docs/runbooks/incident-response.md` |
| A.5.25 | Assessment and decision on information security events | SEV levels defined in incident runbook | `docs/runbooks/incident-response.md` |
| A.5.26 | Response to information security incidents | Playbooks per SEV level; diag bundle | `scripts/collect-diag-bundle.sh`, incident runbook |
| A.5.29 | Information security during disruption | DR runbook | `docs/runbooks/disaster-recovery.md` |
| A.5.30 | ICT readiness for business continuity | HPA + PDB + multi-AZ node pools | Cluster modules, chart templates |
| A.5.32 | Intellectual property rights | Image inventory respects upstream licenses | `scripts/airgap-mirror.sh`, README License section |
| A.5.37 | Documented operating procedures | Six runbooks | `docs/runbooks/*.md` |

## A.8 Technological controls

### Identity and authentication

| Control | Title | This kit provides | Evidence artifact |
|---------|-------|-------------------|-------------------|
| A.8.2 | Privileged access rights | No cluster admins by default; bootstrap-only admin entry | EKS access entry config |
| A.8.3 | Information access restriction | OPA at gateway; NetworkPolicy default-deny | `helm/.../opa-sidecar-configmap.yaml`, `helm/.../networkpolicy.yaml` |
| A.8.4 | Access to source code | CI gates `terraform validate`, `helm lint`, `shellcheck` | CI workflows |
| A.8.5 | Secure authentication | OIDC / SAML at gateway; cloud IAM for cluster | `helm/.../gateway-deployment.yaml` |

### Cryptography

| Control | Title | This kit provides | Evidence artifact |
|---------|-------|-------------------|-------------------|
| A.8.24 | Use of cryptography | CMK via Key Vault / KMS / Cloud KMS; rotation policies set | `terraform/modules/azure-aks/main.tf` (`azurerm_key_vault_key.etcd` rotation), equivalent in AWS/GCP modules |

### Operations security

| Control | Title | This kit provides | Evidence artifact |
|---------|-------|-------------------|-------------------|
| A.8.8 | Management of technical vulnerabilities | Image scanning on push (ECR/ACR Premium/Artifact Registry); pinned versions | Cluster modules |
| A.8.9 | Configuration management | Terraform + Helm IaC | Root README Quick Start |
| A.8.10 | Information deletion | Soft-delete windows on keys and secrets | Cluster modules |
| A.8.12 | Data leakage prevention | Request content not logged; OTel metadata-only | `helm/.../values.yaml` (`--disable-log-requests`), security-model doc |
| A.8.13 | Information backup | Qdrant backup runbook + cloud volume snapshots | `docs/runbooks/disaster-recovery.md` |
| A.8.14 | Redundancy of information processing facilities | Multi-AZ node pools; HPA+PDB; 3-replica Qdrant | Cluster modules, chart templates |
| A.8.15 | Logging | Control plane + OTel + OPA decisions | Cluster modules, OTel config |
| A.8.16 | Monitoring activities | ServiceMonitors + alert rules referenced in DR runbook | `helm/.../servicemonitor.yaml` |
| A.8.17 | Clock synchronization | NTP via node pool defaults (cloud-managed) | Cluster modules |

### Communications security

| Control | Title | This kit provides | Evidence artifact |
|---------|-------|-------------------|-------------------|
| A.8.20 | Networks security | Private cluster, private endpoints, VPC endpoints, default-deny NP | Cluster modules, `helm/.../networkpolicy.yaml` |
| A.8.21 | Security of network services | Only TLS exposed at the gateway; metrics on a separate port | `helm/.../gateway-service.yaml` |
| A.8.22 | Segregation of networks | Node subnets, PE subnets, intra subnets separately | Cluster modules |

### Application security

| Control | Title | This kit provides | Evidence artifact |
|---------|-------|-------------------|-------------------|
| A.8.26 | Application security requirements | OPA policy bundle + chart defaults to secure values | `helm/.../opa-sidecar-configmap.yaml` |
| A.8.28 | Secure coding | ShellCheck CI on scripts; Terraform fmt/validate; Helm lint | `.github/workflows/*.yml` |
| A.8.29 | Security testing in development and acceptance | Smoke test + schema validation in CI | `scripts/smoke-test.sh`, `.github/workflows/helm-lint.yml` |
| A.8.32 | Change management | PR-based change with CI gates | CI workflows |

## Controls explicitly out of scope

| Control | Why out of scope |
|---------|------------------|
| A.6.* (People controls) | Customer-organizational |
| A.7.* (Physical controls) | Inherited from cloud provider |
| A.5.19 - A.5.22 (Supplier) | Customer-specific procurement processes |
| A.5.33 (Protection of records) | Customer's record retention policy, not vendor concern |

## How to use this mapping in an audit

1. The customer's lead auditor receives this document along with the SOC 2 mapping.
2. For each control, the auditor verifies the evidence artifact exists in the deployed repo.
3. Evidence that the control is _operating effectively_ (not just designed) comes from runtime logs (OTel -> Loki) and periodic runbook execution records, which are the customer's responsibility to retain.
