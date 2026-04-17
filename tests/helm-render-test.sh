#!/usr/bin/env bash
#
# helm-render-test.sh - Render the llm-stack chart with different values
# combinations and validate the output against Kubernetes schemas.
#
# Requires: helm 3.12+, kubeconform (https://github.com/yannh/kubeconform).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${REPO_ROOT}/helm/llm-stack"
OUT_DIR="$(mktemp -d)"

cleanup() { rm -rf "${OUT_DIR}"; }
trap cleanup EXIT

CASES=(
  "default:${CHART}/values.yaml"
  "airgap:${CHART}/values.yaml,${CHART}/values-airgap.yaml"
  "dev:${CHART}/values.yaml,${CHART}/values-dev.yaml"
)

K8S_VERSION="${K8S_VERSION:-1.28.0}"

command -v helm >/dev/null 2>&1 || { echo "helm not in PATH"; exit 2; }

have_kubeconform=true
command -v kubeconform >/dev/null 2>&1 || have_kubeconform=false

fail=0

for entry in "${CASES[@]}"; do
  name="${entry%%:*}"
  files="${entry#*:}"
  out="${OUT_DIR}/rendered-${name}.yaml"

  echo "==> helm lint (${name})"
  set -- --set global.imageRegistry=registry.example.com
  IFS=',' read -r -a vf <<< "${files}"
  values_args=()
  for f in "${vf[@]}"; do
    values_args+=(--values "$f")
  done
  if ! helm lint "${CHART}" "${values_args[@]}" "$@"; then
    fail=1
  fi

  echo "==> helm template (${name})"
  if ! helm template llm-stack "${CHART}" "${values_args[@]}" "$@" > "${out}"; then
    fail=1
    continue
  fi

  if [[ "${have_kubeconform}" == "true" ]]; then
    echo "==> kubeconform (${name}, k8s ${K8S_VERSION})"
    if ! kubeconform -kubernetes-version "${K8S_VERSION}" -strict -ignore-missing-schemas "${out}"; then
      fail=1
    fi
  else
    echo "SKIP: kubeconform not installed; skipping schema validation for ${name}."
  fi
done

if [[ "${fail}" -ne 0 ]]; then
  echo "FAIL"
  exit 1
fi
echo "OK"
