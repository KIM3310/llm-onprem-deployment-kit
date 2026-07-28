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

echo "[1/5] terraform init"
terraform init -input=false

echo "[2/5] terraform apply"
terraform apply -auto-approve

echo "[3/5] gcloud container clusters get-credentials"
gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION" --project "$PROJECT_ID"

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
echo "The evaluation API key is stored in the llm-stack-inference-api-key Secret."
echo "Do not print it into shared logs. Run the smoke test, then rotate or delete it at teardown."
