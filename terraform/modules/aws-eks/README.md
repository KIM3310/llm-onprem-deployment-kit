# aws-eks

Production-grade EKS module for `llm-onprem-deployment-kit`.

## What this module provisions

- VPC with private subnets (one per AZ), intra subnets for VPC endpoints, and NAT gateways.
- EKS cluster with:
  - Private API endpoint by default (`endpoint_public_access = false`).
  - Envelope encryption of secrets with a customer-managed KMS key.
  - Control-plane logging (API, audit, authenticator, controllerManager, scheduler) to CloudWatch.
  - IRSA (OIDC provider) enabled for workload identity.
  - `authentication_mode = API` (access entries, not aws-auth ConfigMap).
- System and GPU managed node groups.
- VPC Interface Endpoints for ECR, STS, EC2, SSM, CloudWatch Logs, Secrets Manager + S3 Gateway endpoint.
- Optional private ECR repository for image mirroring (`IMMUTABLE` tags, scan on push).

## Usage

```hcl
module "eks" {
  source = "../../"

  name_prefix        = "acme-prod"
  region             = "ap-northeast-2"
  availability_zones = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]

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
```

## Required variables

| Name | Description |
|------|-------------|
| `name_prefix` | 3-32 chars, lowercase + digits + hyphens. |

## GPU instance notes

- Default: `p4d.24xlarge` (8x A100 40GB). For cost-optimized deployments use `p3.8xlarge` (4x V100 16GB).
- For H100: `p5.48xlarge` (8x H100 80GB) where available.
- For smaller models: `g5.12xlarge` (4x A10G 24GB).

## Cost notes

Indicative Seoul (ap-northeast-2) list prices:

- System node group: 3x `m6i.2xlarge` approx USD 730/month.
- GPU node group: 1x `p4d.24xlarge` on-demand approx USD 23,500/month; 1-year reserved approx USD 14,500/month.
- NAT gateways across 3 AZs: approx USD 100/month + data processing.

## Assumptions

- The operator has an IAM principal with permissions to create VPCs, IAM roles, and EKS clusters.
- The module registers the `terraform apply` caller as a cluster admin via `bootstrap_cluster_creator_admin_permissions = true`. Add additional EKS access entries for day-2 operators as needed.
- Image pulling from public registries (Docker Hub, Quay, nvcr.io) is disabled by default because the node groups do not have public egress; use the included ECR repo plus `scripts/airgap-mirror.sh`.
