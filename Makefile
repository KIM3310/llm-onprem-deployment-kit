# llm-onprem-deployment-kit
#
# Enterprise deployment toolkit for LLM workloads in private,
# hybrid, and airgapped clouds.
#
# Targets here are intentionally thin wrappers around the underlying
# tools (terraform, helm, kubectl, shellcheck) so that they work
# equally well on engineer laptops and in CI.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------
TERRAFORM        ?= terraform
HELM             ?= helm
KUBECTL          ?= kubectl
SHELLCHECK       ?= shellcheck
YAMLLINT         ?= yamllint

REPO_ROOT        := $(shell pwd)
TF_MODULE_DIRS   := terraform/modules/azure-aks terraform/modules/aws-eks terraform/modules/gcp-gke
TF_EXAMPLE_DIRS  := terraform/examples/airgapped-enterprise terraform/examples/dev-sandbox
HELM_CHART_DIR   := helm/llm-stack
NAMESPACE        ?= llm-stack
RELEASE          ?= llm-stack

# Default values file used by `make deploy-stack`; override from CLI:
#   make deploy-stack VALUES=helm/llm-stack/values-airgap.yaml
VALUES           ?= $(HELM_CHART_DIR)/values.yaml

# ----------------------------------------------------------------------------
# Help
# ----------------------------------------------------------------------------
.PHONY: help
help:
	@echo "llm-onprem-deployment-kit targets:"
	@echo ""
	@echo "  validate           Terraform fmt/validate + Helm lint + shellcheck"
	@echo "  fmt                Run terraform fmt -recursive on all modules"
	@echo "  plan-azure         terraform plan for the Azure example"
	@echo "  plan-aws           terraform plan for the AWS example"
	@echo "  plan-gcp           terraform plan for the GCP example"
	@echo "  apply-azure        terraform apply for the Azure example"
	@echo "  apply-aws          terraform apply for the AWS example"
	@echo "  apply-gcp          terraform apply for the GCP example"
	@echo "  destroy-azure      terraform destroy for the Azure example"
	@echo "  destroy-aws        terraform destroy for the AWS example"
	@echo "  destroy-gcp        terraform destroy for the GCP example"
	@echo "  deploy-stack       helm upgrade --install the llm-stack chart"
	@echo "  diff-stack         helm diff against currently installed release"
	@echo "  uninstall-stack    helm uninstall the llm-stack chart"
	@echo "  status             kubectl get status of all llm-stack resources"
	@echo "  smoke-test         Run scripts/smoke-test.sh against the cluster"
	@echo "  diag-bundle        Collect a support diagnostic bundle"
	@echo "  clean              Remove local terraform and helm caches"
	@echo ""
	@echo "Variables:"
	@echo "  NAMESPACE=$(NAMESPACE) RELEASE=$(RELEASE) VALUES=$(VALUES)"

# ----------------------------------------------------------------------------
# Validation
# ----------------------------------------------------------------------------
.PHONY: validate fmt tf-validate helm-lint shell-lint

validate: tf-validate helm-lint shell-lint
	@echo "[OK] All validation checks passed."

fmt:
	$(TERRAFORM) fmt -recursive terraform/

tf-validate:
	@for d in $(TF_MODULE_DIRS) $(TF_EXAMPLE_DIRS); do \
	  echo "==> terraform validate $$d"; \
	  (cd $$d && $(TERRAFORM) init -backend=false -input=false -no-color >/dev/null && \
	    $(TERRAFORM) validate -no-color) || exit 1; \
	done

helm-lint:
	$(HELM) lint $(HELM_CHART_DIR)
	$(HELM) lint $(HELM_CHART_DIR) --values $(HELM_CHART_DIR)/values-airgap.yaml
	$(HELM) lint $(HELM_CHART_DIR) --values $(HELM_CHART_DIR)/values-dev.yaml

shell-lint:
	$(SHELLCHECK) scripts/*.sh tests/*.sh examples/**/scripts/*.sh

# ----------------------------------------------------------------------------
# Terraform lifecycle (examples)
# ----------------------------------------------------------------------------
.PHONY: plan-azure plan-aws plan-gcp apply-azure apply-aws apply-gcp destroy-azure destroy-aws destroy-gcp

plan-azure:
	cd terraform/modules/azure-aks/examples/basic && $(TERRAFORM) init -input=false && $(TERRAFORM) plan -out=tfplan

plan-aws:
	cd terraform/modules/aws-eks/examples/basic && $(TERRAFORM) init -input=false && $(TERRAFORM) plan -out=tfplan

plan-gcp:
	cd terraform/modules/gcp-gke/examples/basic && $(TERRAFORM) init -input=false && $(TERRAFORM) plan -out=tfplan

apply-azure:
	cd terraform/modules/azure-aks/examples/basic && $(TERRAFORM) apply -input=false -auto-approve tfplan

apply-aws:
	cd terraform/modules/aws-eks/examples/basic && $(TERRAFORM) apply -input=false -auto-approve tfplan

apply-gcp:
	cd terraform/modules/gcp-gke/examples/basic && $(TERRAFORM) apply -input=false -auto-approve tfplan

destroy-azure:
	cd terraform/modules/azure-aks/examples/basic && $(TERRAFORM) destroy -input=false -auto-approve

destroy-aws:
	cd terraform/modules/aws-eks/examples/basic && $(TERRAFORM) destroy -input=false -auto-approve

destroy-gcp:
	cd terraform/modules/gcp-gke/examples/basic && $(TERRAFORM) destroy -input=false -auto-approve

# ----------------------------------------------------------------------------
# Helm lifecycle
# ----------------------------------------------------------------------------
.PHONY: deploy-stack diff-stack uninstall-stack

deploy-stack:
	$(KUBECTL) get namespace $(NAMESPACE) >/dev/null 2>&1 || $(KUBECTL) create namespace $(NAMESPACE)
	$(HELM) upgrade --install $(RELEASE) $(HELM_CHART_DIR) \
	  --namespace $(NAMESPACE) \
	  --values $(VALUES) \
	  --atomic --timeout 10m

diff-stack:
	$(HELM) diff upgrade $(RELEASE) $(HELM_CHART_DIR) \
	  --namespace $(NAMESPACE) \
	  --values $(VALUES)

uninstall-stack:
	$(HELM) uninstall $(RELEASE) --namespace $(NAMESPACE)

# ----------------------------------------------------------------------------
# Operational
# ----------------------------------------------------------------------------
.PHONY: status smoke-test diag-bundle clean

status:
	@echo "==> Pods"
	$(KUBECTL) get pods -n $(NAMESPACE) -o wide
	@echo ""
	@echo "==> Services"
	$(KUBECTL) get svc -n $(NAMESPACE)
	@echo ""
	@echo "==> HPA"
	$(KUBECTL) get hpa -n $(NAMESPACE)
	@echo ""
	@echo "==> PVCs"
	$(KUBECTL) get pvc -n $(NAMESPACE)

smoke-test:
	scripts/smoke-test.sh --namespace $(NAMESPACE) --release $(RELEASE)

diag-bundle:
	scripts/collect-diag-bundle.sh --namespace $(NAMESPACE) --release $(RELEASE)

clean:
	@echo "Removing local terraform caches..."
	@find terraform -type d -name .terraform -prune -exec rm -rf {} +
	@find terraform -type f -name '*.tfplan' -delete
	@find terraform -type f -name '.terraform.lock.hcl' -delete
	@echo "Clean complete."
