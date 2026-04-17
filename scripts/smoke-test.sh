#!/usr/bin/env bash
#
# smoke-test.sh - Post-deploy smoke test for the llm-stack Helm release.
#
# Exercises:
#   1. The gateway returns 200 on /health (OPA must allow).
#   2. An OpenAI-compatible /v1/models call against vLLM succeeds.
#   3. Qdrant is reachable and /collections returns 200.
#
# Usage:
#   scripts/smoke-test.sh --namespace llm-stack --release llm-stack
#   scripts/smoke-test.sh --namespace llm-stack --release llm-stack --bearer <TOKEN>

set -euo pipefail

NAMESPACE="llm-stack"
RELEASE="llm-stack"
BEARER=""

log()  { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --namespace NAME   Namespace (default: llm-stack)
  --release NAME     Helm release (default: llm-stack)
  --bearer TOKEN     Bearer token for authorization header
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --release) RELEASE="$2"; shift 2 ;;
    --bearer) BEARER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

command -v kubectl >/dev/null 2>&1 || die "kubectl not in PATH"
command -v curl >/dev/null 2>&1 || die "curl not in PATH"

GATEWAY_SVC="${RELEASE}-gateway"
INFERENCE_SVC="${RELEASE}-inference"
QDRANT_SVC="${RELEASE}-qdrant"

cleanup_pids=()
cleanup() {
  for p in "${cleanup_pids[@]}"; do
    kill "${p}" 2>/dev/null || true
  done
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# Port-forwards
# ------------------------------------------------------------------------------
log "Port-forwarding services..."

kubectl -n "${NAMESPACE}" port-forward "svc/${GATEWAY_SVC}" 18443:443 >/dev/null 2>&1 &
cleanup_pids+=("$!")

kubectl -n "${NAMESPACE}" port-forward "svc/${INFERENCE_SVC}" 18000:8000 >/dev/null 2>&1 &
cleanup_pids+=("$!")

kubectl -n "${NAMESPACE}" port-forward "svc/${QDRANT_SVC}" 16333:6333 >/dev/null 2>&1 &
cleanup_pids+=("$!")

# Wait for ports
for i in $(seq 1 30); do
  if curl -sk --max-time 2 https://localhost:18443/ping >/dev/null 2>&1; then
    break
  fi
  sleep 1
  if [[ "$i" -eq 30 ]]; then
    die "Timed out waiting for gateway port-forward."
  fi
done

log "Port-forwards established."

# ------------------------------------------------------------------------------
# Test 1: Gateway /health returns 200 (OPA should allow unauthenticated)
# ------------------------------------------------------------------------------
log "[1/3] Gateway /health"
code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 https://localhost:18443/health || true)
if [[ "${code}" != "200" ]]; then
  die "Gateway /health returned ${code}, expected 200."
fi
log "  OK (http ${code})"

# ------------------------------------------------------------------------------
# Test 2: vLLM /v1/models
# ------------------------------------------------------------------------------
log "[2/3] vLLM /v1/models"
auth_arg=()
if [[ -n "${BEARER}" ]]; then
  auth_arg=(-H "Authorization: Bearer ${BEARER}")
fi
resp=$(curl -s --max-time 20 "${auth_arg[@]}" http://localhost:18000/v1/models || true)
if ! echo "${resp}" | grep -q '"data"'; then
  die "vLLM /v1/models did not return a data field. Response: ${resp}"
fi
log "  OK (${#resp} bytes)"

# ------------------------------------------------------------------------------
# Test 3: Qdrant /collections
# ------------------------------------------------------------------------------
log "[3/3] Qdrant /collections"
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://localhost:16333/collections || true)
if [[ "${code}" != "200" ]]; then
  die "Qdrant /collections returned ${code}, expected 200."
fi
log "  OK (http ${code})"

log ""
log "All smoke tests passed."
