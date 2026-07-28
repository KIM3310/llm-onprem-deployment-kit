# Revenue Architecture - llm-onprem-deployment-kit

This document turns the repository architecture into a zero-to-low-cost service path. It is not a revenue guarantee; it defines the product boundary, free-tier launch stack, metering hooks, and upgrade path needed to test willingness to pay before taking on fixed infrastructure cost.

## Productized Offer

| Layer | Decision |
| --- | --- |
| Target buyer / user | platform team deploying private LLM workloads into regulated or air-gapped environments |
| Productized offer | deployment kit for Kubernetes, Helm, Terraform, observability, and security controls |
| First paid SKU | fixed-scope Private AI Readiness Sprint for one customer-owned deployment decision |
| Free lead magnet | free reference architecture and Helm/Terraform starter kit |
| Paid expansion | controlled pilot or implementation phase only after the readiness decision and production gaps are accepted |
| Data / workflow moat | multi-cloud deployment recipes, security mappings, upgrade runbooks, and tested Helm/Terraform patterns |
| Private inquiry | https://kim3310-doeon-kim-portfolio.pages.dev/?offer=llm-onprem-deployment-kit&inquiry=private-ai-readiness-sprint#private-inquiry |

## Low-Cost Launch Stack

| Concern | Default choice |
| --- | --- |
| Build and coding loop | OpenCode, Kimi Code CLI, Freebuff, Lovable, Ollama-assisted local agents |
| Public front door | Cloudflare Pages first, with Vercel/Netlify as alternate static front doors |
| Lead intake | Central private inquiry form for business contact and scope only |
| AI inference | Synthetic or customer-approved evaluation in the customer account |
| Storage / exports | Public repository artifacts for examples; customer storage for all private data and evidence |
| Repo-specific launch path | GitHub Pages architecture, local validation, then customer-owned infrastructure only after scope approval |

Do not run a free public GPU service to market this offer. The public surface demonstrates architecture and validation; paid work begins with a bounded decision sprint in or against the customer's environment.

## System Shape

```mermaid
flowchart LR
  Visitor["Visitor or operator"] --> Demo["Free public demo / docs"]
  Demo --> Capture["Private scope intake"]
  Capture --> Score["Use-case readiness scorecard"]
  Score --> Boundary["Ownership and control boundary"]
  Boundary --> Plan["Evaluation and deployment adaptation plan"]
  Plan --> Decision["Go or no-go record"]
  Decision --> Pilot["Separately scoped controlled pilot"]
```

## Commercial Boundary

- Free: architecture, module/chart source, static validation, and synthetic review material.
- Paid: one use-case scorecard, responsibility matrix, data/control boundary, customer-specific adaptation plan, cost/capacity risks, evaluation plan, rollback plan, and go or no-go record.
- Excluded: vendor-hosted customer data, turnkey production deployment, end-user identity, tenant authorization, rate limits, clustered Qdrant, HA/DR evidence, certification, and SLA.

## 30-Day Revenue Test

1. Keep one CTA to the private `private-ai-readiness-sprint` intake.
2. Qualify one use case, data sensitivity, latency/capacity target, residency constraint, and customer owner.
3. Run the static baseline and document gaps before any cluster spend.
4. Produce a fixed-scope readiness decision instead of promising a production deployment.
5. Track qualified inquiries, scoped sprints, go/no-go decisions, controlled pilots, and implementation conversion.

## Cost Guardrails

- Keep the public surface static and synthetic.
- Do not provision GPU clusters before the customer accepts a use case, capacity target, budget, and teardown owner.
- Use customer-owned cloud billing, registries, secrets, storage, models, and logs.
- Set budget alerts and teardown dates before controlled deployment.
- Do not build checkout or subscription machinery before the fixed-scope sprint converts.

## Paid Conversion Architecture

The paid sprint is a decision product. A controlled pilot, implementation, or support retainer is sold separately only when the scorecard and gap register justify it.
