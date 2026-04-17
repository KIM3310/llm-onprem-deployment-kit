# ADR 004 - Airgap Image Strategy

## Status

Accepted.

## Context

Enterprise customers in regulated environments (financial services, public sector, defense) routinely deploy third-party workloads into fully airgapped or egress-restricted clouds. The cluster's nodes cannot pull images directly from Docker Hub, Quay, or ghcr.io. Our deployment tooling must stage every container image into a customer-controlled registry before installation.

The sub-problems:

1. **Inventory.** Who decides which images, at which tags, ship with v0.1.0? Where is that list captured?
2. **Transport.** How do operators get images from upstream to the customer's registry, especially when their own workstation may not have internet?
3. **Trust.** How do we prevent an attacker from substituting a malicious image at the mirror?
4. **Maintenance.** How do we bump versions without introducing drift between what's tested and what's deployed?
5. **Size.** vLLM's base image is approximately 6-8 GB; the full inventory is approximately 15-20 GB. Transport over a slow link is non-trivial.

Candidate strategies:

- **A1** - Mirror dynamically at deploy time using a helm pre-install hook.
- **A2** - Mirror manually via a script maintained in this repo; operator runs it once per environment.
- **A3** - Ship a pre-populated OCI layout (`oras`) tarball along with each release, operator imports.
- **A4** - Harbor/Artifactory proxy with on-demand caching.

## Decision

We adopt **strategy A2**: an explicit, operator-invoked shell script (`scripts/airgap-mirror.sh`) that mirrors a fixed image inventory to a target registry.

Key specifics:

- The image inventory is maintained as a top-of-script bash array `IMAGES=(...)` that lists every image, source path, destination sub-path. Each entry is pinned to an explicit tag.
- `skopeo copy --all` is the preferred tool (works without a Docker daemon; handles multi-arch manifests; supports digest verification on both sides).
- Fallback to `docker` or `podman` when skopeo is unavailable.
- `--dry-run` mode prints what would be mirrored without network calls (audit-friendly).
- `--list` mode emits the inventory for procurement review without any other side effects.

The script does **not** mirror model weights. Model weight transport is a separate procedure (`docs/runbooks/airgap-image-mirror.md` has a section on this).

## Consequences

### Positive

- **Inventory is code.** A single file lists every container the kit ships. Security review is a single diff.
- **Operator-friendly.** One command, understandable output, resumable on transient failure (skopeo compares digests).
- **Transport-agnostic.** The operator can run from a jump host with internet access, or use a two-hop pattern (`skopeo copy dir:./bundle` on one host, carry, `skopeo copy dir:./bundle docker://...` on the destination host).
- **Digest verification.** The operator can inspect `skopeo inspect` output post-mirror to confirm that the tag at the destination resolves to the same digest as upstream.
- **Airtight CI story.** Bumping a version requires editing the script; a PR review catches unexpected bumps.

### Negative

- **Manual step.** Airgap mirror is a prerequisite for every install; if skipped, `helm install` fails with `ImagePullBackOff`. Preflight script partially mitigates by testing image resolution.
- **No proxy caching.** If the customer already runs a pull-through proxy (Harbor, Artifactory), they can't leverage it from this script. They can point the `TARGET_REGISTRY` variable at the proxy instead and let the proxy back-fill, but that's not the default path.
- **Script size grows with inventory.** Currently 11 images. At >50 images the bash approach becomes awkward; refactor to a YAML manifest when that threshold is crossed.
- **Tag drift risk.** Upstream moving a tag (e.g. `docker.io/vllm/vllm-openai:v0.4.3`) between the test-time and mirror-time creates a silent swap. Mitigation: always pin to a digest in strict mode (optional flag, not default because digests are less readable in inventories).

### Mitigations

- The CI workflow includes `scripts/airgap-mirror.sh --list` as a smoke test so any change to the inventory is visible in diffs.
- Runbook recommends recording digests at mirror time in the customer's change ticket; divergence from the recorded digest in a subsequent mirror is a security signal.
- Explicit customer approval step for the image inventory (covered in `docs/compliance/airgap-requirements.md`).

## Alternatives Considered

### A1 - Mirror dynamically via helm hooks

```yaml
hooks:
  pre-install:
    image: oras / skopeo
    args: [copy, ...]
```

Rejected. The Kubernetes cluster is typically more locked down than the operator's workstation; giving the cluster outbound access to Docker Hub defeats the point of airgap. Also introduces a dependency on a second container runtime inside the cluster just for mirroring.

### A3 - Ship OCI tarballs with each release

```bash
gh release download v0.1.0 --pattern 'llm-stack-images-*.tar.gz'
tar -xzf llm-stack-images-v0.1.0.tar.gz
skopeo copy oci:./images docker://registry.customer.internal/llm-stack
```

Serious contender. Has the attraction of deterministic content-addressable artifacts. Rejected (for now) because:

- GitHub release artifacts are capped at 2 GB per file; the full inventory is 15-20 GB, requiring multi-part releases.
- Signature verification in the release build pipeline is additional complexity.
- Most customer environments can reach Docker Hub via a controlled egress proxy during the mirror step; requiring full offline tarballs is a heavier lift than the typical customer needs.

We may revisit this strategy if we see a critical mass of customers asking for fully offline transport. The migration path is additive: a new `airgap-mirror.sh --from-oci-layout=./bundle` flag.

### A4 - Harbor / Artifactory proxy with on-demand caching

Rejected as default. Requires customer infrastructure (a proxy registry) that many customers do not run. If they do, they can trivially adapt by pointing `TARGET_REGISTRY` at the proxy; the script does not care about the distinction.

## Operational implications

- Mirror step is the first real work an operator does after Terraform `apply`.
- `scripts/airgap-mirror.sh --list` is an acceptable answer to the customer's "what are you shipping into my environment?" question.
- Inventory changes (image version bumps) require both a script edit and a values file update. We accept this duplication because values.yaml is the source of truth for what gets deployed, and the script is the source of truth for what gets mirrored; they must stay in sync.

## Follow-ups

- Add `--sign` and `--verify` wrappers around cosign once the key management story with the customer is clear.
- Consider extracting the inventory to `images.yaml` if it grows past 20 entries.
- Consider shipping Harbor-compatible `replication.yaml` as an alternate path.
- Pin by digest in strict mode (`--pin-digests` flag) once tooling supports rendering human-readable diffs of digest changes.

## Image inventory (as of v0.1.0)

| Image | Tag | Size (approx) | License |
|-------|-----|--------------:|---------|
| vllm/vllm-openai | v0.4.3 | 6 GB | Apache 2.0 |
| qdrant/qdrant | v1.9.2 | 200 MB | Apache 2.0 |
| traefik | v3.0.3 | 150 MB | MIT |
| openpolicyagent/opa | 0.65.0-envoy | 40 MB | Apache 2.0 |
| otel/opentelemetry-collector-contrib | 0.100.0 | 250 MB | Apache 2.0 |
| hashicorp/vault | 1.16.2 | 500 MB | BSL 1.1 |
| external-secrets/external-secrets | v0.9.18 | 80 MB | Apache 2.0 |
| prometheus/prometheus | v2.52.0 | 300 MB | Apache 2.0 |
| grafana/loki | 2.9.8 | 300 MB | AGPL 3.0 |
| grafana/tempo | 2.5.0 | 250 MB | AGPL 3.0 |
| nvidia/k8s/dcgm-exporter | 3.3.5-3.4.0 | 1 GB | Apache 2.0 |

Customer should review upstream licenses for each image before accepting.
