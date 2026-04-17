#!/usr/bin/env bash
# Quickstart deploy script for GCP. Runs all steps from the quickstart README.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

: "${PROJECT_ID:=$(gcloud config get-value project)}"
: "${REGION:=us-central1}"
: "${CLUSTER_NAME:=gke-llm-quickstart}"
: "${GPU_MACHINE_TYPE:=a2-highgpu-1g}"

echo "==============================================="
echo "  LLM OnPrem Kit — GCP Quickstart Deploy"
echo "==============================================="
echo "  Project:      $PROJECT_ID"
echo "  Region:       $REGION"
echo "  Cluster:      $CLUSTER_NAME"
echo "  GPU machine:  $GPU_MACHINE_TYPE"
echo ""

cd "$REPO_ROOT/terraform"

cat > terraform.tfvars <<EOF
project_id          = "$PROJECT_ID"
region              = "$REGION"
cluster_name        = "$CLUSTER_NAME"
gpu_machine_type    = "$GPU_MACHINE_TYPE"
gpu_node_count      = 1
standard_node_count = 3
EOF

echo "[1/6] terraform init"
terraform init -input=false

echo "[2/6] terraform apply"
terraform apply -auto-approve

echo "[3/6] gcloud container clusters get-credentials"
gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"

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

echo "[5/6] Seed Secret Manager"
INFERENCE_API_KEY="$(openssl rand -hex 32)"
if ! gcloud secrets describe llm-stack-inference-api-key >/dev/null 2>&1; then
    echo -n "$INFERENCE_API_KEY" | gcloud secrets create llm-stack-inference-api-key \
        --data-file=- --replication-policy=automatic
else
    echo -n "$INFERENCE_API_KEY" | gcloud secrets versions add llm-stack-inference-api-key --data-file=-
fi

if ! gcloud secrets describe llm-stack-vector-db-password >/dev/null 2>&1; then
    echo -n "$(openssl rand -hex 16)" | gcloud secrets create llm-stack-vector-db-password \
        --data-file=- --replication-policy=automatic
fi

SA_EMAIL="$(terraform output -raw external_secrets_sa_email 2>/dev/null || echo "")"

cd "$REPO_ROOT/helm/llm-stack"

echo "[6/6] helm install llm-stack"
helm install llm-stack . \
    --namespace llm-stack --create-namespace \
    --values values.yaml \
    --set "externalSecrets.gcpSecretManager.project=$PROJECT_ID" \
    --set "externalSecrets.gcpSecretManager.serviceAccountEmail=$SA_EMAIL" \
    --wait --timeout 20m

echo ""
echo "==============================================="
echo "  Deploy complete"
echo "==============================================="
echo ""
echo "Inference API key (save this):"
echo "  $INFERENCE_API_KEY"
