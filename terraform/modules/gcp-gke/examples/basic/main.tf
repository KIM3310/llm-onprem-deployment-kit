terraform {
  required_version = ">= 1.6.0"

  required_providers {
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

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

module "gke" {
  source = "../../"

  project_id  = var.project_id
  name_prefix = var.name_prefix
  region      = var.region
  zones       = var.zones

  gpu_node_pool = {
    enabled           = true
    machine_type      = "a2-highgpu-1g"
    accelerator_type  = "nvidia-tesla-a100"
    accelerator_count = 1
    disk_size_gb      = 256
    min_count         = 1
    max_count         = 3
    node_taints = [
      {
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ]
  }

  labels = {
    "managed-by"  = "terraform"
    "stack"       = "llm-onprem-deployment-kit"
    "environment" = var.environment
  }
}

variable "project_id" {
  description = "Target GCP project ID."
  type        = string
}

variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
  default     = "llmkit-demo"
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "asia-northeast3"
}

variable "zones" {
  description = "GCP zones."
  type        = list(string)
  default     = ["asia-northeast3-a", "asia-northeast3-b", "asia-northeast3-c"]
}

variable "environment" {
  type    = string
  default = "dev"
}

output "cluster_name" {
  value       = module.gke.cluster_name
  description = "GKE cluster name."
}

output "cluster_endpoint" {
  value       = module.gke.cluster_endpoint
  description = "Private endpoint of the GKE master."
}

output "artifact_registry_repo" {
  value       = module.gke.artifact_registry_repo
  description = "Artifact Registry repository path."
}
