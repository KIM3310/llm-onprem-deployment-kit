# ----------------------------------------------------------------------------
# dev-sandbox example
#
# Smallest possible deployment that still exercises the full code path.
# Uses the cheapest defaults across all three clouds. Intended for
# engineering testing, not customer-facing workloads.
# ----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

module "aks_dev" {
  source = "../../modules/azure-aks"

  name_prefix = "llmkit-dev"
  location    = "koreacentral"

  system_node_pool = {
    vm_size         = "Standard_D2s_v5"
    node_count      = 2
    min_count       = 2
    max_count       = 3
    os_disk_size_gb = 64
  }

  gpu_node_pool = {
    enabled         = false
    vm_size         = "Standard_NC24ads_A100_v4"
    node_count      = 0
    min_count       = 0
    max_count       = 0
    os_disk_size_gb = 64
    node_taints     = []
  }

  enable_key_vault = false
  enable_acr       = false

  tags = {
    "managed-by"  = "terraform"
    "stack"       = "llm-onprem-deployment-kit"
    "environment" = "dev-sandbox"
    "cost-center" = "engineering"
  }
}

output "cluster_name" {
  value       = module.aks_dev.cluster_name
  description = "AKS cluster name."
}
