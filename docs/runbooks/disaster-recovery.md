# Runbook - Disaster Recovery

Recover the `llm-stack` deployment from a regional outage, catastrophic cluster failure, or storage loss. This runbook is the basis for the customer's Business Continuity Plan.

## Recovery objectives (defaults)

| Objective | Target |
|-----------|--------|
| RPO (Recovery Point Objective) for Qdrant | 15 minutes |
| RPO for configuration (Terraform state, Helm values) | 0 (Git is the source of truth) |
| RTO (Recovery Time Objective) for inference | 30 minutes |
| RTO for vector search | 60 minutes |

Adjust per customer's contractual SLA.

## Backup inventory

| Object | Backup mechanism | Retention |
|--------|------------------|-----------|
| Qdrant collections | Qdrant snapshot API + PVC snapshot | 30 days |
| Model weights PVC | Cloud volume snapshot daily | 14 days |
| Helm values / custom values | Git | Permanent |
| Terraform state | Remote backend (Azure Blob / S3 / GCS) with versioning | Permanent |
| Vault data | Customer's Vault DR strategy | Customer-defined |
| Cluster credentials | Derived on demand via cloud IAM | Not applicable |

## Backup procedures (weekly)

### Qdrant snapshot

```bash
kubectl -n llm-stack exec llm-stack-qdrant-0 -- \
  curl -s -X POST "http://localhost:6333/collections/<col>/snapshots"
# Copy snapshot file to object storage
kubectl -n llm-stack cp llm-stack-qdrant-0:/qdrant/storage/<col>/snapshots/<file> ./qdrant-snapshots/
aws s3 cp ./qdrant-snapshots/<file> s3://customer-dr-bucket/qdrant/
```

### PVC snapshot (VolumeSnapshot API; example on Azure)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: qdrant-0-snap-$(date +%Y%m%d)
  namespace: llm-stack
spec:
  source:
    persistentVolumeClaimName: data-llm-stack-qdrant-0
EOF
```

Repeat for each Qdrant replica and (optionally) the model-cache PVC.

## Recovery scenarios

### Scenario A - Single Qdrant replica lost

Detection: a StatefulSet pod stays `Pending` or `CrashLoopBackOff`; peer pods remain `Running`.

1. Delete the broken PVC and PV:

   ```bash
   kubectl -n llm-stack delete pod llm-stack-qdrant-1
   kubectl -n llm-stack delete pvc data-llm-stack-qdrant-1
   ```

2. The StatefulSet re-provisions a fresh PVC for the replica; Qdrant's replication catches it up from peers.
3. Verify:

   ```bash
   kubectl -n llm-stack exec llm-stack-qdrant-0 -- \
     curl -s http://localhost:6333/cluster | jq
   ```

4. No data restore required.

### Scenario B - All Qdrant replicas lost, snapshots available

1. Scale Qdrant to zero replicas (the operator deletes pods but keeps PVCs unless explicitly deleted):

   ```bash
   kubectl -n llm-stack scale statefulset llm-stack-qdrant --replicas=0
   ```

2. Restore the latest snapshot into the first pod's PVC by:
   - Mounting the PVC in a temporary pod.
   - Copying the snapshot file into `/qdrant/storage/<col>/snapshots/`.
   - Scaling Qdrant back up.

3. On first Qdrant startup, it will recognize the snapshot and recover. See `https://qdrant.tech/documentation/concepts/snapshots/` for the official procedure.

4. Scale to full replica count:

   ```bash
   kubectl -n llm-stack scale statefulset llm-stack-qdrant --replicas=3
   ```

### Scenario C - Entire cluster lost

1. Declare SEV-1 and initiate the DR plan (see [`incident-response.md`](./incident-response.md)).
2. Provision a new cluster in the DR region from `terraform/examples/airgapped-enterprise/main.tf`. Use the customer's DR variables file.
3. Restore Vault from its DR replica.
4. Restore Qdrant from snapshots (Scenario B).
5. Re-apply Helm chart with the same values files.
6. Run smoke test. Cut traffic over at the gateway level once green.

Estimated time: 2-4 hours once the DR cluster exists.

### Scenario D - KMS key unavailable

Extremely rare but catastrophic. Mitigation:

- Terraform module sets the key as `soft_delete_retention_days = 90` (Azure) and `deletion_window_in_days = 30` (AWS). GCP destroys key versions but not the key itself by default.
- Recovery: restore the key from its soft-deleted state via cloud portal or CLI (`az keyvault key recover`, `aws kms cancel-key-deletion`).
- If the key is permanently lost, etcd encrypted objects are unrecoverable. Restore from a cluster-level backup and re-key.

## DR drill procedure (quarterly)

Run this drill every quarter to verify the RTO and RPO targets.

1. In a drill environment, restore the latest Qdrant snapshot and measure time-to-ready.
2. Provision a parallel cluster in the DR region; measure time-to-ready.
3. Run smoke test against the drill cluster; measure pass rate.
4. Record the actual RPO (time between last snapshot and drill start) and RTO (time from drill start to smoke test pass).
5. Update this runbook if drill reveals gaps.

## Cross-region strategy

The default infrastructure is regional. For cross-region DR:

- Keep Terraform state for the DR region pre-provisioned in a "warm standby" state (cluster provisioned, workloads scaled to zero).
- Replicate model weights and Qdrant snapshots to DR-region object storage.
- Rely on the customer's DNS / GSLB to shift traffic between regions.

## What this runbook does NOT cover

- Customer Vault DR - follow Vault's operational manual.
- Customer IdP DR - blocked outage: gateway cannot issue new tokens without IdP; service may remain up for holders of valid tokens.
- Cloud region outage - cloud provider's runbooks take precedence; this runbook assumes IaaS is reachable.

## Communications plan

During a regional outage:

- Incident channel: `#inc-<date>-<region>-outage`.
- Customer status page: update hourly with RPO/RTO progress.
- Customer's procurement / CISO notified at incident declaration and at restore-complete.
