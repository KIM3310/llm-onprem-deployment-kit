#!/usr/bin/env bash
#
# airgap-mirror.sh - Mirror llm-stack container images to a private registry.
#
# Usage:
#   scripts/airgap-mirror.sh --target registry.customer.internal/llm-stack
#   scripts/airgap-mirror.sh --target registry.customer.internal/llm-stack --dry-run
#
# Requires: skopeo OR docker/podman in the PATH. skopeo is preferred because
# it works in airgapped environments without a local Docker daemon.
#
# The list of images below is the canonical inventory shipped by this kit.
# Bumping a version here should be paired with a values file update.

set -euo pipefail

# ------------------------------------------------------------------------------
# Image inventory. Format: source,destination-subpath
# Source is the upstream registry path. Destination is appended to the target
# registry with the tag preserved.
# ------------------------------------------------------------------------------

IMAGES=(
  "docker.io/vllm/vllm-openai:v0.4.3,vllm-openai"
  "docker.io/qdrant/qdrant:v1.9.2,qdrant"
  "docker.io/traefik:v3.0.3,traefik"
  "docker.io/openpolicyagent/opa:0.65.0-envoy,opa"
  "docker.io/otel/opentelemetry-collector-contrib:0.100.0,opentelemetry-collector-contrib"
  "docker.io/hashicorp/vault:1.16.2,vault"
  "ghcr.io/external-secrets/external-secrets:v0.9.18,external-secrets"
  "quay.io/prometheus/prometheus:v2.52.0,prometheus"
  "docker.io/grafana/loki:2.9.8,loki"
  "docker.io/grafana/tempo:2.5.0,tempo"
  "nvcr.io/nvidia/k8s/dcgm-exporter:3.3.5-3.4.0-ubuntu22.04,dcgm-exporter"
)

TARGET=""
DRY_RUN=false
TOOL=""

usage() {
  cat <<EOF
Usage: $(basename "$0") --target REGISTRY [options]

Options:
  --target REGISTRY     Destination registry path (required).
                        Example: registry.customer.internal/llm-stack
  --dry-run             Print what would be mirrored, do nothing.
  --tool TOOL           Force a specific tool: skopeo|docker|podman.
                        Default: auto-detect (skopeo preferred).
  --list                List images that would be mirrored and exit.
  -h, --help            Show this help.

Environment:
  SRC_USER, SRC_PASS    Credentials for the source registry (optional).
  DST_USER, DST_PASS    Credentials for the destination registry (optional).
EOF
}

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

detect_tool() {
  if command -v skopeo >/dev/null 2>&1; then
    TOOL="skopeo"
  elif command -v docker >/dev/null 2>&1; then
    TOOL="docker"
  elif command -v podman >/dev/null 2>&1; then
    TOOL="podman"
  else
    die "No supported tool found (need skopeo, docker, or podman)."
  fi
}

mirror_with_skopeo() {
  local src="$1"
  local dst="$2"
  local src_creds_args=()
  local dst_creds_args=()

  if [[ -n "${SRC_USER:-}" && -n "${SRC_PASS:-}" ]]; then
    src_creds_args=(--src-creds "${SRC_USER}:${SRC_PASS}")
  fi
  if [[ -n "${DST_USER:-}" && -n "${DST_PASS:-}" ]]; then
    dst_creds_args=(--dest-creds "${DST_USER}:${DST_PASS}")
  fi

  skopeo copy --all --retry-times 3 \
    "${src_creds_args[@]}" "${dst_creds_args[@]}" \
    "docker://${src}" "docker://${dst}"
}

mirror_with_docker_like() {
  local src="$1"
  local dst="$2"
  "$TOOL" pull "$src"
  "$TOOL" tag "$src" "$dst"
  "$TOOL" push "$dst"
}

# ------------------------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------------------------

LIST_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --list)
      LIST_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

if [[ "$LIST_ONLY" == "true" ]]; then
  printf 'Source images (%d):\n' "${#IMAGES[@]}"
  for entry in "${IMAGES[@]}"; do
    src="${entry%,*}"
    printf '  %s\n' "$src"
  done
  exit 0
fi

if [[ -z "$TARGET" ]]; then
  usage
  exit 1
fi

if [[ -z "$TOOL" ]]; then
  detect_tool
fi

log "Using tool: $TOOL"
log "Target:     $TARGET"
log "Dry run:    $DRY_RUN"
log "Mirroring ${#IMAGES[@]} images..."
log ""

failures=0
for entry in "${IMAGES[@]}"; do
  src="${entry%,*}"
  sub="${entry##*,}"
  tag="${src##*:}"
  dst="${TARGET}/${sub}:${tag}"

  log "  [src] $src"
  log "  [dst] $dst"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "  (dry-run) skipped"
    log ""
    continue
  fi

  set +e
  if [[ "$TOOL" == "skopeo" ]]; then
    mirror_with_skopeo "$src" "$dst"
  else
    mirror_with_docker_like "$src" "$dst"
  fi
  rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    log "  FAILED (exit $rc)"
    failures=$((failures + 1))
  else
    log "  OK"
  fi
  log ""
done

if [[ $failures -gt 0 ]]; then
  die "$failures image(s) failed to mirror. See log above."
fi

log "All ${#IMAGES[@]} images mirrored successfully to ${TARGET}."
