# Quickstart: GCP Deployment

End-to-end guide to deploying the LLM application stack on Google GKE in under an hour.

## Prerequisites

- GCP project with billing enabled and Kubernetes Engine API enabled.
- gcloud CLI installed and authenticated (`gcloud auth login`).
- Terraform 1.6+ installed.
- Helm 3.12+ installed.
- kubectl installed.

Estimated total GCP cost for a week of running this quickstart: $120-180 (1x a2-highgpu-1g + 3x e2-standard-4 + NAT + Secret Manager + Private Service Connect).

## Step 1 — Provision GKE cluster

```bash
cd terraform/
cat > terraform.tfvars <<EOF
project_id          = "$(gcloud config get-value project)"
region              = "us-central1"
cluster_name        = "gke-llm-quickstart"
gpu_machine_type    = "a2-highgpu-1g"
gpu_node_count      = 1
standard_node_count = 3
EOF

terraform init
terraform plan
terraform apply
```

Wait 10-15 minutes for GKE provisioning.

## Step 2 — Configure kubectl

```bash
gcloud container clusters get-credentials gke-llm-quickstart --region us-central1
kubectl get nodes
```

## Step 3 — Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --set installCRDs=true
```

## Step 4 — Create GCP Secret Manager secrets

```bash
INFERENCE_API_KEY=$(openssl rand -hex 32)

echo -n "$INFERENCE_API_KEY" | gcloud secrets create llm-stack-inference-api-key \
  --data-file=- \
  --replication-policy=automatic

echo -n "$(openssl rand -hex 16)" | gcloud secrets create llm-stack-vector-db-password \
  --data-file=- \
  --replication-policy=automatic
```

## Step 5 — Install the LLM stack Helm chart

```bash
cd ../../helm/llm-stack/

SA_EMAIL=$(terraform -chdir=../../terraform output -raw external_secrets_sa_email)

helm install llm-stack . \
  --namespace llm-stack --create-namespace \
  --values values.yaml \
  --set externalSecrets.gcpSecretManager.project=$(gcloud config get-value project) \
  --set externalSecrets.gcpSecretManager.serviceAccountEmail=$SA_EMAIL \
  --set gpu.nodeSelector."cloud\.google\.com/gke-accelerator"=nvidia-tesla-a100

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

gcloud secrets delete llm-stack-inference-api-key --quiet
gcloud secrets delete llm-stack-vector-db-password --quiet

cd terraform/
terraform destroy
```

## What this quickstart does NOT cover

- Private Service Connect to make the cluster egress-controlled.
- Workload Identity Federation for non-GKE callers.
- Cluster autoscaler tuning and surge configurations.
- Cloud Armor at the Ingress.
- GPU time-slicing for multi-tenant inference.
- Regional HA (single-region here).

For production, see `docs/runbooks/initial-deploy.md`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| terraform apply fails on GPU quota | GPU quota not increased | Request in IAM & Admin → Quotas |
| Nodes stay in NotReady with GPU drivers missing | Node taint / auto-installer lag | `kubectl get nodes -o wide`; wait; verify daemonset `nvidia-driver-installer` ran |
| External Secrets sync fails | SA missing IAM binding | `gcloud projects add-iam-policy-binding ... --role=roles/secretmanager.secretAccessor` |
| Gateway 502 | vLLM still loading model | First pull can be 8-10 min for 70B; check inference pod logs |

## Next steps

- Walk through `docs/runbooks/initial-deploy.md`.
- Replace the default Workload Identity binding with a dedicated least-privilege SA.
- Enable Binary Authorization and Pod Security Standards enforcement.
- Integrate with Cloud Logging and Cloud Monitoring for observability.
