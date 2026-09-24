# LLM On-Prem Deployment Kit in Selected Work

Updated 2026-09-07.

This project adds **infrastructure as code · kubernetes · deployment verification** to the portfolio. Selection is based on distinct, inspectable implementation rather than a particular employment role or startup category.

Terraform formatting, initialization and validation pass in all 8 module/example directories. Default, development and airgap Helm lint/render contracts and ShellCheck pass. The Kubernetes workflow deploys the chart with real Traefik/TLS and an explicitly synthetic inference protocol fixture; its artifact lists the checks performed.

No GPU inference, model-quality benchmark, customer cloud provisioning, network-policy enforcement, Qdrant persistence or offline airgap installation is claimed. The kind fixture proves chart/process/network wiring; production image/model compatibility still requires GPU deployment validation.

[Implementation entry points](../README.md) · [Verification](VERIFICATION.md)
