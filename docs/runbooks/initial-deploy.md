# Runbook - Initial Deployment

Target audience: an on-call SRE with working access to the target cloud account, no prior exposure to this specific project. Allow approximately 90 minutes for a first-time install in a dev environment; 3-6 hours for a fully hardened production install including image mirroring.

## When to use

- First-ever install into a new environment.
- Re-install after a cluster rebuild.
- Install into a disaster-recovery region.

Do **not** use this runbook for in-place upgrades of an existing release; use `upgrade-model.md` or `helm diff upgrade` workflows instead.

## Prerequisites

- Workstation with `terraform >= 1.6`, `helm >= 3.12`, `kubectl >= 1.28`, and the relevant cloud CLI.
- Cloud account access with rights to create VPC/VNet, Kubernetes clusters, KMS keys, and IAM bindings.
- Private container registry and model-weights storage already provisioned (or be prepared to accept the ones provisioned by the Terraform module).
- Target namespace name (default: `llm-stack`).
- Customer's Prometheus / Loki / Tempo endpoints, or explicit confirmation that those integrations are deferred.

## Step 0 - Preflight

```bash
git clone https://github.com/KIM3310/llm-onprem-deployment-kit.git
cd llm-onprem-deployment-kit
make validate
```

Expected output ends with `[OK] All validation checks passed.`

If `validate` fails, stop. Do not proceed with a dirty working copy.

## Step 1 - Provision infrastructure

Pick a cloud. The example below is Azure; substitute `aws` / `gcp` as needed.

```bash
cd terraform/modules/azure-aks/examples/basic
terraform init
terraform plan -out=tfplan -var name_prefix=acme-prod -var location=koreacentral
terraform apply tfplan
```

Expected outputs:

- `cluster_name` - the AKS / EKS / GKE cluster name
- `cluster_private_fqdn` / `cluster_endpoint` - private API server address
- `acr_login_server` / `ecr_repository_url` / `artifact_registry_repo` - registry path
- `key_vault_uri` / `kms_key_arn` / `kms_key_id` - CMK reference

Capture these outputs; they drive the rest of the runbook.

## Step 2 - Get cluster credentials

```bash
# Azure
az aks get-credentials --resource-group acme-prod-rg --name acme-prod-aks --file ./kubeconfig.tmp

# AWS
aws eks update-kubeconfig --region ap-northeast-2 --name acme-prod-eks --kubeconfig ./kubeconfig.tmp

# GCP
gcloud container clusters get-credentials acme-prod-gke --region asia-northeast3 --project acme-prod-ai-1234
```

Verify:

```bash
KUBECONFIG=./kubeconfig.tmp kubectl get nodes
```

Expected: one node per zone for the system pool, plus any GPU nodes.

## Step 3 - Install cluster-wide prerequisites

These are one-time per cluster:

```bash
# NVIDIA device plugin (skip on managed GPU pools that include it, e.g. GKE with driver=LATEST)
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.5/nvidia-device-plugin.yml

# cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.14.5 --set installCRDs=true

# External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --version 0.9.18

# Prometheus Operator (for ServiceMonitors)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

In airgap mode, substitute the chart paths with locally mirrored charts and set image values to your private registry.

## Step 4 - Mirror container images (airgap only)

```bash
export TARGET_REGISTRY=$(terraform output -raw acr_login_server)/llm-stack
./scripts/airgap-mirror.sh --target "$TARGET_REGISTRY" --list   # verify list
./scripts/airgap-mirror.sh --target "$TARGET_REGISTRY" --dry-run
./scripts/airgap-mirror.sh --target "$TARGET_REGISTRY"
```

Expected: `All 11 images mirrored successfully to <registry>.`

See [`airgap-image-mirror.md`](./airgap-image-mirror.md) for troubleshooting.

## Step 5 - Configure Vault and ESO

Create a `ClusterSecretStore` pointed at the customer's Vault. Example (adjust for customer-provided address and auth method):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.internal.customer.example:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "llm-stack"
          serviceAccountRef:
            name: default
            namespace: llm-stack
```

Apply:

```bash
kubectl apply -f clustersecretstore.yaml
```

Confirm:

```bash
kubectl get clustersecretstore vault-backend -o jsonpath='{.status.conditions[0].status}'
```

Expected: `True`.

## Step 6 - Preflight the cluster

```bash
./scripts/preflight-check.sh --namespace llm-stack --gpu
```

Expected summary: `0 fail, 0 warn`. Resolve any warnings before proceeding.

## Step 7 - Install the llm-stack Helm chart

Dev:

```bash
helm upgrade --install llm-stack ./helm/llm-stack \
  --namespace llm-stack --create-namespace \
  --values ./helm/llm-stack/values.yaml \
  --values ./helm/llm-stack/values-dev.yaml \
  --atomic --timeout 10m
```

Airgap:

```bash
helm upgrade --install llm-stack ./helm/llm-stack \
  --namespace llm-stack --create-namespace \
  --values ./helm/llm-stack/values.yaml \
  --values ./helm/llm-stack/values-airgap.yaml \
  --set global.imageRegistry="$(terraform output -raw acr_login_server)/llm-stack" \
  --atomic --timeout 15m
```

## Step 8 - Verify

```bash
kubectl -n llm-stack get pods
./scripts/smoke-test.sh --namespace llm-stack --release llm-stack
```

Expected smoke-test output ends with `All smoke tests passed.`

## Step 9 - Document the installation

Record in the customer ticket:

- Git SHA of this repo used.
- Output values from `terraform output`.
- Helm release version (`helm ls -n llm-stack`).
- Smoke test timestamp and log.

## Rollback

If install fails:

1. `helm -n llm-stack uninstall llm-stack` (Helm was installed with `--atomic`, so this is a safety net).
2. `kubectl -n llm-stack get events --sort-by=.lastTimestamp | tail -50`
3. `./scripts/collect-diag-bundle.sh --namespace llm-stack` and attach to the ticket.
4. Destroy and recreate infrastructure only as a last resort; prefer `terraform apply -target=...` for surgical fixes.

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| Inference pods stuck in `Pending` with `0/3 nodes available` | No GPU node or taints not tolerated | `kubectl describe pod`, check `nvidia.com/gpu` allocatable on nodes |
| Qdrant pods `CrashLoopBackOff` with PVC errors | No default StorageClass or PVC pending | `kubectl get pvc -n llm-stack`; verify StorageClass in `values.yaml` |
| Gateway returns 403 on all requests | OPA policy denying; check policy ConfigMap | `kubectl -n llm-stack logs deploy/llm-stack-gateway -c opa` |
| `ImagePullBackOff` | Missing pull secret or image not mirrored | Verify image exists; check `imagePullSecrets` rendered |
| ExternalSecret stuck in `SecretSyncedError` | Vault auth role not configured | Follow Step 5 and check Vault role policy |
