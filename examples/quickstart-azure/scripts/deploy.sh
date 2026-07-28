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

echo "[1/5] terraform init"
terraform init -input=false

echo "[2/5] terraform apply"
terraform apply -auto-approve

echo "[3/5] az aks get-credentials"
az aks get-credentials \
    --resource-group "$RESOURCE_GROUP" \
    --name "$CLUSTER_NAME" \
    --overwrite-existing

kubectl wait --for=condition=Ready nodes --all --timeout=10m

echo "[4/5] Create evaluation API-key Secret"
INFERENCE_API_KEY="$(openssl rand -hex 32)"
kubectl create namespace llm-stack --dry-run=client -o yaml | kubectl apply -f -
kubectl -n llm-stack create secret generic llm-stack-inference-api-key \
    --from-literal="api-key=$INFERENCE_API_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

cd "$REPO_ROOT/helm/llm-stack"

echo "[5/5] helm install evaluation stack"
helm install llm-stack . \
    --namespace llm-stack \
    --values values.yaml \
    --set "gateway.tls.enabled=false" \
    --set "gateway.traefik.service.type=ClusterIP" \
    --wait --timeout 20m

echo ""
echo "==============================================="
echo "  Deploy complete"
echo "==============================================="
echo ""
echo "Next:"
echo "  Run: bash $REPO_ROOT/scripts/smoke-test.sh --namespace llm-stack --release llm-stack"
echo "The smoke test reads the API key from the customer-owned Kubernetes Secret without printing it."
echo "Rotate or delete the key at teardown."
