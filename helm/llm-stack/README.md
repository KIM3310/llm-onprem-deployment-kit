# llm-stack (Helm chart)

Customer-owned pilot baseline for deploying a narrow private LLM runtime into a
Kubernetes cluster. A rendered chart is not a production-readiness claim.

## Components

| Component | Default image | Purpose |
|-----------|---------------|---------|
| Inference | `vllm/vllm-openai:v0.4.3` | OpenAI-compatible LLM inference with vLLM |
| Vector DB | `qdrant/qdrant:v1.9.2` | Single-node Qdrant StatefulSet |
| Gateway | `traefik:v3.0.3` | TLS termination and file-provider routing to vLLM |
| Observability | `otel/opentelemetry-collector-contrib:0.100.0` | OTel collector -> Prom / Loki / Tempo |

vLLM can require one API key from an existing Kubernetes Secret. This is not
end-user identity, tenant authorization, quotas, or rate limiting.

External Secrets Operator is optional and not shipped by this chart. When
enabled, the customer must install ESO and create the referenced `SecretStore`
or `ClusterSecretStore`.

## Quick install

```bash
helm lint helm/llm-stack
kubectl create namespace llm-stack
kubectl -n llm-stack create secret generic llm-stack-inference-api-key \
  --from-literal=api-key="$(openssl rand -hex 32)"
# Also create the customer-approved llm-stack-tls Secret.
helm upgrade --install llm-stack ./helm/llm-stack \
  --namespace llm-stack \
  --values helm/llm-stack/values.yaml
```

## Airgap install

```bash
helm upgrade --install llm-stack ./helm/llm-stack \
  --namespace llm-stack --create-namespace \
  --values helm/llm-stack/values.yaml \
  --values helm/llm-stack/values-airgap.yaml
```

The air-gap overlay requires mirrored images and model weights, a customer
secret store, TLS, approved ingress sources, storage, observability endpoints,
and an acceptance plan. It is not turnkey.

## Key values

| Key | Default | Description |
|-----|---------|-------------|
| `global.imageRegistry` | `""` | Prefix prepended to all image refs. Set to private registry for airgap. |
| `inference.enabled` | `true` | Deploy vLLM. |
| `inference.auth.enabled` | `true` | Require the API key referenced by `inference.auth.existingSecret`. |
| `inference.model.name` | `meta-llama/Meta-Llama-3.1-8B-Instruct` | HF model id when not using a PVC. |
| `inference.autoscaling.metricName` | `DCGM_FI_DEV_GPU_UTIL` | Custom metric name for GPU-utilization HPA. Requires DCGM exporter. |
| `vectorDb.replicaCount` | `1` | Must remain `1`; distributed consensus is not configured. |
| `vectorDb.persistence.size` | `200Gi` | PVC size per replica. |
| `gateway.tls.enabled` | `true` | Mount the customer TLS Secret and expose the HTTPS router. |
| `externalSecrets.enabled` | `false` | Render `ExternalSecret` resources only after the customer store exists. |
| `networkPolicy.enabled` | `false` | Air-gap values enable default-deny with approved ingress sources. |

See `values.yaml` for the exhaustive list.

## Templates shipped

- `inference-deployment.yaml` - vLLM Deployment with GPU resource requests + liveness/readiness.
- `inference-service.yaml` - ClusterIP Service exposing the OpenAI-compatible port.
- `inference-hpa.yaml` - HPA with an `External` metric (typically DCGM GPU util).
- `inference-pdb.yaml` - PodDisruptionBudget for the inference workload.
- `vector-db-statefulset.yaml` - Qdrant StatefulSet with per-replica PVC template.
- `vector-db-service.yaml` - Headless + client Services for Qdrant.
- `gateway-dynamic-configmap.yaml` - Traefik route to the vLLM Service.
- `gateway-deployment.yaml` - Traefik reverse-proxy Deployment.
- `gateway-service.yaml` - Internal LoadBalancer Service.
- `gateway-ingress.yaml` - Optional standard Ingress for a customer controller.
- `otel-collector-configmap.yaml` - OpenTelemetry collector config.
- `servicemonitor.yaml` - Prometheus Operator ServiceMonitor.
- `networkpolicy.yaml` - Namespace-level default-deny + explicit allows.
- `poddisruptionbudget.yaml` - PDB for the vector DB.
- `externalsecret.yaml` - ExternalSecret resources for ESO.
- `NOTES.txt` - Post-install guidance.

## Chart development

- `helm lint helm/llm-stack` must stay clean.
- `helm template llm-stack helm/llm-stack > /tmp/r.yaml && kubeconform -kubernetes-version 1.28.0 /tmp/r.yaml` should pass.
- PRs that add a template must also update `values.yaml` with commented defaults.
- `tests/helm-runtime-contract-test.sh` must prove the gateway route, API-key
  secret reference, single-node state gate, and air-gap network paths.
