# Security Policy

## Supported Versions

Security fixes are applied to the default branch. Consumers should run the latest commit or latest tagged release when available.

## Reporting a Vulnerability

Do not open a public issue for suspected vulnerabilities. Use GitHub private vulnerability reporting if it is enabled for this repository, or contact the repository owner through their GitHub profile.

Please include:

- A clear description of the issue and affected deployment component
- Reproduction steps or a minimal proof of concept
- Potential impact and any known mitigations
- Whether cluster credentials, registry credentials, model weights, or customer data may be exposed

## Security Expectations

- Never commit kubeconfigs, Terraform state, cloud credentials, registry tokens, or private model artifacts.
- Review generated manifests for least privilege before applying them to a cluster.
- Run local verification before merging:

```bash
bash -n scripts/*.sh
```
