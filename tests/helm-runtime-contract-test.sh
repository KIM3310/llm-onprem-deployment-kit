#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${REPO_ROOT}/helm/llm-stack"
OUT_DIR="$(mktemp -d)"

cleanup() { rm -rf "${OUT_DIR}"; }
trap cleanup EXIT

command -v helm >/dev/null 2>&1 || {
  echo "helm not in PATH"
  exit 2
}

DEFAULT_RENDER="${OUT_DIR}/default.yaml"
AIRGAP_RENDER="${OUT_DIR}/airgap.yaml"
DEV_RENDER="${OUT_DIR}/dev.yaml"

helm template llm-stack "${CHART}" > "${DEFAULT_RENDER}"
helm template llm-stack "${CHART}" \
  --values "${CHART}/values-airgap.yaml" > "${AIRGAP_RENDER}"
helm template llm-stack "${CHART}" \
  --values "${CHART}/values-dev.yaml" > "${DEV_RENDER}"

assert_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq -- "${pattern}" "${file}"; then
    echo "expected ${file} to contain: ${pattern}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  if grep -Fq -- "${pattern}" "${file}"; then
    echo "expected ${file} not to contain: ${pattern}" >&2
    exit 1
  fi
}

assert_contains "${DEFAULT_RENDER}" "--providers.file.filename=/etc/traefik/dynamic/dynamic.yaml"
assert_contains "${DEFAULT_RENDER}" "url: http://llm-stack-inference:8000"
assert_contains "${DEFAULT_RENDER}" "name: VLLM_API_KEY"
assert_contains "${DEFAULT_RENDER}" "name: llm-stack-inference-api-key"
assert_contains "${DEFAULT_RENDER}" "name: llm-stack-qdrant"
assert_contains "${DEFAULT_RENDER}" "replicas: 1"
assert_contains "${DEFAULT_RENDER}" "health_check:"
assert_contains "${DEFAULT_RENDER}" "extensions: [health_check]"
assert_contains "${DEFAULT_RENDER}" "name: health"
assert_contains "${DEFAULT_RENDER}" "containerPort: 13133"
assert_not_contains "${DEFAULT_RENDER}" "openpolicyagent/opa"
assert_not_contains "${DEFAULT_RENDER}" "package authz"
assert_not_contains "${DEFAULT_RENDER}" "kind: HorizontalPodAutoscaler"

if grep -A3 '^kind: PodDisruptionBudget$' "${DEFAULT_RENDER}" \
  | grep -Fq 'name: llm-stack-qdrant'; then
  echo "expected the single-node Qdrant baseline not to render a blocking PDB" >&2
  exit 1
fi

assert_contains "${AIRGAP_RENDER}" "name: llm-stack-inference-api-key"
assert_contains "${AIRGAP_RENDER}" "name: llm-stack-allow-gateway-egress"
assert_contains "${AIRGAP_RENDER}" "name: llm-stack-allow-gateway-ingress"

assert_not_contains "${DEV_RENDER}" "name: VLLM_API_KEY"
assert_not_contains "${DEV_RENDER}" "kind: ExternalSecret"

if helm template llm-stack "${CHART}" --set vectorDb.replicaCount=2 >/dev/null 2>&1; then
  echo "expected an unconfigured multi-replica Qdrant render to fail" >&2
  exit 1
fi

if helm template llm-stack "${CHART}" \
  --set inference.auth.existingSecret= >/dev/null 2>&1; then
  echo "expected a missing inference API-key secret reference to fail" >&2
  exit 1
fi

echo "helm runtime contract ok"
