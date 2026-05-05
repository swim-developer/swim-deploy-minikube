.DEFAULT_GOAL := help

.PHONY: help setup setup-samples destroy cluster-only

help:
	@echo "Targets:"
	@echo "  setup          Provision full Minikube SWIM environment (no samples)"
	@echo "  setup-samples  Same as setup, then deploy sample CRs"
	@echo "  destroy        Tear down the Minikube environment"
	@echo "  cluster-only   Create Minikube cluster only (no operators)"
	@echo ""
	@echo "Build local images before deploying:"
	@echo "  make setup-samples BUILD_OPERATOR=true BUILD_APPS=true"

BUILD_OPERATOR ?= false
BUILD_APPS     ?= false

setup:
	ansible-playbook swim-local-setup.yml \
	  -e build_operator_image=$(BUILD_OPERATOR) \
	  -e build_app_images=$(BUILD_APPS)

setup-samples:
	ansible-playbook swim-local-setup.yml \
	  -e deploy_samples=true \
	  -e build_operator_image=$(BUILD_OPERATOR) \
	  -e build_app_images=$(BUILD_APPS)

destroy:
	ansible-playbook swim-local-setup.yml -e cleanup=true

cluster-only:
	ansible-playbook swim-local-setup.yml --tags minikube
