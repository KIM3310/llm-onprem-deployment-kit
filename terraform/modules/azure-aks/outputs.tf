# ----------------------------------------------------------------------------
# azure-aks module - outputs
# ----------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the resource group containing the cluster."
  value       = local.rg_resolved.name
}

output "cluster_name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_id" {
  description = "Azure resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_private_fqdn" {
  description = "Private FQDN of the API server. Only resolvable within the VNet."
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity. Grant this RBAC over Key Vault secrets, storage, etc."
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federation."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "vnet_id" {
  description = "Azure resource ID of the VNet."
  value       = azurerm_virtual_network.this.id
}

output "aks_subnet_id" {
  description = "Azure resource ID of the AKS node subnet."
  value       = azurerm_subnet.aks.id
}

output "private_endpoint_subnet_id" {
  description = "Azure resource ID of the private endpoint subnet."
  value       = azurerm_subnet.private_endpoints.id
}

output "acr_login_server" {
  description = "Login server FQDN for the provisioned ACR. Null if ACR is disabled."
  value       = var.enable_acr ? azurerm_container_registry.this[0].login_server : null
}

output "key_vault_uri" {
  description = "DNS name for the provisioned Key Vault. Null if Key Vault is disabled."
  value       = var.enable_key_vault ? azurerm_key_vault.this[0].vault_uri : null
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID."
  value       = azurerm_log_analytics_workspace.this.id
}
