#!/usr/bin/env bash
# Actual kind + Helm + Traefik; the inference protocol is synthetic.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${KIND_CLUSTER_NAME:=portfolio-smoke}"
work_dir="$(mktemp -d)"
forward_pid=""
cleanup() {
  if [[ -n "$forward_pid" ]]; then kill "$forward_pid" 2>/dev/null || true; fi
  rm -rf "$work_dir"
}
trap cleanup EXIT
# Guard against applying this fixture to an existing user cluster.
context="kind-${KIND_CLUSTER_NAME}"
[[ "$(kubectl config current-context)" == "$context" ]] || { echo "Expected disposable kind context $context" >&2; exit 1; }
docker build -t llm-protocol-fixture:ci tests/cluster-fixture
kind load docker-image llm-protocol-fixture:ci --name "$KIND_CLUSTER_NAME"
kubectl create namespace llm-smoke
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -keyout "$work_dir/key.pem" -out "$work_dir/cert.pem" -subj /CN=localhost -addext subjectAltName=DNS:localhost >/dev/null 2>&1
kubectl -n llm-smoke create secret tls llm-stack-tls --cert="$work_dir/cert.pem" --key="$work_dir/key.pem"
fixture_key="$(openssl rand -hex 24)"
invalid_key="invalid-test-key"
kubectl -n llm-smoke create secret generic llm-stack-inference-api-key --from-literal="api-key=$fixture_key"
helm upgrade --install llm-stack helm/llm-stack -n llm-smoke -f tests/cluster-fixture/values.yaml --wait --timeout 180s
kubectl -n llm-smoke rollout status deployment/llm-stack-gateway --timeout=120s
kubectl -n llm-smoke port-forward service/llm-stack-gateway 18080:80 18443:443 >"$work_dir/forward.log" 2>&1 &
forward_pid=$!
for _ in {1..30}; do
  if curl -fsS http://localhost:18080/ping >/dev/null; then break; fi
  sleep 1
done
http_status="$(curl -sS -o /dev/null -w '%{http_code}' http://localhost:18080/v1/models)"
[[ "$http_status" == 301 || "$http_status" == 308 ]]
[[ "$(curl --cacert "$work_dir/cert.pem" -sS -o /dev/null -w '%{http_code}' https://localhost:18443/v1/models)" == 401 ]]
[[ "$(curl --cacert "$work_dir/cert.pem" -sS -H "Authorization: Bearer $invalid_key" -o /dev/null -w '%{http_code}' https://localhost:18443/v1/models)" == 401 ]]
curl --cacert "$work_dir/cert.pem" -fsS -H "Authorization: Bearer $fixture_key" https://localhost:18443/v1/models > "$work_dir/models.json"
python3 - "$work_dir/models.json" <<'CHECK'
import json, sys
assert json.load(open(sys.argv[1]))["data"][0]["id"] == "synthetic-fixture-no-model"
CHECK
# Kubernetes must replace a deleted serving pod and restore readiness.
kubectl -n llm-smoke delete pod -l app.kubernetes.io/component=inference --wait=true
kubectl -n llm-smoke rollout status deployment/llm-stack-inference --timeout=120s
for _ in {1..30}; do
  if curl --cacert "$work_dir/cert.pem" -fsS -H "Authorization: Bearer $fixture_key" https://localhost:18443/v1/models >/dev/null; then break; fi
  sleep 1
done
curl --cacert "$work_dir/cert.pem" -fsS -H "Authorization: Bearer $fixture_key" https://localhost:18443/v1/models >/dev/null
mkdir -p artifacts
python3 - <<'PROOF'
import json
from pathlib import Path
proof = {"schema": "llm-cluster-smoke-v1", "scope": "real kind Kubernetes, chart, TLS and Traefik; synthetic inference HTTP fixture", "checks": ["helm rollout", "HTTP redirects to HTTPS", "trusted local TLS certificate", "missing key rejected", "wrong key rejected", "secret reaches inference process", "authenticated request routed", "pod deletion recovery"], "notValidated": ["GPU inference", "model quality", "network policy enforcement", "Qdrant persistence", "airgap install", "cloud provisioning"]}
Path("artifacts/cluster-smoke.json").write_text(json.dumps(proof, indent=2) + "\n")
print(json.dumps(proof, indent=2))
PROOF
