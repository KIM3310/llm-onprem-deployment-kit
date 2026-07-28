# Ad-Supported Resource and Aggregate Data Architecture

Repository: `llm-onprem-deployment-kit`

## Public Resource Model

Free private LLM deployment readiness map for Terraform, Helm, and air-gapped operations.

- Audience: infrastructure architects and private AI platform teams
- Central resource: https://kim3310-doeon-kim-portfolio.pages.dev/resources/llm-onprem-deployment-kit/
- Live system: https://kim3310.github.io/llm-onprem-deployment-kit/
- Advertising boundary: ads allowed only on public deployment-readiness guides; deployment plans, credentials, cluster details, and dashboards are ad-free
- Current ad state: code-ready on the central resource; serving depends on Google AdSense site approval and consent policy.

## Readiness Utility

The central resource turns the repository architecture into a practical review checklist:

- **Architecture Summary:** Repository-local proof surface for agent runtime reliability and AI workflow orchestration, backed by Terraform infrastructure modules, GitHub Actions validation.
- **Runtime And Data Flow:** Primary domain: agent runtime reliability and AI workflow orchestration.
- **Cloud Or Local Deployment Boundary:** Operating model: stateless runtimes, provider adapters, queue-aware execution, telemetry, and controlled secret boundaries
- **Deployment patterns:** Infrastructure-as-code entrypoint with explicit variables, outputs, and provider boundaries Stateless agent gateway with provider abstraction, retries, cost controls, and trace capture
- **Control boundaries:** identity boundary and least-privilege service access environment separation for local, staging, and managed runtime paths secret storage outside source and deterministic fallback for missing credentials observability hooks for logs, metrics, traces, and audit events rollback path...

The checklist state remains in the visitor's browser and is not transmitted.

## Aggregate Data Boundary

- Data asset: anonymous aggregate private deployment topic demand and guide-open counts
- Sensitivity class: high-trust-b2b
- Allowed events: `resource_view`, `resource_cta_click`, `architecture_doc_open`, `privacy_support_open`
- Prohibited fields: `raw_input`, `url`, `referrer`, `title`, `user_id`, `session_id`, `ip_address`, `device_id`, `payment_detail`
- Consent defaults to off.
- DNT and Global Privacy Control fail closed.
- Events are reduced to repository, allowlisted event, public surface, and consent-policy version.
- Personal, sensitive, raw, event-level, or re-identifiable data is never offered for sale.

## Storage Path

```text
Public resource
  -> consent and privacy-signal gate
  -> Cloudflare Pages event API
  -> rate-limited daily aggregate counter
  -> public benchmark response
  -> Firebase public aggregate data mart
```

Cloudflare D1 holds operational counters. Firestore project `kim3310-free-tools` is the deny-by-default public aggregate data mart. Private inquiries remain isolated from telemetry.
