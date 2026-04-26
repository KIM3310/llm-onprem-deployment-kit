terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.region
}

module "eks" {
  source = "../../"

  name_prefix        = var.name_prefix
  region             = var.region
  availability_zones = var.availability_zones

  gpu_node_group = {
    enabled        = true
    instance_types = ["g5.12xlarge"]
    desired_size   = 1
    min_size       = 1
    max_size       = 3
    disk_size_gb   = 256
    taints = [
      {
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ]
  }

  tags = {
    "managed-by"  = "terraform"
    "stack"       = "llm-onprem-deployment-kit"
    "environment" = var.environment
    "owner"       = "platform-sre"
  }
}

variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
  default     = "llmkit-demo"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-northeast-2"
}

variable "availability_zones" {
  description = "AZs."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
}

variable "environment" {
  type    = string
  default = "dev"
}

output "cluster_name" {
  value       = module.eks.cluster_name
  description = "EKS cluster name."
}

output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "Private API server endpoint."
}

output "ecr_repository_url" {
  value       = module.eks.ecr_repository_url
  description = "ECR repository URL for mirrored images."
}
