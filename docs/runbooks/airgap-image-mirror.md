# Runbook - Airgap Image Mirroring

Mirror every container image the `llm-stack` Helm chart uses into a customer-controlled private registry so that pods never pull from a public registry at runtime.

## When to use

- Initial deployment into an airgapped environment.
- Upgrading the image inventory to a new chart version.
- Recovering after a registry outage or prune.

## Prerequisites

- Workstation (call this the _jump host_) with network access to both:
  - The upstream public registries during mirroring (Docker Hub, Quay, ghcr.io, nvcr.io).
  - The customer's private registry for push.
- `skopeo` installed (preferred) or `docker`/`podman`.
- Credentials to push to the destination registry.

If your jump host has no access to the public internet, use a two-hop pattern: an internet-connected workstation pulls images to a tarball via `skopeo copy --dest dir:./images/`, you carry the tarball across the airgap, and a second jump host pushes them into the destination registry.

## Step 1 - Review the image list

```bash
./scripts/airgap-mirror.sh --list
```

Expected output: 11 images, all tag-pinned, no `:latest`.

If any image needs a different version (customer policy, compliance scan finding), edit `IMAGES` in `scripts/airgap-mirror.sh` and open a PR. Never run an install with an unsanctioned image.

## Step 2 - Dry-run

```bash
export TARGET_REGISTRY=registry.customer.internal/llm-stack
./scripts/airgap-mirror.sh --target "$TARGET_REGISTRY" --dry-run
```

Expected: for each image, source and destination are printed, and `(dry-run) skipped` follows. No network calls beyond DNS.

## Step 3 - Authenticate

### skopeo

```bash
export SRC_USER=...
export SRC_PASS=...
export DST_USER=...
export DST_PASS=...
```

The script honors these envs via `skopeo --src-creds` / `--dest-creds`.

### docker / podman

```bash
docker login docker.io
docker login "$TARGET_REGISTRY"
```

## Step 4 - Mirror

```bash
./scripts/airgap-mirror.sh --target "$TARGET_REGISTRY"
```

Expected tail: `All 11 images mirrored successfully to <registry>.`

Typical duration: 15-45 minutes depending on bandwidth and the size of the vLLM base image.

### Resuming after a transient failure

The script retries each `skopeo copy` up to 3 times. If a single image fails after retries, fix the issue (likely auth or network) and rerun the command; already-mirrored images skip quickly because skopeo will compare digests.

## Step 5 - Verify

```bash
# Pick one image to verify manually
crane ls "$TARGET_REGISTRY/vllm-openai"
skopeo inspect "docker://$TARGET_REGISTRY/vllm-openai:v0.4.3" | jq '.Digest, .Labels'
```

Expected: the tag exists and the digest matches the upstream.

### Verify from inside the cluster

```bash
kubectl run vllm-pull-test --rm -it --restart=Never \
  --image="$TARGET_REGISTRY/vllm-openai:v0.4.3" \
  --command -- /bin/true
```

If this completes without `ImagePullBackOff`, the cluster can pull the image via your `imagePullSecrets` configuration.

## Step 6 - Record the manifest

Record the per-image digests you mirrored (from `skopeo inspect`) in the customer's change ticket. These digests become the source of truth if a mirror is ever re-populated.

## Common failures

| Failure | Cause | Action |
|---------|-------|--------|
| `401 Unauthorized` on dest | Missing DST_USER/DST_PASS | Export credentials; re-run |
| `manifest unknown` on upstream | Tag moved upstream | Update the IMAGES list; document the change |
| `x509: certificate signed by unknown authority` | Internal registry uses a private CA | Add the CA to `/etc/docker/certs.d/<registry>/ca.crt` or `/etc/containers/certs.d/` |
| Partial push completes, destination is missing tags | CLI was killed or network dropped | Re-run; skopeo resumes via digest comparison |
| Skopeo `error signing manifest` | Push through an intermediate proxy that modifies content | Bypass the proxy or use `--dest-no-sign` |

## Separate concern: model weights

The mirror script does not transfer model weights. Model weights are handled separately because:

- Weights are often tens of GB per model.
- Licensing usually requires an explicit ACK per model.
- Weights are staged on a PVC, not in the container registry.

Runbook for weights:

1. Download the model from Hugging Face with `huggingface-cli download` on an internet-connected workstation.
2. `tar -czf llama-3.1-8b.tgz llama-3.1-8b-instruct/`, checksum, carry across the airgap.
3. `kubectl cp llama-3.1-8b.tgz <llm-stack-inference-pod>:/models/` (or use an initContainer pull from internal object storage).
4. Set `inference.modelVolume.enabled = true` and `inference.model.modelPath = /models/llama-3.1-8b-instruct` in values-airgap.yaml.

## Security checks

- Confirm digests match between upstream and mirror (prevents an attacker substituting images at the mirror).
- Enable registry-side image scanning (ECR: `scan_on_push = true`; ACR Premium: `quarantinePolicy`; Artifact Registry: `continuousScanning`).
- Apply immutable tag policy at the registry.
- Rotate registry push credentials after the mirror completes.
