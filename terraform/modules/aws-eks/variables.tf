# ----------------------------------------------------------------------------
# aws-eks module - input variables
# ----------------------------------------------------------------------------

variable "name_prefix" {
  description = "Prefix applied to every resource name, e.g. acme-prod."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 3-32 lowercase chars / digits / hyphens, starting with a letter."
  }
}

variable "region" {
  description = "AWS region, e.g. ap-northeast-2, ap-southeast-1, ap-northeast-1."
  type        = string
  default     = "ap-northeast-2"
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

variable "vpc_cidr" {
  description = "CIDR for the VPC hosting the cluster."
  type        = string
  default     = "10.68.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets, one per AZ. Must have at least two entries."
  type        = list(string)
  default = [
    "10.68.1.0/24",
    "10.68.2.0/24",
    "10.68.3.0/24",
  ]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "Provide at least two private subnet CIDRs across different AZs."
  }
}

variable "intra_subnet_cidrs" {
  description = "CIDRs for intra (no NAT) subnets used by VPC endpoints and control-plane ENIs."
  type        = list(string)
  default = [
    "10.68.101.0/28",
    "10.68.102.0/28",
    "10.68.103.0/28",
  ]
}

variable "availability_zones" {
  description = "Availability zones to span. Should be the same length as private_subnet_cidrs."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
}

variable "public_endpoint_enabled" {
  description = "Whether the EKS API server has a public endpoint. Default false (private-only)."
  type        = bool
  default     = false
}

variable "public_endpoint_cidrs" {
  description = "If public_endpoint_enabled is true, restrict public access to these CIDRs."
  type        = list(string)
  default     = []
}

# ----------------------------------------------------------------------------
# Cluster
# ----------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.29"
}

variable "system_node_group" {
  description = "System node group sizing."
  type = object({
    instance_types = list(string)
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size_gb   = number
  })
  default = {
    instance_types = ["m6i.2xlarge"]
    desired_size   = 3
    min_size       = 3
    max_size       = 6
    disk_size_gb   = 128
  }
}

variable "gpu_node_group" {
  description = "GPU node group sizing for vLLM."
  type = object({
    enabled        = bool
    instance_types = list(string)
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size_gb   = number
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  })
  default = {
    enabled        = true
    instance_types = ["p4d.24xlarge"]
    desired_size   = 1
    min_size       = 1
    max_size       = 4
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

# ----------------------------------------------------------------------------
# Security and endpoints
# ----------------------------------------------------------------------------

variable "enable_kms" {
  description = "Create a KMS key for EKS secrets encryption and EBS encryption."
  type        = bool
  default     = true
}

variable "enable_ecr" {
  description = "Create a private ECR repository for image mirroring."
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Create Interface VPC endpoints for ECR, S3, STS, EC2, and SSM to avoid public egress."
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Retention in days for EKS control plane logs."
  type        = number
  default     = 90
}
