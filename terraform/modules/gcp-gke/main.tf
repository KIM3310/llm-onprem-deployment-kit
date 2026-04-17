# ----------------------------------------------------------------------------
# gcp-gke module - main.tf
#
# Provisions:
#   - Custom VPC + regional subnet with secondary ranges for pods/services
#   - Private regional GKE cluster with Workload Identity
#   - System + optional GPU node pool
#   - Dedicated service account for nodes (least-privilege)
#   - Optional CMEK for application-layer secrets
#   - Optional Artifact Registry (Docker) for mirrored images
#   - Private Service Connect is implicit via `enable_private_endpoint`
# ----------------------------------------------------------------------------

locals {
  cluster_name = "${var.name_prefix}-gke"

  base_labels = merge(var.labels, {
    "module" = "gcp-gke"
  })
}

resource "random_id" "suffix" {
  byte_length = 3
}

# ----------------------------------------------------------------------------
# VPC + Subnet
# ----------------------------------------------------------------------------

resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "this" {
  project                  = var.project_id
  name                     = "${var.name_prefix}-subnet"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "${var.name_prefix}-pods"
    ip_cidr_range = var.pod_cidr
  }

  secondary_ip_range {
    range_name    = "${var.name_prefix}-services"
    ip_cidr_range = var.service_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud NAT so private nodes can reach Google APIs that aren't covered by
# private.googleapis.com (or to outbound mirror targets during bootstrap).
resource "google_compute_router" "this" {
  project = var.project_id
  name    = "${var.name_prefix}-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  project                            = var.project_id
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ----------------------------------------------------------------------------
# Node service account (least privilege)
# ----------------------------------------------------------------------------

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-gke-nodes"
  display_name = "GKE node service account for ${local.cluster_name}"
}

resource "google_project_iam_member" "node_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_project_iam_member" "node_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_project_iam_member" "node_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_project_iam_member" "node_artifact_reader" {
  count   = var.enable_artifact_registry ? 1 : 0
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# ----------------------------------------------------------------------------
# KMS for application-layer secrets encryption (CMEK)
# ----------------------------------------------------------------------------

resource "google_kms_key_ring" "this" {
  count    = var.enable_kms ? 1 : 0
  project  = var.project_id
  name     = "${var.name_prefix}-gke-keyring"
  location = var.region
}

resource "google_kms_crypto_key" "etcd" {
  count           = var.enable_kms ? 1 : 0
  name            = "${var.name_prefix}-gke-etcd-cmek"
  key_ring        = google_kms_key_ring.this[0].id
  rotation_period = "7776000s" # 90 days
  purpose         = "ENCRYPT_DECRYPT"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "HSM"
  }

  lifecycle {
    prevent_destroy = false
  }
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_kms_crypto_key_iam_member" "gke_service_agent_encrypter" {
  count         = var.enable_kms ? 1 : 0
  crypto_key_id = google_kms_crypto_key.etcd[0].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.this.number}@container-engine-robot.iam.gserviceaccount.com"
}

# ----------------------------------------------------------------------------
# GKE cluster (regional, private)
# ----------------------------------------------------------------------------

resource "google_container_cluster" "this" {
  provider = google-beta

  project  = var.project_id
  name     = local.cluster_name
  location = var.region

  network    = google_compute_network.this.name
  subnetwork = google_compute_subnetwork.this.name

  min_master_version  = var.kubernetes_version
  deletion_protection = false

  release_channel {
    channel = var.release_channel
  }

  # VPC-native networking via secondary ranges
  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.this.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.this.secondary_ip_range[1].range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = var.master_cidr

    master_global_access_config {
      enabled = true
    }
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  addons_config {
    http_load_balancing {
      disabled = true
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
    dns_cache_config {
      enabled = true
    }
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  dynamic "database_encryption" {
    for_each = var.enable_kms ? [1] : []
    content {
      state    = "ENCRYPTED"
      key_name = google_kms_crypto_key.etcd[0].id
    }
  }

  cluster_autoscaling {
    enabled = false
  }

  # Remove the default node pool; use managed node pools below.
  remove_default_node_pool = true
  initial_node_count       = 1

  resource_labels = local.base_labels

  depends_on = [
    google_kms_crypto_key_iam_member.gke_service_agent_encrypter,
  ]
}

# ----------------------------------------------------------------------------
# System node pool
# ----------------------------------------------------------------------------

resource "google_container_node_pool" "system" {
  project    = var.project_id
  name       = "system"
  location   = var.region
  cluster    = google_container_cluster.this.name
  node_count = null

  autoscaling {
    min_node_count = var.system_node_pool.min_count
    max_node_count = var.system_node_pool.max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.system_node_pool.machine_type
    disk_size_gb    = var.system_node_pool.disk_size_gb
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      "workload" = "system"
    }

    metadata = {
      "disable-legacy-endpoints" = "true"
    }
  }
}

# ----------------------------------------------------------------------------
# GPU node pool
# ----------------------------------------------------------------------------

resource "google_container_node_pool" "gpu" {
  count      = var.gpu_node_pool.enabled ? 1 : 0
  project    = var.project_id
  name       = "gpu"
  location   = var.region
  cluster    = google_container_cluster.this.name
  node_count = null

  autoscaling {
    min_node_count = var.gpu_node_pool.min_count
    max_node_count = var.gpu_node_pool.max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    strategy        = "SURGE"
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.gpu_node_pool.machine_type
    disk_size_gb    = var.gpu_node_pool.disk_size_gb
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.nodes.email

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    guest_accelerator {
      type  = var.gpu_node_pool.accelerator_type
      count = var.gpu_node_pool.accelerator_count

      gpu_driver_installation_config {
        gpu_driver_version = "LATEST"
      }
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      "workload" = "llm-inference"
      "gpu"      = "nvidia"
    }

    dynamic "taint" {
      for_each = var.gpu_node_pool.node_taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    metadata = {
      "disable-legacy-endpoints" = "true"
    }
  }
}

# ----------------------------------------------------------------------------
# Artifact Registry (Docker)
# ----------------------------------------------------------------------------

resource "google_artifact_registry_repository" "mirror" {
  count         = var.enable_artifact_registry ? 1 : 0
  project       = var.project_id
  location      = var.region
  repository_id = "${var.name_prefix}-llm-stack"
  description   = "Mirrored LLM stack images"
  format        = "DOCKER"

  docker_config {
    immutable_tags = true
  }

  labels = local.base_labels
}
