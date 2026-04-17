# ----------------------------------------------------------------------------
# gcp-gke module - outputs
# ----------------------------------------------------------------------------

output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "GKE cluster location (region)."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "Private endpoint of the GKE master."
  value       = google_container_cluster.this.private_cluster_config[0].private_endpoint
}

output "cluster_ca_certificate" {
  description = "Cluster CA certificate (base64)."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "workload_identity_pool" {
  description = "Workload identity pool for this cluster."
  value       = "${var.project_id}.svc.id.goog"
}

output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.this.name
}

output "subnet_name" {
  description = "Subnet name."
  value       = google_compute_subnetwork.this.name
}

output "artifact_registry_repo" {
  description = "Artifact Registry repository path. Null if disabled."
  value       = var.enable_artifact_registry ? "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.mirror[0].repository_id}" : null
}

output "kms_key_id" {
  description = "CMEK key resource name. Null if KMS is disabled."
  value       = var.enable_kms ? google_kms_crypto_key.etcd[0].id : null
}

output "node_service_account_email" {
  description = "Email of the node service account."
  value       = google_service_account.nodes.email
}
