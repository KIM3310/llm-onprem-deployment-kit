terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.71"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

module "aks" {
  source = "../../"

  name_prefix = var.name_prefix
  location    = var.location

  vnet_address_space = ["10.64.0.0/16"]
  aks_subnet_cidr    = "10.64.1.0/24"
  pe_subnet_cidr     = "10.64.2.0/27"

  gpu_node_pool = {
    enabled         = true
    vm_size         = "Standard_NC24ads_A100_v4"
    node_count      = 1
    min_count       = 1
    max_count       = 4
    os_disk_size_gb = 256
    node_taints     = ["nvidia.com/gpu=true:NoSchedule"]
  }

  tags = {
    "managed-by"  = "terraform"
    "stack"       = "llm-onprem-deployment-kit"
    "environment" = var.environment
    "owner"       = "platform-sre"
  }
}

variable "name_prefix" {
  description = "Resource name prefix (e.g. acme-prod)."
  type        = string
  default     = "llmkit-demo"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "koreacentral"
}

variable "environment" {
  description = "Environment label applied to tags."
  type        = string
  default     = "dev"
}

output "cluster_name" {
  value       = module.aks.cluster_name
  description = "AKS cluster name."
}

output "cluster_private_fqdn" {
  value       = module.aks.cluster_private_fqdn
  description = "Private FQDN of the API server."
}

output "acr_login_server" {
  value       = module.aks.acr_login_server
  description = "ACR login server FQDN."
}

output "key_vault_uri" {
  value       = module.aks.key_vault_uri
  description = "Key Vault URI."
}
