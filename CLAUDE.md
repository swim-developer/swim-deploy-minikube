# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ansible playbook for provisioning a local **SWIM (System Wide Information Management)** development environment on Minikube. SWIM is the ICAO-mandated global standard for aviation information exchange, requiring ANSPs to adopt service-oriented data sharing by 2026. This repo automates the deployment of all infrastructure components needed to develop and test SWIM services locally.

## Commands

```bash
# Full setup (infrastructure only)
make setup
# or: ansible-playbook swim-local-setup.yml

# Full setup with sample SWIM CRs deployed
make setup-samples
# or: ansible-playbook swim-local-setup.yml -e deploy_samples=true

# Build operator/app images locally instead of pulling from quay.io
make setup-samples BUILD_OPERATOR=true BUILD_APPS=true

# Tear down the Minikube environment
make destroy

# Create Minikube cluster only (no operators)
make cluster-only

# Run specific phases via tags
ansible-playbook swim-local-setup.yml --tags minikube
ansible-playbook swim-local-setup.yml --tags dependencies
ansible-playbook swim-local-setup.yml --tags operator
ansible-playbook swim-local-setup.yml --tags samples -e deploy_samples=true

# Restart existing profile / destroy
ansible-playbook swim-local-setup.yml -e restart=true
ansible-playbook swim-local-setup.yml -e cleanup=true
```

## Architecture

The playbook provisions a Minikube cluster (profile: `swim`) with these components:

| Component | Namespace |
|---|---|
| cert-manager + SWIM PKI (CA + ClusterIssuer) | `cert-manager` |
| Strimzi Kafka Operator | `strimzi-system` |
| ArtemisCloud Operator | `activemq-artemis-operator` |
| Keycloak (realm: `swim`) | `keycloak` |
| SWIM Kubernetes Operator | `swim-kubernetes-operator-system` |

When `deploy_samples=true`, sample CRs are deployed:

| Sample | Namespace |
|---|---|
| DNOTAM Consumer Validator | `swim-external-provider` |
| DNOTAM Consumer + Provider + Kafka | `swim-sandbox` |
| ED-254 Consumer Validator | `swim-ed254-cv` |
| Provider Validator | `swim-providervalidator` |

### Playbook Execution Order

`swim-local-setup.yml` is a single-file playbook with tagged phases: `cleanup` > `restart` > `minikube` > `dependencies` > `operator` > `samples`. Each phase guards its tasks with tags and conditional variables.

### External Dependencies

The playbook references sibling directories for manifests and source code:

- `../swim-operator/swim-kubernetes-operator/` — operator manifests, PKI config, Keycloak config
- `../compose/keycloak/realm/` — Keycloak realm JSON
- `../compose/samples/` — sample CR YAML files
- `../swim-developer/` — Java source for consumer/provider apps (when `build_app_images=true`)

### Configuration

All variables are in `group_vars/all.yml`. Key variables: `minikube_profile`, `minikube_cpus`, `minikube_memory`, `minikube_driver`, `deploy_samples`, `build_operator_image`, `build_app_images`, `operator_image`, `consumer_image`, `provider_image`.

### TLS/mTLS

All services use HTTPS with certificates signed by a self-signed SWIM CA managed by cert-manager. The PKI hierarchy: `selfsigned-bootstrap` > `swim-ca` (root CA) > `swim-ca-issuer` (ClusterIssuer signs all service certs). Dynamic hostnames use nip.io with the Minikube IP. Certificates auto-renew 30 days before expiration.

Exported artifacts: `swim-ca.crt` (CA cert), `swim-client.crt` and `swim-client.key` (client certs, only when `deploy_samples=true`).

### macOS M-series with Podman

Requires `sudo minikube tunnel --profile=swim` running in a separate terminal. Services accessible at `https://<service>.127.0.0.1.nip.io`. Other platforms use `https://<service>.<minikube-ip>.nip.io`.

## SWIM Domain Rules

### Consumer-to-Validator Connectivity (absolute rule)

A Consumer NEVER connects to the Provider of the same module. The "provider" from a Consumer's perspective is ALWAYS a Consumer Validator. In any Consumer CR, `amqpBrokerHost` and `subscriptionManager.url` MUST point to the consumer-validator endpoints, never to provider endpoints.

### Naming

Every artifact name must be unambiguous and fully qualified. Use `swim-dnotam-consumer`, never just `swim-consumer`, when multiple consumer types exist.

### Deployment Commands

Ansible/kubectl/helm commands that modify a running cluster require explicit user confirmation before execution. Read-only commands (`kubectl get`, `kubectl describe`, `kubectl logs`) are allowed without confirmation.

### AI Authorship

Never add `Co-Authored-By` or any AI tool reference to commit messages. A global git hook at `~/.config/git/hooks/commit-msg` strips these automatically.

