#!/usr/bin/env bash
#
# collect-diag-bundle.sh - Gather a diagnostic bundle for support escalation.
#
# Produces a tarball under ${OUT_DIR:-/tmp} containing cluster state,
# resource descriptions, logs, events, and recent metrics scrapes. The
# bundle is what support needs on a ticket, and NOTHING ELSE: no secret
# values, no config maps with credentials.
#
# Usage:
#   scripts/collect-diag-bundle.sh --namespace llm-stack --release llm-stack

set -euo pipefail

NAMESPACE="llm-stack"
RELEASE="llm-stack"
OUT_DIR="${OUT_DIR:-/tmp}"

log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --namespace NAME   Namespace (default: llm-stack)
  --release NAME     Helm release (default: llm-stack)
  --out-dir DIR      Where to write the bundle (default: /tmp)
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --release) RELEASE="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

command -v kubectl >/dev/null 2>&1 || die "kubectl not in PATH"

stamp="$(date -u +'%Y%m%dT%H%M%SZ')"
bundle_dir="${OUT_DIR}/diag-bundle-${RELEASE}-${stamp}"
mkdir -p "${bundle_dir}"

log "Collecting bundle at ${bundle_dir}"

# ---- Cluster-level ---------------------------------------------------------
kubectl version -o yaml > "${bundle_dir}/kubectl-version.yaml" 2>&1 || true
kubectl cluster-info >"${bundle_dir}/cluster-info.txt" 2>&1 || true
kubectl get nodes -o yaml > "${bundle_dir}/nodes.yaml" 2>&1 || true
kubectl top nodes > "${bundle_dir}/nodes-top.txt" 2>&1 || true
kubectl get storageclasses -o yaml > "${bundle_dir}/storageclasses.yaml" 2>&1 || true
kubectl api-resources > "${bundle_dir}/api-resources.txt" 2>&1 || true

# ---- Namespace-level -------------------------------------------------------
ns_dir="${bundle_dir}/namespace-${NAMESPACE}"
mkdir -p "${ns_dir}"

kubectl -n "${NAMESPACE}" get all -o yaml > "${ns_dir}/all.yaml" 2>&1 || true
kubectl -n "${NAMESPACE}" get events --sort-by='.lastTimestamp' > "${ns_dir}/events.txt" 2>&1 || true
kubectl -n "${NAMESPACE}" get networkpolicies -o yaml > "${ns_dir}/networkpolicies.yaml" 2>&1 || true
kubectl -n "${NAMESPACE}" get pdb -o yaml > "${ns_dir}/pdb.yaml" 2>&1 || true
kubectl -n "${NAMESPACE}" get pvc -o yaml > "${ns_dir}/pvc.yaml" 2>&1 || true
kubectl -n "${NAMESPACE}" get hpa -o yaml > "${ns_dir}/hpa.yaml" 2>&1 || true
kubectl -n "${NAMESPACE}" get serviceaccounts > "${ns_dir}/serviceaccounts.txt" 2>&1 || true
kubectl -n "${NAMESPACE}" top pods > "${ns_dir}/pods-top.txt" 2>&1 || true

# ---- Describe pods + logs --------------------------------------------------
pods_dir="${ns_dir}/pods"
mkdir -p "${pods_dir}"

pods=$(kubectl -n "${NAMESPACE}" get pods --no-headers -o custom-columns=:metadata.name 2>/dev/null || true)
for pod in ${pods}; do
  pod_dir="${pods_dir}/${pod}"
  mkdir -p "${pod_dir}"
  kubectl -n "${NAMESPACE}" describe pod "${pod}" > "${pod_dir}/describe.txt" 2>&1 || true
  containers=$(kubectl -n "${NAMESPACE}" get pod "${pod}" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || true)
  for c in ${containers}; do
    kubectl -n "${NAMESPACE}" logs "${pod}" -c "${c}" --tail=1000 \
      > "${pod_dir}/${c}.log" 2>&1 || true
    kubectl -n "${NAMESPACE}" logs "${pod}" -c "${c}" --previous --tail=1000 \
      > "${pod_dir}/${c}.previous.log" 2>/dev/null || true
  done
done

# ---- Helm manifest (values are sanitized: keys like password/token/key dropped) ---
if command -v helm >/dev/null 2>&1; then
  helm -n "${NAMESPACE}" get manifest "${RELEASE}" > "${ns_dir}/helm-manifest.yaml" 2>&1 || true
  helm -n "${NAMESPACE}" get values "${RELEASE}" \
    | sed -E '/(password|secret|token|apikey|key): /Id' \
    > "${ns_dir}/helm-values.sanitized.yaml" 2>&1 || true
fi

# ---- ExternalSecret status (without data) ----------------------------------
kubectl -n "${NAMESPACE}" get externalsecrets -o json 2>/dev/null \
  | awk '/"data":/,0{next}1' \
  > "${ns_dir}/externalsecrets.status.txt" 2>&1 || true

# ---- Metadata --------------------------------------------------------------
cat > "${bundle_dir}/META.txt" <<EOF
Bundle created at:   $(date -u +'%Y-%m-%dT%H:%M:%SZ')
Namespace:           ${NAMESPACE}
Release:             ${RELEASE}
Tool:                collect-diag-bundle.sh (llm-onprem-deployment-kit)

This bundle contains:
- Cluster version and node state
- Namespace-scoped resource manifests (no Secret values)
- Pod logs (current + previous) for every pod in the release
- Helm manifest and sanitized values
- ExternalSecret status (no secret data)

It does NOT contain:
- Kubernetes Secret values
- Values from any key named password/secret/token/apikey/key
- Cluster credentials or kubeconfig
EOF

# ---- Package ---------------------------------------------------------------
tarball="${OUT_DIR}/$(basename "${bundle_dir}").tar.gz"
tar -czf "${tarball}" -C "$(dirname "${bundle_dir}")" "$(basename "${bundle_dir}")"
rm -rf "${bundle_dir}"

log "Bundle written: ${tarball}"
log ""
log "Open your support ticket and attach this file. Do not email it;"
log "transfer via the customer-approved artifact channel."
