# Runbook - Incident Response

Playbook for responding to incidents affecting a production `llm-stack` deployment. Primary audience: on-call SRE. Secondary audience: customer's change-management / security team.

## Severity levels

| SEV | Definition | Response time (page) | Examples |
|-----|-----------|----------------------|----------|
| SEV-1 | Full outage, data loss risk, or active security incident | Immediate (24x7) | API 100% unavailable; Vault compromise suspected; unauthorized access to pods |
| SEV-2 | Major degradation, partial feature loss | 15 minutes (business + after-hours) | p95 latency > 10x baseline for >5m; one component failing on all replicas |
| SEV-3 | Minor degradation; some users affected | 1 hour (business hours) | Sporadic 5xx errors within SLO; Qdrant replica down but others healthy |
| SEV-4 | No user impact; engineering cleanup | Next business day | Noisy non-fatal logs; cosmetic issues |

## Paging and ownership

- Primary on-call: the vendor forward deployed engineer assigned to this customer.
- Secondary on-call: the customer's platform SRE rotation.
- Escalation: vendor engineering leadership at SEV-1 after 30 minutes without stabilization.
- Security-specific: customer's SOC + vendor security at SEV-1 suspected-breach scenarios.

Paging channel is defined per-customer in the deployment record (PagerDuty service / Opsgenie schedule / phone tree).

## First-response checklist (all SEVs)

1. Acknowledge the page.
2. Open an incident channel (Slack `#inc-<timestamp>` or equivalent).
3. Declare the SEV in the channel topic. You can upgrade or downgrade later.
4. Note current time as `T0`.
5. Do not make changes in the first 5 minutes unless you are actively containing damage. Observe first.

## Observation

```bash
# Overall pod health
kubectl -n llm-stack get pods

# Recent events
kubectl -n llm-stack get events --sort-by='.lastTimestamp' | tail -50

# Inference logs (recent)
kubectl -n llm-stack logs deploy/llm-stack-inference --tail=200

# Gateway + OPA logs
kubectl -n llm-stack logs deploy/llm-stack-gateway -c traefik --tail=200
kubectl -n llm-stack logs deploy/llm-stack-gateway -c opa --tail=200

# Metrics (adapt to customer's Prometheus endpoint)
# High-signal PromQL queries are in runbooks/disaster-recovery.md
```

## SEV-1 playbook

For full-outage or suspected-breach:

1. **Contain damage first.** If a security event, revoke the relevant credentials before investigating. `vault token revoke ...`, cloud IAM access key rotation, `kubectl -n llm-stack delete deploy/llm-stack-gateway` to cut traffic if necessary.
2. **Collect evidence.** `./scripts/collect-diag-bundle.sh --namespace llm-stack --out-dir /tmp` BEFORE further changes. This captures current state with no secret values.
3. **Communicate.** Post to the incident channel every 15 minutes with: current status, what was tried, next action, ETA.
4. **Restore service** per the specific symptom below.
5. **Document decisions** in real time, not post-hoc.

## Common symptom -> action matrix

| Symptom | First investigation | First remediation |
|---------|---------------------|-------------------|
| All inference pods CrashLoopBackOff | `kubectl describe pod`, look at events | Rollback last helm upgrade: `helm rollback llm-stack <N-1>` |
| Gateway 503 on every request | Check OPA logs for `policy evaluation error` | Roll out previous OPA policy ConfigMap |
| Qdrant cluster split-brain | `kubectl exec` into pod and `GET /cluster` | Follow `disaster-recovery.md` Qdrant section |
| Node "NotReady" en masse | Cloud health page first; `kubectl get nodes` | Cordon affected nodes; drain to healthy nodes |
| ExternalSecret stuck in error | `kubectl describe externalsecret`; check Vault auth | Re-create SA and re-run Vault kubernetes auth role |
| HPA not scaling despite GPU saturation | `kubectl describe hpa`; check metric availability | Check DCGM exporter; external-metrics adapter |
| Memory OOM on vLLM | `kubectl describe pod`; check cgroup limits | Raise memory limits or reduce `--max-model-len` |
| Certificate expired | `openssl s_client -connect ...` to verify | Check cert-manager logs; force renewal |

## AegisOps integration (optional)

For customers with [`AegisOps`](https://github.com/KIM3310/AegisOps) deployed:

1. AegisOps ingests the cluster's multimodal signals (pod logs, dashboards, architecture diagrams) and produces a structured incident analysis.
2. Use AegisOps' operator-handoff output as the starting point for SEV-2/SEV-3 investigations.
3. SEV-1 always starts with human action; AegisOps advises rather than decides.

## Diagnostic bundle

`./scripts/collect-diag-bundle.sh --namespace llm-stack` writes a tarball to `/tmp/diag-bundle-<release>-<timestamp>.tar.gz`. The bundle excludes Secret values and sanitizes values files. Attach to the support ticket via the customer-approved artifact channel.

## Customer handoff

When an incident is bounded and the remaining work is the customer's responsibility:

- State clearly in the incident channel: "Handing off to customer team for `<specific task>`. Context: `<summary>`. Expected follow-up: `<action + owner>`."
- Ensure the customer on-call acknowledges in writing.
- Do not close the ticket until the customer explicitly agrees to close.

## Post-incident

Within 48 hours of SEV-1/SEV-2 resolution:

- [ ] Post-mortem document drafted (blameless format).
- [ ] Timeline with every command and decision.
- [ ] Root cause analysis; "five whys" section.
- [ ] Action items with owners and due dates.
- [ ] Update this runbook if gaps were found.
- [ ] Update [`security-model.md`](../security-model.md) if the threat model needs adjustment.

## Detection rules

Recommended alert thresholds; wire into the customer's Prometheus / alerting stack.

| Alert | Expression | Severity |
|-------|------------|----------|
| InferencePodDown | `sum(up{job="llm-stack", component="inference"}) < 1` for 5m | SEV-1 |
| GatewayHighErrorRate | `sum(rate(traefik_service_requests_total{code=~"5.."}[5m])) / sum(rate(traefik_service_requests_total[5m])) > 0.05` for 10m | SEV-2 |
| QdrantReplicaDown | `up{job="llm-stack", component="vector-db"} == 0` for 10m | SEV-3 |
| GPUMemoryPressure | `DCGM_FI_DEV_MEM_COPY_UTIL > 95` for 15m | SEV-3 |
| SecretSyncFailing | `increase(externalsecret_sync_calls_error_total[15m]) > 5` | SEV-2 |
| CertExpiringSoon | `probe_ssl_earliest_cert_expiry - time() < 86400 * 14` | SEV-3 |
| OPAPolicyEvaluationError | `increase(opa_evaluator_errors_total[15m]) > 0` | SEV-2 |
