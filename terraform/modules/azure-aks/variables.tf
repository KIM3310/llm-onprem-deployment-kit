# ----------------------------------------------------------------------------
# azure-aks module - input variables
# ----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix applied to every resource name created by this module. Typically <customer>-<env>, e.g. acme-prod."
  type        = string

  validation {
    condition     = length(var.name_prefix) > 0 && length(var.name_prefix) <= 24
    error_message = "name_prefix must be 1-24 characters to satisfy Azure resource naming constraints."
  }
}

variable "location" {
  description = "Azure region for all resources, e.g. koreacentral, japaneast, southeastasia."
  type        = string
  default     = "koreacentral"
}

variable "resource_group_name" {
  description = "Name of the existing resource group to deploy into. If null, a new one is created with the module name prefix and -rg suffix."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "stack"      = "llm-onprem-deployment-kit"
  }
}

# ----------------------------------------------------------------------------
# Networking
# ----------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "Address space for the VNet hosting the cluster."
  type        = list(string)
  default     = ["10.64.0.0/16"]
}

variable "aks_subnet_cidr" {
  description = "CIDR for the AKS node subnet."
  type        = string
  default     = "10.64.1.0/24"
}

variable "pe_subnet_cidr" {
  description = "CIDR for the private endpoint subnet (used for ACR, Key Vault, etc)."
  type        = string
  default     = "10.64.2.0/27"
}

variable "authorized_ip_ranges" {
  description = "Additional CIDR ranges allowed to reach the API server. Private cluster mode is also enabled; these ranges apply to the public companion endpoint only when public access is enabled."
  type        = list(string)
  default     = []
}

# ----------------------------------------------------------------------------
# Cluster
# ----------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "AKS Kubernetes minor version."
  type        = string
  default     = "1.29"
}

variable "system_node_pool" {
  description = "Configuration for the default (system) node pool."
  type = object({
    vm_size         = string
    node_count      = number
    min_count       = number
    max_count       = number
    os_disk_size_gb = number
  })
  default = {
    vm_size         = "Standard_D4s_v5"
    node_count      = 3
    min_count       = 3
    max_count       = 6
    os_disk_size_gb = 128
  }
}

variable "gpu_node_pool" {
  description = "Configuration for the GPU node pool that hosts vLLM. Set enabled=false to omit."
  type = object({
    enabled         = bool
    vm_size         = string
    node_count      = number
    min_count       = number
    max_count       = number
    os_disk_size_gb = number
    node_taints     = list(string)
  })
  default = {
    enabled         = true
    vm_size         = "Standard_NC24ads_A100_v4"
    node_count      = 1
    min_count       = 1
    max_count       = 4
    os_disk_size_gb = 256
    node_taints     = ["nvidia.com/gpu=true:NoSchedule"]
  }
}

# ----------------------------------------------------------------------------
# Security - Key Vault / private endpoints
# ----------------------------------------------------------------------------

variable "enable_key_vault" {
  description = "Create a Key Vault with a private endpoint and wire it to the cluster."
  type        = bool
  default     = true
}

variable "key_vault_sku" {
  description = "Key Vault SKU - `standard` or `premium` (HSM-backed)."
  type        = string
  default     = "premium"

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "key_vault_sku must be `standard` or `premium`."
  }
}

variable "enable_acr" {
  description = "Create a private Azure Container Registry for image mirroring."
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Retention for the Log Analytics workspace backing OMS/Container Insights."
  type        = number
  default     = 90
}
