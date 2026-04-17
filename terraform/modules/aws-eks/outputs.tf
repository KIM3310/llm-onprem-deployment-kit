# ----------------------------------------------------------------------------
# aws-eks module - outputs
# ----------------------------------------------------------------------------

output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint. Private-only by default."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate for kubeconfig."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN (use when granting IRSA roles to workloads)."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "OIDC issuer URL."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets that host the node groups."
  value       = aws_subnet.private[*].id
}

output "intra_subnet_ids" {
  description = "IDs of the intra subnets that host VPC endpoints."
  value       = aws_subnet.intra[*].id
}

output "ecr_repository_url" {
  description = "ECR repository URL for mirrored images. Null if disabled."
  value       = var.enable_ecr ? aws_ecr_repository.mirror[0].repository_url : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for EKS secrets encryption. Null if KMS is disabled."
  value       = var.enable_kms ? aws_kms_key.eks[0].arn : null
}
