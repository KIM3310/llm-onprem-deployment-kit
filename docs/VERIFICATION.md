# LLM On-Prem Deployment Kit — implementation and verification

Reviewed 2026-09-07. The repository and linked tests define the evidence; a preview alone does not establish production readiness.

### TLS changes routing behavior

When TLS is enabled, ordinary HTTP requests redirect to HTTPS; health probes remain available. The development overlay can explicitly disable TLS.

### Use the real chart for deployment checks

The fixture preserves the inference entrypoint and secret argument contract while replacing the expensive model process with a named synthetic protocol fixture.

### Keep reproducible provider selections

Terraform lockfiles are retained; the clean target removes disposable caches without deleting the selected provider locks.

## Reproduce

```sh
make verify
make validate
# Disposable Docker/kind environment only:
kind create cluster --name portfolio-smoke
KIND_CLUSTER_NAME=portfolio-smoke bash tests/cluster-smoke.sh
```

Terraform formatting, initialization and validation pass in all 8 module/example directories. Default, development and airgap Helm lint/render contracts and ShellCheck pass. The Kubernetes workflow deploys the chart with real Traefik/TLS and an explicitly synthetic inference protocol fixture; its artifact lists the checks performed.

## Boundaries

No GPU inference, model-quality benchmark, customer cloud provisioning, network-policy enforcement, Qdrant persistence or offline airgap installation is claimed. The kind fixture proves chart/process/network wiring; production image/model compatibility still requires GPU deployment validation.

## Attribution

This page describes capabilities visible in the repository. It does not independently establish which lines were written manually, with AI assistance, or by collaborators. The commit history and pull-request diffs preserve the implementation trail; individual/team contribution percentages have not been inferred.

[Back to the project](../README.md)
