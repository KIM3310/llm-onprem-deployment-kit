# gcp-gke

Production-grade GKE module for `llm-onprem-deployment-kit`.

## What this module provisions

- Custom-mode VPC with a single regional subnet and VPC-native secondary ranges for pods and services.
- Cloud NAT + router for private nodes.
- Private regional GKE cluster:
  - `enable_private_endpoint = true` (no public master endpoint)
  - Workload Identity enabled (`workload_pool = <project>.svc.id.goog`)
  - Network Policy enabled (Calico)
  - Binary Authorization enforce mode
  - Shielded Nodes with Secure Boot and integrity monitoring
  - VPC Flow Logs on the node subnet
  - Intranode visibility via Dataplane v2 / GKE DNS cache
- System and optional GPU node pool with autoscaling and `COS_CONTAINERD`.
- Dedicated least-privilege node service account.
- Optional CMEK (HSM-backed) for application-layer secrets.
- Optional Artifact Registry Docker repo with `immutable_tags = true`.

## Usage

```hcl
module "gke" {
  source = "../../"

  project_id  = "acme-prod-ai-1234"
  name_prefix = "acme-prod"
  region      = "asia-northeast3"
  zones       = ["asia-northeast3-a", "asia-northeast3-b", "asia-northeast3-c"]

  gpu_node_pool = {
    enabled          = true
    machine_type     = "a2-highgpu-1g"
    accelerator_type = "nvidia-tesla-a100"
    accelerator_count = 1
    disk_size_gb     = 256
    min_count        = 1
    max_count        = 4
    node_taints = [
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
| `project_id` | Target GCP project ID |
| `name_prefix` | 3-32 lowercase chars, digits, hyphens |

## GPU notes

- Default: `a2-highgpu-1g` (1x A100 40GB).
- For higher throughput: `a2-ultragpu-1g` (1x A100 80GB) or `a2-highgpu-8g` (8x A100 40GB).
- For H100: `a3-highgpu-8g` where available (Seoul and Tokyo have limited capacity; always confirm with Google sales).
- `gpu_driver_version = "LATEST"` lets GKE auto-install the NVIDIA driver.

## Connecting from a local workstation

Because the endpoint is private, operators must either:
- Connect from a VM in the same VPC with `gcloud container clusters get-credentials`, or
- Use Identity-Aware Proxy (IAP) through a Cloud IAP tunnel.

See [`docs/runbooks/initial-deploy.md`](../../../docs/runbooks/initial-deploy.md) for the IAP bastion pattern.

## Cost notes

Indicative Seoul (asia-northeast3) list prices:

- System node pool: 3x `n2-standard-8` approx USD 560/month.
- GPU node pool: 1x `a2-highgpu-1g` approx USD 2,900/month on-demand.
- Cloud NAT: approx USD 60/month + data processing.
