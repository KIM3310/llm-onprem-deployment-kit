#!/usr/bin/env bash
# Quickstart deploy script for Azure. Runs all steps from the quickstart README.
# Use for testing or demos; for production follow the runbook.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

: "${SUBSCRIPTION_ID:=$(az account show --query id -o tsv)}"
: "${RESOURCE_GROUP:=rg-llm-onprem-quickstart}"
: "${LOCATION:=eastus2}"
: "${CLUSTER_NAME:=aks-llm-quickstart}"

echo "==============================================="
echo "  LLM OnPrem Kit — Azure Quickstart Deploy"
echo "==============================================="
echo "  Subscription:  $SUBSCRIPTION_ID"
echo "  Resource grp:  $RESOURCE_GROUP"
echo "  Location:      $LOCATION"
echo "  Cluster:       $CLUSTER_NAME"
echo ""

cd "$REPO_ROOT/terraform"

cat > terraform.tfvars <<EOF
subscription_id     = "$SUBSCRIPTION_ID"
resource_group_name = "$RESOURCE_GROUP"
location            = "$LOCATION"
cluster_name        = "$CLUSTER_NAME"
gpu_node_count      = 1
standard_node_count = 3
EOF

echo "[1/6] terraform init"
terraform init -input=false

echo "[2/6] terraform apply"
terraform apply -auto-approve

echo "[3/6] az aks get-credentials"
az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --overwrite-existing

kubectl wait --for=condition=Ready nodes --all --timeout=10m

echo "[4/6] Install External Secrets Operator"
if ! helm status external-secrets -n external-secrets >/dev/null 2>&1; then
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update
    helm install external-secrets external-secrets/external-secrets \
        --namespace external-secrets --create-namespace \
        --set installCRDs=true \
        --wait
fi

KV_NAME="$(terraform output -raw key_vault_name 2>/dev/null || echo "")"
if [[ -z "$KV_NAME" ]]; then
    echo "ERROR: Key Vault name not found in Terraform outputs" >&2
    exit 1
fi

echo "[5/6] Seed Key Vault with secrets"
INFERENCE_API_KEY="$(openssl rand -hex 32)"
az keyvault secret set --vault-name "$KV_NAME" --name inference-api-key --value "$INFERENCE_API_KEY" >/dev/null
az keyvault secret set --vault-name "$KV_NAME" --name vector-db-password --value "$(openssl rand -hex 16)" >/dev/null

cd "$REPO_ROOT/helm/llm-stack"

echo "[6/6] helm install llm-stack"
helm install llm-stack . \
    --namespace llm-stack --create-namespace \
    --values values.yaml \
    --set "externalSecrets.azureKeyVault.vaultUrl=https://${KV_NAME}.vault.azure.net/" \
    --set "externalSecrets.azureKeyVault.tenantId=$(az account show --query tenantId -o tsv)" \
    --wait --timeout 20m

echo ""
echo "==============================================="
echo "  Deploy complete"
echo "==============================================="
echo ""
echo "Next:"
echo "  1. Port-forward the gateway:"
echo "     kubectl -n llm-stack port-forward svc/llm-stack-gateway 8080:80"
echo ""
echo "  2. Test the inference endpoint:"
echo "     curl -H \"Authorization: Bearer $INFERENCE_API_KEY\" http://localhost:8080/v1/completions"
echo ""
echo "  3. Run the smoke test:"
echo "     bash $REPO_ROOT/scripts/smoke-test.sh --endpoint http://localhost:8080 --api-key $INFERENCE_API_KEY"
echo ""
echo "Inference API key (save this):"
echo "  $INFERENCE_API_KEY"
