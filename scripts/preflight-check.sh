#!/usr/bin/env bash
#
# preflight-check.sh - Validate that a Kubernetes cluster is ready to host
# the llm-stack Helm chart. Runs read-only checks only.
#
# Usage:
#   scripts/preflight-check.sh [--namespace NAME] [--gpu] [--strict]
#
# Exit code: 0 if all required checks pass (warnings still allowed),
# non-zero otherwise.

set -euo pipefail

NAMESPACE="llm-stack"
REQUIRE_GPU=false
STRICT=false

log_info()  { printf '[ INFO] %s\n' "$*"; }
log_ok()    { printf '[  OK ] %s\n' "$*"; }
log_warn()  { printf '[WARN ] %s\n' "$*"; }
log_fail()  { printf '[FAIL ] %s\n' "$*"; }

WARN_COUNT=0
FAIL_COUNT=0

warn() { log_warn "$*"; WARN_COUNT=$((WARN_COUNT + 1)); }
fail() { log_fail "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --namespace NAME   Namespace to validate into (default: llm-stack)
  --gpu              Require GPU nodes to be present
  --strict           Treat warnings as failures
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --gpu) REQUIRE_GPU=true; shift ;;
    --strict) STRICT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

log_info "Preflight check against namespace: ${NAMESPACE}"
log_info "GPU required: ${REQUIRE_GPU}, strict mode: ${STRICT}"
log_info ""

# ------------------------------------------------------------------------------
# Tooling checks
# ------------------------------------------------------------------------------
for bin in kubectl helm; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    fail "Required binary not found: ${bin}"
  else
    ver=$("$bin" version --short 2>/dev/null || "$bin" version --client 2>/dev/null || true)
    log_ok "${bin} found (${ver:-unknown version})"
  fi
done

# ------------------------------------------------------------------------------
# Cluster reachability
# ------------------------------------------------------------------------------
if ! kubectl cluster-info >/dev/null 2>&1; then
  fail "Cannot reach cluster via kubectl. Check kubeconfig."
else
  server=$(kubectl config view --minify --output 'jsonpath={.clusters[0].cluster.server}')
  log_ok "Cluster reachable: ${server}"
fi

# ------------------------------------------------------------------------------
# Server version
# ------------------------------------------------------------------------------
server_version=$(kubectl version -o json 2>/dev/null | awk -F'"' '/gitVersion/{print $4}' | tail -1 || true)
if [[ -z "${server_version}" ]]; then
  warn "Could not determine server version."
else
  log_ok "Kubernetes server version: ${server_version}"
  # Expect 1.28+
  major=$(echo "${server_version#v}" | cut -d. -f1)
  minor=$(echo "${server_version#v}" | cut -d. -f2)
  if [[ "${major}" -lt 1 || ( "${major}" -eq 1 && "${minor}" -lt 28 ) ]]; then
    fail "Kubernetes >= 1.28 required; found ${server_version}"
  fi
fi

# ------------------------------------------------------------------------------
# Node count + zones
# ------------------------------------------------------------------------------
node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${node_count}" -lt 3 ]]; then
  warn "Only ${node_count} node(s) found. Production deployments expect >= 3 for HA."
else
  log_ok "${node_count} nodes available."
fi

zones=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' 2>/dev/null | sort -u | grep -cve '^$')
if [[ "${zones}" -lt 2 ]]; then
  warn "Nodes span only ${zones} zone(s). HA recommends 2+ zones."
else
  log_ok "Nodes span ${zones} zones."
fi

# ------------------------------------------------------------------------------
# GPU check
# ------------------------------------------------------------------------------
gpu_nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null | awk '$1>0{c++}END{print c+0}')
if [[ "${REQUIRE_GPU}" == "true" ]]; then
  if [[ "${gpu_nodes}" -lt 1 ]]; then
    fail "No nodes advertise nvidia.com/gpu. Install the NVIDIA device plugin."
  else
    log_ok "${gpu_nodes} node(s) expose GPU resources."
  fi
else
  log_info "GPU nodes (advertising nvidia.com/gpu): ${gpu_nodes}"
fi

# ------------------------------------------------------------------------------
# StorageClass
# ------------------------------------------------------------------------------
default_sc=$(kubectl get sc -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null | awk -F'|' '$2=="true"{print $1}')
if [[ -z "${default_sc}" ]]; then
  warn "No default StorageClass set. Qdrant PVCs need a StorageClass."
else
  log_ok "Default StorageClass: ${default_sc}"
fi

# ------------------------------------------------------------------------------
# Operators we expect to be installed (External Secrets, Prometheus Operator)
# ------------------------------------------------------------------------------
if kubectl get crd externalsecrets.external-secrets.io >/dev/null 2>&1; then
  log_ok "External Secrets Operator CRDs present."
else
  warn "ExternalSecrets CRD not found. Install ESO before enabling externalSecrets."
fi

if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
  log_ok "Prometheus Operator CRDs present."
else
  warn "ServiceMonitor CRD not found. Install kube-prometheus-stack or disable observability.serviceMonitor."
fi

# ------------------------------------------------------------------------------
# Namespace
# ------------------------------------------------------------------------------
if kubectl get ns "${NAMESPACE}" >/dev/null 2>&1; then
  log_ok "Namespace ${NAMESPACE} exists."
else
  log_info "Namespace ${NAMESPACE} does not exist yet; Helm will create it."
fi

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
log_info ""
log_info "Summary: ${FAIL_COUNT} fail, ${WARN_COUNT} warn."

if [[ "${STRICT}" == "true" && "${WARN_COUNT}" -gt 0 ]]; then
  exit 1
fi
if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
exit 0
