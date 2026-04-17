# ADR 001 - Why Kubernetes, not ECS / Nomad / plain VMs

## Status

Accepted. Revisit annually or if target customer profile shifts to dominant AWS-only + ECS adopters.

## Context

This kit deploys an LLM application stack into customer-controlled private clouds across Azure, AWS, and GCP. The orchestration layer is the single largest determinant of:

1. Portability across the three clouds.
2. Operational familiarity for the customer's platform team.
3. Capability to express the security posture we require (NetworkPolicy, RBAC, PodSecurity).
4. Velocity of the deployment team shipping changes to new customers.

Candidate orchestration layers considered:

- **Kubernetes** (AKS / EKS / GKE, managed control planes)
- **AWS ECS (Fargate / EC2)** as an AWS-only alternative
- **HashiCorp Nomad** as a lightweight alternative
- **Plain VMs + systemd**, provisioned by Terraform
- **Serverless** (Azure Container Apps, AWS App Runner, Cloud Run)

The decision was made in the context of enterprise customer environments where:

- The customer's platform team already runs Kubernetes workloads for other vendors.
- The workload includes stateful (Qdrant) and stateless (vLLM, gateway) components.
- The customer requires policy-engine integration, fine-grained network policy, and workload identity.
- The workload is GPU-heavy, so nodeSelector / taints / tolerations matter.

## Decision

We target **managed Kubernetes** (AKS, EKS, GKE) as the orchestration layer across all three cloud modules.

Concretely, that means:

- Terraform modules provision a managed Kubernetes cluster with a system node pool and a GPU node pool.
- All workloads ship as Helm templates inside a single `llm-stack` chart.
- Cloud-specific concerns (private endpoints, KMS integration, image registry) are handled in the Terraform module; the Helm chart is cloud-agnostic and references only K8s primitives and values.
- Workload identity uses the cloud-native mapping (Azure AD Workload Identity, IRSA, GKE Workload Identity) via ServiceAccount annotations.

## Consequences

### Positive

- **Portability.** One Helm chart covers all three clouds. Adding a fourth cloud (OCI, IBM Cloud, or on-premise OpenShift) is a new Terraform module, not a new application stack.
- **Familiar to customers.** Enterprise infra teams recognize and can audit Kubernetes constructs: NetworkPolicy, PodSecurityAdmission, RBAC.
- **Ecosystem integration.** Prometheus Operator, External Secrets Operator, cert-manager, and OPA all have first-class Kubernetes integrations. The chart consumes these as CRDs, not as vendor-specific services.
- **Policy expressiveness.** OPA sidecars, Kyverno ClusterPolicies, and admission webhooks can all be layered on. ECS/Nomad require bespoke policy machinery.
- **Autoscaling.** HPA with custom metrics (DCGM) is available out-of-the-box. ECS has application autoscaling but does not support arbitrary external metrics as cleanly.
- **Stateful workloads.** StatefulSet + PVC semantics are a clean fit for Qdrant's 3-replica-with-anti-affinity pattern. ECS stateful support is inferior.

### Negative

- **Cognitive load.** Kubernetes has a steep learning curve compared to ECS. For a customer that only ever deploys AWS workloads and already uses Fargate, the tooling delta is real.
- **Control plane costs.** EKS and GKE charge for the control plane (~USD 72/month each). AKS's control plane is free. ECS has no control plane charge. At 100+ deployments this compounds.
- **Upgrade operational cost.** Kubernetes minor version upgrades happen every 3-4 months; customer platform teams must keep pace. ECS and Nomad upgrade cadences are gentler.
- **Node management.** Even with managed node groups, node AMIs and kubelet versions require lifecycle management. Fargate / App Runner eliminate this, but at the cost of losing GPUs (Fargate does not support GPUs).

### Mitigations

- The runbooks assume a moderately experienced platform SRE, not a K8s expert; explicit `kubectl` commands with expected output are included.
- The `upgrade-model.md` runbook covers vLLM upgrades; a separate but similar pattern handles K8s version upgrades (out of scope for this repo; it is the customer's responsibility).
- Helm chart defaults favor safe-but-conservative defaults (three replicas, anti-affinity on zones) to compensate for operator unfamiliarity.

## Alternatives Considered

### AWS ECS (Fargate + EC2)

Strong contender for AWS-only customers. Rejected because:

- No GPU support on Fargate. EC2 launch type is required for GPUs, which eliminates the main operational advantage of ECS (no node management).
- Cross-cloud portability is zero. A customer that swaps AWS for Azure inherits a full reimplementation.
- Policy and observability ecosystems are smaller. OPA integration with ECS is not well-trodden; Prometheus on ECS requires custom work.
- StatefulSet equivalent is clunky (service-discovery + task-placement rules).

Decision: ECS is viable for a single-cloud, AWS-only, GPU-heavy workload if cross-cloud portability is not required. We do not target that audience with this kit.

### HashiCorp Nomad

Lean and operationally simple. Rejected because:

- Customer familiarity is an order of magnitude lower than Kubernetes.
- CSI support is less mature than K8s (matters for Qdrant).
- The ecosystem of compliance-oriented admission controllers (Kyverno, OPA Gatekeeper) is less mature.
- HashiCorp relationship requires Consul + Vault + Nomad; customers without an existing HashiCorp footprint balk at the per-cluster complexity.

Decision: Nomad is elegant but does not match the "customer already knows it" criterion.

### Plain VMs + systemd

Lowest common denominator. Rejected because:

- GPU scheduling, multi-replica stateful workloads, and policy enforcement would require reimplementing Kubernetes primitives at the OS level.
- Cross-cloud portability requires thousands of lines of Ansible / Packer / cloud-init.
- Customer platform teams that can operate this are rare; the ones who can are also capable of running K8s.

Decision: Only for customers with strict "no orchestrator" policies, which are vanishingly rare in 2026.

### Serverless (Container Apps / App Runner / Cloud Run)

Appealing for stateless HTTP workloads. Rejected because:

- No GPU support in the serverless offerings we evaluated (as of the decision date). Cloud Run has added GPUs for Gemini-family models but only for Google's own workloads.
- No persistent-volume support for Qdrant.
- OPA sidecar pattern doesn't fit the serverless per-request container model cleanly.
- Customer procurement is often wary of "single-cloud serverless" for reasons of lock-in.

Decision: serverless is viable for a stateless inference-only workload in a single cloud. This kit targets a stateful, multi-cloud audience.

## Out-of-scope for this ADR

- Choice of **managed** vs. **self-managed** Kubernetes. We picked managed unconditionally. Self-managed is a valid choice in customers with a mature platform team, but it doubles the support burden on the vendor and is not reflected in this kit.
- Choice of **service mesh** (Istio / Linkerd / Cilium Service Mesh). The kit currently relies on Traefik + OPA for ingress policy; a service mesh would extend to east-west mTLS. Tracked as a future enhancement.
- Choice of **OpenShift**. OpenShift is Kubernetes with opinions; if the customer requires OpenShift specifically, the delta is ~10% of the chart (SCC vs. PodSecurityPolicy) and can be added as a fourth module or a values override. Not included in v0.1.0.
