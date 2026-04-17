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

echo "[1/6] terraform init"
terraform init -input=false

echo "[2/6] terraform apply"
terraform apply -auto-approve

echo "[3/6] aws eks update-kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

kubectl wait --for=condition=Ready nodes --all --timeout=15m

echo "[4/6] Install External Secrets Operator"
if ! helm status external-secrets -n external-secrets >/dev/null 2>&1; then
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update
    helm install external-secrets external-secrets/external-secrets \
        --namespace external-secrets --create-namespace \
        --set installCRDs=true \
        --wait
fi

echo "[5/6] Seed Secrets Manager"
INFERENCE_API_KEY="$(openssl rand -hex 32)"
aws secretsmanager create-secret \
    --name llm-stack/inference-api-key \
    --secret-string "$INFERENCE_API_KEY" \
    --region "$REGION" >/dev/null 2>&1 || \
    aws secretsmanager update-secret \
        --secret-id llm-stack/inference-api-key \
        --secret-string "$INFERENCE_API_KEY" \
        --region "$REGION" >/dev/null

aws secretsmanager create-secret \
    --name llm-stack/vector-db-password \
    --secret-string "$(openssl rand -hex 16)" \
    --region "$REGION" >/dev/null 2>&1 || true

IRSA_ROLE_ARN="$(terraform output -raw external_secrets_role_arn 2>/dev/null || echo "")"

cd "$REPO_ROOT/helm/llm-stack"

echo "[6/6] helm install llm-stack"
helm install llm-stack . \
    --namespace llm-stack --create-namespace \
    --values values.yaml \
    --set "externalSecrets.awsSecretsManager.region=$REGION" \
    --set "externalSecrets.awsSecretsManager.irsaRoleArn=$IRSA_ROLE_ARN" \
    --wait --timeout 20m

echo ""
echo "==============================================="
echo "  Deploy complete"
echo "==============================================="
echo ""
echo "Inference API key (save this):"
echo "  $INFERENCE_API_KEY"
echo ""
echo "Next: port-forward, test, smoke-test per quickstart README"
