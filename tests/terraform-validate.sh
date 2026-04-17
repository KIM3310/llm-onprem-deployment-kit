#!/usr/bin/env bash
#
# terraform-validate.sh - Run `terraform fmt -check` and `terraform validate`
# on every module and example directory. Used both locally and by CI.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODULES=(
  "${REPO_ROOT}/terraform/modules/azure-aks"
  "${REPO_ROOT}/terraform/modules/aws-eks"
  "${REPO_ROOT}/terraform/modules/gcp-gke"
)

EXAMPLES=(
  "${REPO_ROOT}/terraform/modules/azure-aks/examples/basic"
  "${REPO_ROOT}/terraform/modules/aws-eks/examples/basic"
  "${REPO_ROOT}/terraform/modules/gcp-gke/examples/basic"
  "${REPO_ROOT}/terraform/examples/airgapped-enterprise"
  "${REPO_ROOT}/terraform/examples/dev-sandbox"
)

fail=0

check_dir() {
  local d="$1"
  echo "==> ${d}"
  if ! terraform -chdir="${d}" fmt -check -recursive >/dev/null; then
    echo "  fmt issues (run: terraform fmt -recursive ${d})"
    fail=1
  fi
  if ! terraform -chdir="${d}" init -backend=false -input=false -no-color >/dev/null 2>&1; then
    echo "  init failed"
    fail=1
    return
  fi
  if ! terraform -chdir="${d}" validate -no-color; then
    fail=1
  fi
}

for d in "${MODULES[@]}" "${EXAMPLES[@]}"; do
  check_dir "$d"
done

if [[ "${fail}" -ne 0 ]]; then
  echo "FAIL: one or more modules did not validate cleanly."
  exit 1
fi
echo "OK: all modules validated."
