# Quickstart: Azure Deployment

End-to-end guide to deploying the LLM application stack on Azure AKS in under an hour.

## Prerequisites

- Azure subscription with contributor access.
- Azure CLI installed and authenticated (`az login`).
- Terraform 1.6+ installed.
- Helm 3.12+ installed.
- kubectl installed.

Estimated total Azure cost for a week of running this quickstart: $120-180 (1x GPU node + 3x standard nodes + NAT gateway + Key Vault + Private Endpoints).

## Step 1 — Provision AKS cluster

```bash
cd terraform/
cat > terraform.tfvars <<EOF
subscription_id     = "$(az account show --query id -o tsv)"
resource_group_name = "rg-llm-onprem-quickstart"
location            = "eastus2"
cluster_name        = "aks-llm-quickstart"
gpu_node_count      = 1
standard_node_count = 3
EOF

terraform init
terraform plan
terraform apply
```

Wait 12-18 minutes for AKS provisioning.

## Step 2 — Configure kubectl

```bash
az aks get-credentials \
  --resource-group rg-llm-onprem-quickstart \
  --name aks-llm-quickstart

kubectl get nodes
# Expect: 4 nodes Ready (1 GPU, 3 standard)
```

## Step 3 — Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --set installCRDs=true
```

## Step 4 — Create Azure Key Vault secrets

```bash
KV_NAME=$(terraform output -raw key_vault_name)

# Generate an internal API key for the inference service
INFERENCE_API_KEY=$(openssl rand -hex 32)
az keyvault secret set --vault-name "$KV_NAME" --name inference-api-key --value "$INFERENCE_API_KEY"

# Placeholder for a database URL if your deployment needs one
az keyvault secret set --vault-name "$KV_NAME" --name vector-db-password --value "$(openssl rand -hex 16)"
```

## Step 5 — Install the LLM stack Helm chart

```bash
cd ../../helm/llm-stack/

helm install llm-stack . \
  --namespace llm-stack --create-namespace \
  --values values.yaml \
  --set externalSecrets.azureKeyVault.vaultUrl="https://${KV_NAME}.vault.azure.net/" \
  --set externalSecrets.azureKeyVault.tenantId="$(az account show --query tenantId -o tsv)" \
  --set gpu.nodeSelector."agentpool"=gpu

# Wait for the inference pod to become Ready (model download can take 5-10 min)
kubectl -n llm-stack get pods -w
```

## Step 6 — Verify the deployment

```bash
# Port-forward the gateway
kubectl -n llm-stack port-forward svc/llm-stack-gateway 8080:80 &

# Send a test request
curl -H "Authorization: Bearer $INFERENCE_API_KEY" \
  http://localhost:8080/v1/completions \
  -d '{"prompt": "Hello, world.", "max_tokens": 20}'
```

Expected: a JSON response with a completion.

## Step 7 — Smoke test

```bash
cd ../../
bash scripts/smoke-test.sh --endpoint http://localhost:8080 --api-key "$INFERENCE_API_KEY"
```

Expected: all checks pass (health, tokenizer, inference, latency under 10s).

## Step 8 — Teardown (when done)

```bash
helm uninstall -n llm-stack llm-stack
helm uninstall -n external-secrets external-secrets

kubectl delete namespace llm-stack external-secrets

cd ../../terraform/
terraform destroy
```

## What this quickstart does NOT cover

- Ingress with a real DNS name and TLS certificate (use cert-manager + your DNS provider).
- NetworkPolicy deployment (enable via `--set networkPolicy.enabled=true` in the Helm install).
- Horizontal Pod Autoscaler tuning (defaults are conservative).
- Regional failover (single-region deployment).
- Compliance configurations (SOC2 evidence collection, audit log forwarding).
- Airgap deployment (use `values-airgap.yaml` and the airgap runbook for that).

For production deployment, see `docs/runbooks/initial-deploy.md`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `terraform apply` fails on GPU quota | Azure GPU quota not granted | Request quota in Azure portal; redeploy |
| Inference pod stuck in Pending | GPU node not ready | `kubectl describe node` to confirm GPU driver |
| Inference pod OOM during model download | Node memory too small | Scale to a larger VM size via Terraform `gpu_vm_size` |
| 403 on /v1/completions | API key mismatch | Verify secret synced via ESO; check gateway logs |
| Slow first response | Model loading into GPU memory | Normal on cold start; warm up with a dummy request |

## Next steps

- Walk through `docs/runbooks/initial-deploy.md` for production-grade settings.
- Review `docs/runbooks/rotate-secrets.md` before any real secrets land in Key Vault.
- Run `docs/runbooks/incident-response.md` tabletop exercise with your on-call team.
