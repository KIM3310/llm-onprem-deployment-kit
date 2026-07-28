#!/usr/bin/env bash
# Quickstart deploy script for AWS. Runs all steps from the quickstart README.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

: "${REGION:=us-east-1}"
: "${CLUSTER_NAME:=eks-llm-quickstart}"
: "${GPU_INSTANCE_TYPE:=p3.2xlarge}"

echo "==============================================="
echo "  LLM OnPrem Kit — AWS Quickstart Deploy"
echo "==============================================="
echo "  Region:         $REGION"
echo "  Cluster:        $CLUSTER_NAME"
echo "  GPU instance:   $GPU_INSTANCE_TYPE"
echo ""

cd "$REPO_ROOT/terraform"

cat > terraform.tfvars <<EOF
region              = "$REGION"
cluster_name        = "$CLUSTER_NAME"
gpu_instance_type   = "$GPU_INSTANCE_TYPE"
gpu_node_count      = 1
standard_node_count = 3
EOF

echo "[1/5] terraform init"
terraform init -input=false

echo "[2/5] terraform apply"
terraform apply -auto-approve

echo "[3/5] aws eks update-kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

kubectl wait --for=condition=Ready nodes --all --timeout=15m

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
