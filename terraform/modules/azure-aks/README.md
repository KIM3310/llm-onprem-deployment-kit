# azure-aks

Production-grade AKS module for `llm-onprem-deployment-kit`.

## What this module provisions

- Resource group (or reuses an existing one)
- Virtual network with two subnets (cluster + private endpoints)
- AKS cluster with:
  - Private control plane (no public API server)
  - Azure RBAC-backed authentication (no local kubeconfig)
  - Azure CNI overlay + Cilium network policy
  - OIDC issuer + Workload Identity enabled
  - Customer-managed key for etcd (when Key Vault is enabled)
  - Azure Policy and Microsoft Defender for Containers
- System node pool (D-series) and optional GPU node pool (NC A100 v4)
- User-assigned managed identity for the control plane
- Log Analytics workspace + Container Insights
- Optional Azure Container Registry (Premium, private endpoint)
- Optional Azure Key Vault (Premium, private endpoint, RBAC mode)

## Usage

```hcl
module "aks" {
  source = "../../"

  name_prefix = "acme-prod"
  location    = "koreacentral"

  vnet_address_space = ["10.64.0.0/16"]
  aks_subnet_cidr    = "10.64.1.0/24"
  pe_subnet_cidr     = "10.64.2.0/27"

  gpu_node_pool = {
    enabled         = true
    vm_size         = "Standard_NC24ads_A100_v4"
    node_count      = 2
    min_count       = 2
    max_count       = 6
    os_disk_size_gb = 256
    node_taints     = ["nvidia.com/gpu=true:NoSchedule"]
  }
}
```

See [`examples/basic/main.tf`](./examples/basic/main.tf) for a fully-wired example.

## Required variables

| Name | Description |
|------|-------------|
| `name_prefix` | Prefix applied to every resource (`1-24` characters). |

All other variables have sane defaults.

## Outputs

| Name | Description |
|------|-------------|
| `cluster_name` | AKS cluster name |
| `cluster_private_fqdn` | Private FQDN of the API server (only resolvable inside the VNet) |
| `kubelet_identity_object_id` | Grant this over Key Vault secrets, storage, etc. |
| `oidc_issuer_url` | Use with Azure AD for Workload Identity federation |
| `acr_login_server` | ACR FQDN, null if `enable_acr=false` |
| `key_vault_uri` | Key Vault URI, null if `enable_key_vault=false` |

## GPU node pool notes

- Default VM: `Standard_NC24ads_A100_v4` (single A100 80GB per VM).
- Scheduled via a taint (`nvidia.com/gpu=true:NoSchedule`) so vLLM pods opt in via tolerations.
- Zones `1` and `2` are selected; customers in regions with more zones may extend.
- For H100s, use `Standard_ND96isr_H100_v5` where available and adjust `os_disk_size_gb` accordingly.

## Cost notes

Indicative Korea Central list prices (subject to change):

- System pool: 3x D4s_v5 approx USD 520/month reserved.
- GPU pool: 1x NC24ads_A100_v4 approx USD 3,800/month on-demand, approx USD 2,200/month 1-year reserved.
- Log Analytics (Container Insights): approx USD 150/month for a 3-node cluster with default verbosity.

Always confirm pricing with the customer's Azure account team.

## Assumptions

- The operator has an Azure AD account with `Owner` or equivalent rights in the target subscription.
- Outbound network access from the subnet is routable to an Azure Firewall or NAT Gateway that allows the AKS required egress (documented at `https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress`). The module sets `outbound_type = "userDefinedRouting"` to make this explicit.
- The caller provides the DNS forwarding required to resolve the `privatelink.*.azure.com` zones from operator workstations (typically via the customer's hub DNS).
