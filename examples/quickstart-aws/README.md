# Quickstart: AWS Deployment

End-to-end guide to deploying the LLM application stack on Amazon EKS in under an hour.

## Prerequisites

- AWS account with admin access.
- AWS CLI installed and authenticated (`aws configure`).
- Terraform 1.6+ installed.
- Helm 3.12+ installed.
- kubectl installed.
- `eksctl` (optional, for troubleshooting).

Estimated total AWS cost for a week of running this quickstart: $130-200 (1x p3.2xlarge + 3x m5.large + NAT Gateway + Secrets Manager + VPC Endpoints).

## Step 1 — Provision EKS cluster

```bash
cd terraform/
cat > terraform.tfvars <<EOF
region              = "us-east-1"
cluster_name        = "eks-llm-quickstart"
gpu_instance_type   = "p3.2xlarge"
gpu_node_count      = 1
standard_node_count = 3
EOF

terraform init
terraform plan
terraform apply
```

Wait 15-20 minutes for EKS provisioning.

## Step 2 — Configure kubectl

```bash
aws eks update-kubeconfig --name eks-llm-quickstart --region us-east-1
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

## Step 4 — Create AWS Secrets Manager secrets

```bash
INFERENCE_API_KEY=$(openssl rand -hex 32)

aws secretsmanager create-secret \
  --name llm-stack/inference-api-key \
  --secret-string "$INFERENCE_API_KEY"

aws secretsmanager create-secret \
  --name llm-stack/vector-db-password \
  --secret-string "$(openssl rand -hex 16)"
```

## Step 5 — Install the LLM stack Helm chart

```bash
cd ../../helm/llm-stack/

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
IRSA_ROLE_ARN=$(terraform -chdir=../../terraform output -raw external_secrets_role_arn)

helm install llm-stack . \
  --namespace llm-stack --create-namespace \
  --values values.yaml \
  --set externalSecrets.awsSecretsManager.region=us-east-1 \
  --set externalSecrets.awsSecretsManager.irsaRoleArn="$IRSA_ROLE_ARN" \
  --set gpu.nodeSelector."node\.kubernetes\.io/instance-type"=p3.2xlarge

kubectl -n llm-stack get pods -w
```

## Step 6 — Verify the deployment

```bash
kubectl -n llm-stack port-forward svc/llm-stack-gateway 8080:80 &

curl -H "Authorization: Bearer $INFERENCE_API_KEY" \
  http://localhost:8080/v1/completions \
  -d '{"prompt": "Hello, world.", "max_tokens": 20}'
```

## Step 7 — Smoke test

```bash
cd ../../
bash scripts/smoke-test.sh --endpoint http://localhost:8080 --api-key "$INFERENCE_API_KEY"
```

## Step 8 — Teardown (when done)

```bash
helm uninstall -n llm-stack llm-stack
helm uninstall -n external-secrets external-secrets

aws secretsmanager delete-secret --secret-id llm-stack/inference-api-key --force-delete-without-recovery
aws secretsmanager delete-secret --secret-id llm-stack/vector-db-password --force-delete-without-recovery

cd terraform/
terraform destroy
```

## What this quickstart does NOT cover

- Ingress with a real Route 53 domain and ACM certificate.
- Private EKS cluster with no public endpoint.
- VPC endpoints for S3, ECR, and Secrets Manager (essential for airgap; add via Terraform).
- Cluster autoscaler tuning.
- GPU time-slicing for multi-tenant inference.
- PrivateLink for customer-to-cluster connectivity.
- Compliance evidence automation (AWS Audit Manager + Config Rules).

For production, see `docs/runbooks/initial-deploy.md`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| EKS node group fails to launch | GPU quota not increased | Request p-instance quota in AWS Service Quotas console |
| External Secrets can't fetch | IRSA role missing | Check `terraform output external_secrets_role_arn` matches the annotation |
| Inference pod can't pull image | ECR access | Attach AmazonEC2ContainerRegistryReadOnly to node role |
| Slow model download | Cross-region S3 | Put model weights in an S3 bucket in the cluster's region |
| Gateway 502 | vLLM not ready | Check inference pod logs; often a model loading timeout |

## Next steps

- Walk through `docs/runbooks/initial-deploy.md`.
- Enable VPC endpoints and remove the NAT gateway dependency (see `docs/runbooks/airgap-image-mirror.md`).
- Configure AWS CloudWatch Container Insights for observability.
