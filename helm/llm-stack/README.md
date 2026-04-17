# llm-stack (Helm chart)

Unified Helm chart for deploying the full LLM application stack into a
Kubernetes cluster provisioned by one of the `terraform/modules/*` modules.

## Components

| Component | Default image | Purpose |
|-----------|---------------|---------|
| Inference | `vllm/vllm-openai:v0.4.3` | OpenAI-compatible LLM inference with vLLM |
| Vector DB | `qdrant/qdrant:v1.9.2` | 3-replica Qdrant StatefulSet |
| Gateway | `traefik:v3.0.3` | Ingress + routing |
| Policy | `openpolicyagent/opa:0.65.0-envoy` | OPA sidecar for per-route auth |
| Observability | `otel/opentelemetry-collector-contrib:0.100.0` | OTel collector -> Prom / Loki / Tempo |

External Secrets Operator (not shipped by this chart; assumed installed cluster-wide) is wired via `ExternalSecret` resources.

## Quick install

```bash
helm lint helm/llm-stack
helm upgrade --install llm-stack ./helm/llm-stack \
  --namespace llm-stack --create-namespace \
  --values helm/llm-stack/values.yaml
```

## Airgap install

```bash
helm upgrade --install llm-stack ./helm/llm-stack \
  --namespace llm-stack --create-namespace \
  --values helm/llm-stack/values.yaml \
  --values helm/llm-stack/values-airgap.yaml
```

## Key values

| Key | Default | Description |
|-----|---------|-------------|
| `global.imageRegistry` | `""` | Prefix prepended to all image refs. Set to private registry for airgap. |
| `inference.enabled` | `true` | Deploy vLLM. |
| `inference.model.name` | `meta-llama/Meta-Llama-3.1-8B-Instruct` | HF model id when not using a PVC. |
| `inference.autoscaling.metricName` | `DCGM_FI_DEV_GPU_UTIL` | Custom metric name for GPU-utilization HPA. Requires DCGM exporter. |
| `vectorDb.replicaCount` | `3` | Qdrant replicas. |
| `vectorDb.persistence.size` | `200Gi` | PVC size per replica. |
| `gateway.opa.enabled` | `true` | Attach OPA sidecar to the gateway. |
| `externalSecrets.enabled` | `true` | Render `ExternalSecret` resources. |
| `networkPolicy.enabled` | `true` | Default-deny NetworkPolicies for the namespace. |

See `values.yaml` for the exhaustive list.

## Templates shipped

- `inference-deployment.yaml` - vLLM Deployment with GPU resource requests + liveness/readiness.
- `inference-service.yaml` - ClusterIP Service exposing the OpenAI-compatible port.
- `inference-hpa.yaml` - HPA with an `External` metric (typically DCGM GPU util).
- `inference-pdb.yaml` - PodDisruptionBudget for the inference workload.
- `vector-db-statefulset.yaml` - Qdrant StatefulSet with per-replica PVC template.
- `vector-db-service.yaml` - Headless + client Services for Qdrant.
- `gateway-deployment.yaml` - Traefik Deployment with co-located OPA sidecar.
- `gateway-service.yaml` - Internal LoadBalancer Service.
- `gateway-ingress.yaml` - IngressRoute / Ingress for the gateway hostname.
- `opa-sidecar-configmap.yaml` - Rego policy bundle for OPA.
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
