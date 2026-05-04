# ----------------------------------------------------------------------------
# airgapped-enterprise example
#
# Reference deployment for a single-cloud, airgapped, production-grade
# environment. Pick the `cloud` variable to select Azure, AWS, or GCP.
# Outputs are normalized across clouds so downstream Helm tooling can
# consume the same contract.
# ----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 4.71"
      configuration_aliases = []
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.43"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 7.30"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.30"
    }
  }
}

# Providers are configured by the caller's terraform.tfvars or environment.

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# ----------------------------------------------------------------------------
# Inputs
# ----------------------------------------------------------------------------

variable "cloud" {
  description = "Which cloud to deploy. One of: azure, aws, gcp."
  type        = string

  validation {
    condition     = contains(["azure", "aws", "gcp"], var.cloud)
    error_message = "cloud must be one of: azure, aws, gcp."
  }
}

variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
  default     = "acme-prod"
}

variable "azure_location" {
  description = "Azure region if cloud=azure."
  type        = string
  default     = "koreacentral"
}

variable "aws_region" {
  description = "AWS region if cloud=aws."
  type        = string
  default     = "ap-northeast-2"
}

variable "gcp_project_id" {
  description = "GCP project if cloud=gcp."
  type        = string
  default     = "example-project"
}

variable "gcp_region" {
  description = "GCP region if cloud=gcp."
  type        = string
  default     = "asia-northeast3"
}

# ----------------------------------------------------------------------------
# Cloud-specific modules (only one runs)
# ----------------------------------------------------------------------------

module "azure" {
  count  = var.cloud == "azure" ? 1 : 0
  source = "../../modules/azure-aks"

  name_prefix = var.name_prefix
  location    = var.azure_location

  gpu_node_pool = {
    enabled         = true
    vm_size         = "Standard_NC24ads_A100_v4"
    node_count      = 2
    min_count       = 2
    max_count       = 6
    os_disk_size_gb = 256
    node_taints     = ["nvidia.com/gpu=true:NoSchedule"]
  }

  tags = {
    "managed-by"  = "terraform"
    "stack"       = "llm-onprem-deployment-kit"
    "environment" = "production"
    "airgap"      = "true"
  }
}

module "aws" {
  count  = var.cloud == "aws" ? 1 : 0
  source = "../../modules/aws-eks"

  name_prefix = var.name_prefix
  region      = var.aws_region

  gpu_node_group = {
    enabled        = true
    instance_types = ["p4d.24xlarge"]
    desired_size   = 2
    min_size       = 2
    max_size       = 6
    disk_size_gb   = 256
    taints = [
      {
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ]
  }
}

module "gcp" {
  count  = var.cloud == "gcp" ? 1 : 0
  source = "../../modules/gcp-gke"

  project_id  = var.gcp_project_id
  name_prefix = var.name_prefix
  region      = var.gcp_region

  gpu_node_pool = {
    enabled           = true
    machine_type      = "a2-highgpu-1g"
    accelerator_type  = "nvidia-tesla-a100"
    accelerator_count = 1
    disk_size_gb      = 256
    min_count         = 2
    max_count         = 6
    node_taints = [
      {
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ]
  }
}

# ----------------------------------------------------------------------------
# Normalized outputs
# ----------------------------------------------------------------------------

output "cloud" {
  value       = var.cloud
  description = "Cloud that was deployed."
}

output "cluster_name" {
  value = coalesce(
    try(module.azure[0].cluster_name, null),
    try(module.aws[0].cluster_name, null),
    try(module.gcp[0].cluster_name, null),
  )
  description = "Cluster name."
}

output "registry_url" {
  value = coalesce(
    try(module.azure[0].acr_login_server, null),
    try(module.aws[0].ecr_repository_url, null),
    try(module.gcp[0].artifact_registry_repo, null),
  )
  description = "Private container registry / repository URL."
}
