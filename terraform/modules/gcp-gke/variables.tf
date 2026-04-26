# ----------------------------------------------------------------------------
# gcp-gke module - input variables
# ----------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to every resource. Lowercase letters, digits, hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 3-32 lowercase chars / digits / hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Primary GCP region."
  type        = string
  default     = "asia-northeast3"
}

variable "zones" {
  description = "Zones within the region. Must have at least two entries for regional clusters."
  type        = list(string)
  default     = ["asia-northeast3-a", "asia-northeast3-b", "asia-northeast3-c"]
}

variable "labels" {
  description = "Labels applied to every resource that supports them."
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "stack"      = "llm-onprem-deployment-kit"
  }
}

# ----------------------------------------------------------------------------
# Networking
# ----------------------------------------------------------------------------

variable "subnet_cidr" {
  description = "Primary CIDR for the node subnet."
  type        = string
  default     = "10.72.0.0/20"
}

variable "pod_cidr" {
  description = "Secondary range for pods (VPC-native)."
  type        = string
  default     = "10.72.128.0/17"
}

variable "service_cidr" {
  description = "Secondary range for services (VPC-native)."
  type        = string
  default     = "10.73.0.0/20"
}

variable "master_cidr" {
  description = "CIDR reserved for the GKE master network (private cluster)."
  type        = string
  default     = "172.16.0.0/28"
}

variable "authorized_networks" {
  description = "Master authorized networks. Empty list means no external access."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

# ----------------------------------------------------------------------------
# Cluster
# ----------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "GKE master version. Use a minor version string (e.g. `1.29`) or full version."
  type        = string
  default     = "1.29"
}

variable "release_channel" {
  description = "GKE release channel: RAPID, REGULAR, STABLE."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = contains(["RAPID", "REGULAR", "STABLE"], var.release_channel)
    error_message = "release_channel must be one of RAPID, REGULAR, STABLE."
  }
}

variable "system_node_pool" {
  description = "System node pool configuration."
  type = object({
    machine_type = string
    disk_size_gb = number
    min_count    = number
    max_count    = number
  })
  default = {
    machine_type = "n2-standard-8"
    disk_size_gb = 128
    min_count    = 3
    max_count    = 6
  }
}

variable "gpu_node_pool" {
  description = "GPU node pool configuration."
  type = object({
    enabled           = bool
    machine_type      = string
    accelerator_type  = string
    accelerator_count = number
    disk_size_gb      = number
    min_count         = number
    max_count         = number
    node_taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  })
  default = {
    enabled           = true
    machine_type      = "a2-highgpu-1g"
    accelerator_type  = "nvidia-tesla-a100"
    accelerator_count = 1
    disk_size_gb      = 256
    min_count         = 1
    max_count         = 4
    node_taints = [
      {
        key    = "nvidia.com/gpu"
        value  = "true"
        effect = "NO_SCHEDULE"
      }
    ]
  }
}

variable "enable_artifact_registry" {
  description = "Create a regional Artifact Registry Docker repository."
  type        = bool
  default     = true
}

variable "enable_kms" {
  description = "Create a Cloud KMS key ring and CMEK for GKE application-layer secrets."
  type        = bool
  default     = true
}
