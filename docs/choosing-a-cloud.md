# Choosing a Cloud

All three Terraform modules (`azure-aks`, `aws-eks`, `gcp-gke`) deliver a functionally equivalent outcome: a private-control-plane Kubernetes cluster with GPU nodes, customer-managed keys, a private container registry, and private endpoints for the services the cluster needs.

Pick the cloud that matches the customer's existing relationship and GPU availability.

## Decision matrix

| Factor | Azure AKS | AWS EKS | GCP GKE |
|--------|-----------|---------|---------|
| Existing customer relationship | Microsoft Enterprise Agreement customers, public sector, healthcare | AWS-first SaaS shops, mid-market, financial services | Google-aligned data/AI customers, media, ad tech |
| APAC GPU availability (Seoul / Tokyo / Singapore) | A100 in all three; H100 in Tokyo / Singapore | A100 / H100 in Seoul / Tokyo / Sydney; A10G widely | A100 in Tokyo / Seoul; H100 in Tokyo |
| Private control plane | Private Cluster (no public API) | `endpointPrivateAccess=true` | Private endpoint master |
| Customer-managed keys (etcd) | Key Vault Premium (HSM) | KMS (with CloudHSM) | Cloud KMS (HSM protection) |
| Private registry | ACR Premium + Private Endpoint | ECR + VPC Interface Endpoint | Artifact Registry + PSC |
| Workload identity | Azure AD Workload Identity | IRSA (OIDC on IAM) | Workload Identity (GKE Metadata Server) |
| Cost of GPU node (1x A100 80GB, 1-year RI) | approx USD 2,200/mo | approx USD 2,900/mo | approx USD 2,900/mo |
| Operational simplicity (subjective) | High | High with add-ons | Highest defaults out-of-the-box |
| Best-fit when... | Customer standardizes on Microsoft, needs Defender for Containers + Azure Policy | Customer is AWS-native, already has IAM + Org SCPs | Customer wants strong out-of-the-box security defaults (Binary Auth, Shielded Nodes) |

## When to use multi-cloud

If the customer has a strict multi-cloud policy, use `terraform/examples/airgapped-enterprise/main.tf`. That example selects between the three modules by the `cloud` variable and produces a normalized output contract so downstream tooling is the same.

Do not run all three simultaneously in one environment; treat one cloud as primary and use the others for DR.

## Specific callouts

### Azure
- Prefer Azure AD authentication over local accounts (`local_account_disabled = true`).
- Use Azure Policy for governance (Azure Policy add-on for AKS).
- GPU VMs: `Standard_NC24ads_A100_v4` is the default. For H100 use `Standard_ND96isr_H100_v5` in regions where available.
- Private DNS zones for `privatelink.*.azure.com` must be linked to the VNet; the module does this for the services it creates.

### AWS
- Use EKS access entries (`authentication_mode = API`) over the legacy aws-auth ConfigMap.
- The default node group has no public egress; rely on VPC endpoints + NAT only where strictly required.
- Consider `p5.48xlarge` for H100 workloads. For dev, `g5.12xlarge` (A10G) is sufficient.
- Use EBS CSI driver with `gp3` default storage class for Qdrant. Encryption at rest defaults to AWS-managed KMS; override with the module's KMS key.

### GCP
- Binary Authorization is enforce-mode by default in this module (`PROJECT_SINGLETON_POLICY_ENFORCE`). Ensure the customer has a Binary Auth policy before installing.
- Private endpoint master requires a bastion or IAP tunnel for kubectl access.
- Use Cloud NAT for minimal required egress; rely on `private.googleapis.com` for Google API access.
- Artifact Registry `immutable_tags = true` by default. Plan for tag churn in CI.

## Decision flow

1. Does the customer already have a cloud account for this workload? Use that cloud.
2. Are you offered a choice by the customer? Prefer the one with the best GPU availability in their target region for the model size.
3. Does the customer's compliance team prefer HSM-backed etcd keys? All three support this; Azure Premium KV and GCP Cloud KMS HSM are the strongest defaults.
4. Does the customer have strict egress-denial requirements? All three modules are egress-denied by default; GKE's private endpoint master + `private.googleapis.com` has the shortest path to "zero public endpoints."
