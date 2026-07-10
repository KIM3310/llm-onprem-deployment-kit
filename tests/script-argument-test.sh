#!/usr/bin/env bash
#
# Verify shell entrypoints reject missing option values with intentional errors
# instead of leaking Bash "unbound variable" failures under set -u.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_missing_value() {
  local script="$1"
  local option="$2"
  local output

  set +e
  output="$("${ROOT_DIR}/${script}" "${option}" 2>&1)"
  local rc=$?
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    printf 'FAIL: %s %s unexpectedly succeeded\n' "${script}" "${option}" >&2
    exit 1
  fi
  if [[ "${output}" != *"Missing value for ${option}"* ]]; then
    printf 'FAIL: %s %s did not report a missing value\n%s\n' "${script}" "${option}" "${output}" >&2
    exit 1
  fi
  if [[ "${output}" == *"unbound variable"* ]]; then
    printf 'FAIL: %s %s leaked an unbound-variable error\n%s\n' "${script}" "${option}" "${output}" >&2
    exit 1
  fi
}

assert_missing_value "scripts/airgap-mirror.sh" "--target"
assert_missing_value "scripts/airgap-mirror.sh" "--tool"
assert_missing_value "scripts/preflight-check.sh" "--namespace"
assert_missing_value "scripts/smoke-test.sh" "--namespace"
assert_missing_value "scripts/smoke-test.sh" "--release"
assert_missing_value "scripts/smoke-test.sh" "--bearer"
assert_missing_value "scripts/collect-diag-bundle.sh" "--namespace"
assert_missing_value "scripts/collect-diag-bundle.sh" "--release"
assert_missing_value "scripts/collect-diag-bundle.sh" "--out-dir"

printf 'script argument validation ok\n'
