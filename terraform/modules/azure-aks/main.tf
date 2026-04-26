# ----------------------------------------------------------------------------
# azure-aks module - main.tf
#
# Provisions a private-control-plane AKS cluster with:
#   - Resource group (or reuses an existing one)
#   - VNet and subnets for the cluster and for private endpoints
#   - AKS cluster with system + optional GPU node pool
#   - User-assigned managed identity for the cluster
#   - Log Analytics workspace and Container Insights
#   - Optional Azure Container Registry with private endpoint + DNS
#   - Optional Azure Key Vault with private endpoint + DNS
# ----------------------------------------------------------------------------

locals {
  rg_name = coalesce(var.resource_group_name, "${var.name_prefix}-rg")

  base_tags = merge(var.tags, {
    "module" = "azure-aks"
  })
}

# ----------------------------------------------------------------------------
# Random suffix to avoid ACR / Key Vault name collisions
# ----------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 3
}

# ----------------------------------------------------------------------------
# Resource group
# ----------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count    = var.resource_group_name == null ? 1 : 0
  name     = local.rg_name
  location = var.location
  tags     = local.base_tags
}

data "azurerm_resource_group" "existing" {
  count = var.resource_group_name == null ? 0 : 1
  name  = var.resource_group_name
}

locals {
  rg_resolved = var.resource_group_name == null ? azurerm_resource_group.this[0] : data.azurerm_resource_group.existing[0]
}

# ----------------------------------------------------------------------------
# Network
# ----------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  location            = local.rg_resolved.location
  resource_group_name = local.rg_resolved.name
  address_space       = var.vnet_address_space
  tags                = local.base_tags
}

resource "azurerm_subnet" "aks" {
  name                 = "${var.name_prefix}-aks-subnet"
  resource_group_name  = local.rg_resolved.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_subnet_cidr]

  service_endpoints = [
    "Microsoft.KeyVault",
    "Microsoft.ContainerRegistry",
    "Microsoft.Storage",
  ]
}

resource "azurerm_subnet" "private_endpoints" {
  name                              = "${var.name_prefix}-pe-subnet"
  resource_group_name               = local.rg_resolved.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.pe_subnet_cidr]
  private_endpoint_network_policies = "Enabled"
}

# ----------------------------------------------------------------------------
# Managed identity for the cluster control plane
# ----------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.name_prefix}-aks-identity"
  location            = local.rg_resolved.location
  resource_group_name = local.rg_resolved.name
  tags                = local.base_tags
}

# ----------------------------------------------------------------------------
# Log Analytics + diagnostic workspace
# ----------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name_prefix}-law"
  location            = local.rg_resolved.location
  resource_group_name = local.rg_resolved.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = local.base_tags
}

# ----------------------------------------------------------------------------
# AKS cluster (private control plane)
# ----------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "this" {
  name                      = "${var.name_prefix}-aks"
  location                  = local.rg_resolved.location
  resource_group_name       = local.rg_resolved.name
  dns_prefix                = "${var.name_prefix}-aks"
  kubernetes_version        = var.kubernetes_version
  sku_tier                  = "Standard"
  automatic_channel_upgrade = "patch"
  private_cluster_enabled   = true
  local_account_disabled    = true
  azure_policy_enabled      = true
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  tags                      = local.base_tags

  api_server_access_profile {
    authorized_ip_ranges = var.authorized_ip_ranges
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_pool.vm_size
    vnet_subnet_id               = azurerm_subnet.aks.id
    node_count                   = var.system_node_pool.node_count
    min_count                    = var.system_node_pool.min_count
    max_count                    = var.system_node_pool.max_count
    os_disk_size_gb              = var.system_node_pool.os_disk_size_gb
    only_critical_addons_enabled = true
    type                         = "VirtualMachineScaleSets"
    zones                        = ["1", "2", "3"]

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    service_cidr        = "10.100.0.0/16"
    dns_service_ip      = "10.100.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = "userDefinedRouting"
  }

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.this.id
    msi_auth_for_monitoring_enabled = true
  }

  microsoft_defender {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  }

  key_management_service {
    key_vault_key_id = var.enable_key_vault ? azurerm_key_vault_key.etcd[0].id : null
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    utc_offset  = "+09:00"
    start_time  = "02:00"
  }

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
    ]
  }
}

# ----------------------------------------------------------------------------
# GPU node pool (optional)
# ----------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  count                 = var.gpu_node_pool.enabled ? 1 : 0
  name                  = "gpu"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.gpu_node_pool.vm_size
  vnet_subnet_id        = azurerm_subnet.aks.id
  node_count            = var.gpu_node_pool.node_count
  min_count             = var.gpu_node_pool.min_count
  max_count             = var.gpu_node_pool.max_count
  os_disk_size_gb       = var.gpu_node_pool.os_disk_size_gb
  node_taints           = var.gpu_node_pool.node_taints
  zones                 = ["1", "2"]
  mode                  = "User"

  node_labels = {
    "workload" = "llm-inference"
    "gpu"      = "nvidia-a100"
  }

  tags = local.base_tags

  upgrade_settings {
    max_surge = "33%"
  }
}

# ----------------------------------------------------------------------------
# Azure Container Registry (optional, with private endpoint)
# ----------------------------------------------------------------------------

resource "azurerm_container_registry" "this" {
  count                         = var.enable_acr ? 1 : 0
  name                          = "${replace(var.name_prefix, "-", "")}acr${random_id.suffix.hex}"
  resource_group_name           = local.rg_resolved.name
  location                      = local.rg_resolved.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  tags                          = local.base_tags

  retention_policy {
    days    = 30
    enabled = true
  }

  trust_policy {
    enabled = true
  }
}

resource "azurerm_private_dns_zone" "acr" {
  count               = var.enable_acr ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = local.rg_resolved.name
  tags                = local.base_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count                 = var.enable_acr ? 1 : 0
  name                  = "${var.name_prefix}-acr-link"
  resource_group_name   = local.rg_resolved.name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = local.base_tags
}

resource "azurerm_private_endpoint" "acr" {
  count               = var.enable_acr ? 1 : 0
  name                = "${var.name_prefix}-acr-pe"
  location            = local.rg_resolved.location
  resource_group_name = local.rg_resolved.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.base_tags

  private_service_connection {
    name                           = "${var.name_prefix}-acr-psc"
    private_connection_resource_id = azurerm_container_registry.this[0].id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr[0].id]
  }
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  count                = var.enable_acr ? 1 : 0
  scope                = azurerm_container_registry.this[0].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

# ----------------------------------------------------------------------------
# Key Vault (optional, with private endpoint + etcd encryption key)
# ----------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  count                         = var.enable_key_vault ? 1 : 0
  name                          = "${substr(replace(var.name_prefix, "-", ""), 0, 14)}kv${random_id.suffix.hex}"
  location                      = local.rg_resolved.location
  resource_group_name           = local.rg_resolved.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = var.key_vault_sku
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  enable_rbac_authorization     = true
  public_network_access_enabled = false
  tags                          = local.base_tags

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }
}

resource "azurerm_role_assignment" "kv_admin_self" {
  count                = var.enable_key_vault ? 1 : 0
  scope                = azurerm_key_vault.this[0].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_key" "etcd" {
  count        = var.enable_key_vault ? 1 : 0
  name         = "${var.name_prefix}-etcd-cmk"
  key_vault_id = azurerm_key_vault.this[0].id
  key_type     = "RSA-HSM"
  key_size     = 4096

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = "P1Y"
    notify_before_expiry = "P30D"
  }

  depends_on = [
    azurerm_role_assignment.kv_admin_self,
  ]
}

resource "azurerm_private_dns_zone" "kv" {
  count               = var.enable_key_vault ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.rg_resolved.name
  tags                = local.base_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv" {
  count                 = var.enable_key_vault ? 1 : 0
  name                  = "${var.name_prefix}-kv-link"
  resource_group_name   = local.rg_resolved.name
  private_dns_zone_name = azurerm_private_dns_zone.kv[0].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = local.base_tags
}

resource "azurerm_private_endpoint" "kv" {
  count               = var.enable_key_vault ? 1 : 0
  name                = "${var.name_prefix}-kv-pe"
  location            = local.rg_resolved.location
  resource_group_name = local.rg_resolved.name
  subnet_id           = azurerm_subnet.private_endpoints.id
  tags                = local.base_tags

  private_service_connection {
    name                           = "${var.name_prefix}-kv-psc"
    private_connection_resource_id = azurerm_key_vault.this[0].id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv-dns"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv[0].id]
  }
}
