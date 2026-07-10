# Runbook - Upgrade the Inference Model

Zero-downtime model upgrade. The llm-stack chart supports this via a rolling update of the inference Deployment with a single replica surge and a minAvailable=1 PodDisruptionBudget.

## When to use

- Model version bump (e.g. Llama 3.1 -> 3.2).
- Engine version bump (vLLM 0.4.x -> 0.5.x).
- Quantization change (fp16 -> awq-int4).

## Prerequisites

- New model weights already staged on the model PVC at a distinct path, or a new container image already mirrored.
- Confirmed that the new model is license-compatible with the customer's contract.
- A defined rollback version and validated rollback path.

## Compatibility matrix

Before upgrading, verify:

| Axis | Check |
|------|-------|
| vLLM version supports the model | See vLLM release notes |
| Model context length fits the allocated KV cache | `--max-model-len` in values.yaml |
| GPU memory sufficient for the new model at the target batch size | `resources.limits.nvidia.com/gpu` and node type |
| Quantization supported (if used) | Engine + hardware combination |

## Procedure - Model weight change

1. **Stage new weights on the PVC.**

   If weights are on a shared RWX PVC (e.g. NFS, Azure Files), copy the new directory in place:

   ```bash
   kubectl -n llm-stack exec -it llm-stack-model-copier -- \
     sh -c 'cp -r /src/llama-3.2-8b-instruct /models/'
   ```

   Confirm:

   ```bash
   kubectl -n llm-stack exec -it deploy/llm-stack-inference -c vllm -- \
     ls /models/llama-3.2-8b-instruct
   ```

2. **Render the new configuration.**

   ```bash
   helm diff upgrade llm-stack ./helm/llm-stack \
     --namespace llm-stack \
     --values ./helm/llm-stack/values.yaml \
     --values ./helm/llm-stack/values-airgap.yaml \
     --set inference.model.modelPath=/models/llama-3.2-8b-instruct
   ```

3. **Apply.**

   ```bash
   helm upgrade llm-stack ./helm/llm-stack \
     --namespace llm-stack \
     --values ./helm/llm-stack/values.yaml \
     --values ./helm/llm-stack/values-airgap.yaml \
     --set inference.model.modelPath=/models/llama-3.2-8b-instruct \
     --atomic --timeout 20m
   ```

   The rollout replaces one pod at a time with `maxSurge=1, maxUnavailable=0`. The PodDisruptionBudget ensures at least `minAvailable=1` pod is always Ready.

4. **Verify.**

   ```bash
   kubectl -n llm-stack rollout status deployment/llm-stack-inference
   ./scripts/smoke-test.sh --namespace llm-stack
   ```

   Also verify the served model name:

   ```bash
   kubectl -n llm-stack port-forward svc/llm-stack-inference 18000:8000 &
   curl -s http://localhost:18000/v1/models | jq '.data[].id'
   ```

## Procedure - Engine version change

When bumping vLLM (e.g. v0.4.3 -> v0.5.1):

1. Update `inference.image.tag` in your values override, or on the CLI with `--set inference.image.tag=v0.5.1`.
2. Mirror the new image first: `./scripts/airgap-mirror.sh --target ...` with an updated `IMAGES` list.
3. `helm diff upgrade` and review the Deployment changes carefully: check for new CLI flags, changed env vars.
4. Apply as above.

## Procedure - Quantization change

1. Confirm the new quantization is supported: `--quantization` flag combinations.
2. Set `inference.model.quantization` to `awq` / `gptq` / `fp8` in values.
3. Confirm GPU memory budget. Quantization reduces it significantly; you can often scale down `resources.requests.nvidia.com/gpu` from a whole A100 to a fraction via MIG if enabled.
4. Apply.

## Canary pattern (optional)

For high-risk upgrades, deploy a second Helm release alongside the current one at a different name and route a percentage of traffic to it via the gateway:

```bash
helm upgrade --install llm-stack-canary ./helm/llm-stack \
  --namespace llm-stack \
  --values ./helm/llm-stack/values.yaml \
  --set fullnameOverride=llm-stack-canary \
  --set inference.model.modelPath=/models/llama-3.2-8b-instruct \
  --set inference.replicaCount=1
```

Configure the gateway's Traefik weight split (TraefikService `weighted` servers) or an ingress-level split. Promote when canary metrics are green for at least 30 minutes.

## Verification checklist

- [ ] Smoke test passes.
- [ ] HPA shows healthy GPU utilization within expected range.
- [ ] OTel metrics show p50/p95 latency comparable to baseline.
- [ ] Error budget unchanged over the next hour.
- [ ] No new errors in OPA decision logs.

## Rollback

```bash
helm -n llm-stack history llm-stack
helm -n llm-stack rollback llm-stack <previous-revision>
```

Allow 5-10 minutes for the rollback; verify with smoke test.

If the old model weights were deleted during staging, rollback requires re-staging them. Do not delete old weight directories until at least 48 hours after the upgrade.

## Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| New pods OOMKilled at model load | GPU or RAM too small for new model | Raise resource limits and GPU type |
| New pods fail readiness with "unknown argument" | vLLM version renamed a flag | Adjust `args.extra` in values |
| Throughput drop after quantization change | Different kernel path, BF16 to AWQ | Benchmark before rollout; consider fp8 on H100 |
| Gateway returns 502 intermittently during rollout | Readiness probe too aggressive | Increase `probes.readiness.initialDelaySeconds` |
