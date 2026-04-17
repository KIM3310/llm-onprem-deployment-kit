# ADR 002 - Inference Engine Selection (vLLM vs. TGI)

## Status

Accepted. Revisit when a major 2-3x throughput delta opens between engines, or when a specific customer imposes a hard engine requirement.

## Context

The inference engine is the dominant cost center of a production LLM deployment. Engine choice determines:

- Throughput per GPU (tokens/sec/GPU, directly linked to unit economics).
- Supported model families and quantization formats.
- OpenAI-API compatibility (and therefore how clients integrate).
- Operational features: continuous batching, prefix caching, speculative decoding, multi-LoRA.
- Maintenance burden: frequency of breaking changes, upstream velocity, release discipline.

Candidates evaluated:

- **vLLM** (University of California, Berkeley origin; broad commercial adoption; vLLM Project).
- **TGI** (Text Generation Inference, Hugging Face).
- **Triton Inference Server** with TensorRT-LLM backend (NVIDIA).
- **llama.cpp** (CPU-first, GGUF; server mode).
- **Modular MAX / Mojo-based engines** (commercial, early maturity).

Criteria:

- **Throughput** on Llama-class 7-13B models with continuous batching.
- **OpenAI API compatibility** (clients assume `/v1/chat/completions`).
- **Quantization** (AWQ, GPTQ, fp8).
- **Airgap-friendliness** (no mandatory phone-home, pinnable images).
- **Docs and community** quality for operator self-service.
- **License**: Apache 2.0 or similar permissive preferred.
- **Multi-GPU tensor parallelism** for larger models.

## Decision

We adopt **vLLM** (`vllm/vllm-openai`) as the default inference engine.

- Default image: `vllm/vllm-openai:v0.4.3`.
- The chart invokes the OpenAI-compatible server: `python3 -m vllm.entrypoints.openai.api_server`.
- Configuration surface: `inference.model.name`, `inference.model.modelPath`, `inference.model.maxModelLen`, `inference.model.quantization`, plus `inference.args.extra` for passthrough flags.

vLLM is the default, but the chart does not force it. `values.yaml` keeps the engine-agnostic fields (image, args, env, ports, resources) so operators can swap in TGI or Triton by overriding `inference.image` and `inference.args.extra`.

## Consequences

### Positive

- **Highest general-purpose throughput.** vLLM's continuous batching and PagedAttention consistently post the best tokens/sec on Llama-class models in public benchmarks.
- **OpenAI-compatible API.** Drop-in for any client that targets the OpenAI SDK; zero application-side changes for `stage-pilot`, `enterprise-llm-adoption-kit`, or third-party tooling.
- **Active, disciplined releases.** Monthly minor versions, patch releases for CVEs, clear deprecation policy.
- **Strong quantization support.** AWQ, GPTQ, fp8, GGUF (via llama.cpp backend) and increasingly INT8/FP8 with H100.
- **Multi-LoRA.** vLLM supports serving multiple LoRA adapters from a single base model; important for tenancy patterns in enterprise deployments.
- **Python-only runtime.** Image inventory is a single wheel plus CUDA; easy to mirror and sign.

### Negative

- **Python ecosystem fragility.** Breaking changes in upstream model libraries (transformers, flash-attn) periodically force vLLM version bumps that are not strictly backward-compatible. The upgrade runbook addresses this.
- **GPU memory overhead.** vLLM's KV-cache allocation is eager; poorly tuned `--max-model-len` can cause OOM at pod start. Default in values.yaml is 8192, conservative for A100 40GB.
- **Startup time.** Model load + cuBLAS warmup is 2-5 minutes. Autoscaling latency is dominated by this.
- **Observability.** vLLM exposes Prometheus metrics on the same port as the API; scraping is straightforward but the metric names change between minor versions; dashboards drift.

### Mitigations

- `probes.startupSeconds` defaults to 600 to cover cold start.
- Image tag is pinned; upgrades are explicit operator actions via `upgrade-model.md`.
- HPA uses DCGM GPU utilization (`DCGM_FI_DEV_GPU_UTIL`) as the scaling metric rather than vLLM-specific names, insulating scaling policy from engine version churn.
- Documentation points operators at vLLM's `/metrics` endpoint so they can author engine-specific alerts if they wish.

## Alternatives Considered

### TGI (Text Generation Inference)

Strong alternative, especially for customers deeply in the Hugging Face ecosystem.

**Why not default:**

- Historically trails vLLM on raw throughput for Llama-class models. The gap has narrowed with TGI v2, but vLLM remains ahead in public benchmarks for continuous-batching scenarios.
- License change in TGI 1.x (HFOIL v1, a non-OSI license) caused concern for enterprise procurement. Reverted later, but it was a signal.
- Startup-time gap is similar to vLLM.
- OpenAI-compatible API shim available but not first-class.

**When to prefer TGI:**

- Customer has standardized on Hugging Face Inference Endpoints semantics.
- Specific model family is supported better by TGI (some Mistral and Falcon variants have had earlier support on TGI).
- Customer has an existing TGI deployment and wants parity with it.

To swap to TGI: override `inference.image.repository` to `ghcr.io/huggingface/text-generation-inference`, drop vLLM-specific args, and re-render. Mirror the TGI image via `airgap-mirror.sh` with an updated IMAGES list.

### Triton + TensorRT-LLM

Highest absolute throughput for compiled models on NVIDIA hardware.

**Why not default:**

- Model compilation (TensorRT engine build) adds a separate pre-processing step per model per hardware class. This does not fit a "helm upgrade" workflow cleanly.
- Quantization support is powerful but more operationally complex.
- Triton's configuration surface is large and Kubernetes-unfriendly out-of-the-box.
- OpenAI API is bolted on via a custom Python frontend; not canonical.

**When to prefer:** customers who have standardized on Triton already, or workloads where the last 20-30% of throughput is worth the operational tax.

### llama.cpp

Terrific for edge and CPU-only workloads.

**Why not default:** this kit assumes production GPU deployment. Throughput per A100 is several multiples higher on vLLM than on llama.cpp with CUDA backend.

### Commercial engines

(Modular MAX, MosaicML Inference, etc.) License constraints and immature airgap stories make these non-starters for the target audience as of the decision date.

## Operational implications

- **Tokenizer management.** vLLM bundles tokenizers; no separate deployment needed.
- **Model lifecycle.** `upgrade-model.md` describes the procedure.
- **Security posture.** `--trust-remote-code=false` is set in values.yaml to prevent a malicious HF model from executing arbitrary code at load.
- **Privacy.** `--disable-log-requests` is set to keep request content out of logs.

## Open questions / follow-ups

- Evaluate vLLM's speculative decoding for >50% latency reduction on long-context chat.
- Consider multi-LoRA serving for tenant isolation on shared GPU pools.
- Track Triton TRT-LLM for the H100 generation; compilation cost may become tolerable with a model-bakery CI pipeline.
