# SWIM Local Automation

Ansible playbook for provisioning a local SWIM development environment on Minikube.

![Architecture](docs/minikube-architecture.svg)

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) installed
- [Podman](https://podman.io/) installed (default OCI driver for Minikube)
- [Ansible](https://docs.ansible.com/) installed (`pip install ansible`)
- [Helm](https://helm.sh/docs/intro/install/) installed (for cert-manager)
- At least 4 CPUs and 12 GB RAM available (adjusted from 8/16 for M-series Macs)

## Getting Started (New Contributors)

After cloning the repository, follow these steps to get a working local SWIM environment:

### 1. Install Prerequisites

Ensure all tools listed above are installed.

### 2. Run the Playbook

From the repository root:

```bash
ansible-playbook swim-local-setup.yml
```

This will:
- Create Minikube cluster (profile: `swim`)
- Install all operators (cert-manager, Strimzi, ArtemisCloud, SWIM)
- Deploy Keycloak with HTTPS
- **Export SWIM CA certificate** to `automation/swim-ca.crt`

⏱️ Expected duration: ~10-15 minutes

### 3. Trust the SWIM CA Certificate

The playbook automatically generates and exports the CA certificate to `automation/swim-ca.crt`.

**Import it to avoid browser SSL warnings:**

```bash
# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain swim-ca.crt

# Linux
sudo cp swim-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# Windows (PowerShell as Administrator)
certutil -addstore -f "ROOT" swim-ca.crt

# Firefox (all platforms)
# Preferences → Privacy & Security → Certificates → View Certificates → Import swim-ca.crt
```

### 4. Client Certificates (for mTLS access)

SWIM applications require **mutual TLS (mTLS)** for external access. When you deploy samples, the playbook exports client certificates:

**Certificates location:**
- `automation/swim-ca.crt` (CA certificate - trust this in your browser/system)
- `automation/swim-client.crt` (client certificate)
- `automation/swim-client.key` (client private key)

**Usage example:**
```bash
# Access SWIM Consumer Validator with mTLS
curl https://swim-consumervalidator.swim-consumervalidator.svc.cluster.local/q/health \
  --cacert swim-ca.crt \
  --cert swim-client.crt \
  --key swim-client.key
```

**Important notes:**
- Client certificates are exported **only** when `deploy_samples=true`
- Pods inside the cluster use mounted secrets (no manual certificate configuration needed)
- Same client certificate works for all SWIM applications

### 5. Start Minikube Tunnel (macOS M1 with Podman only)

If you're on **macOS with M1/M2/M3 chip** using Podman driver:

```bash
# Open a new terminal and keep this running
sudo minikube tunnel --profile=swim
```

*(Other platforms skip this step - services are accessible via Minikube IP directly)*

### 6. Access Services

**macOS M1/M2/M3 (Podman):**
- Keycloak: https://keycloak.127.0.0.1.nip.io
- Admin credentials: `admin` / `admin`
- Realm: `swim`

**Other platforms:**
```bash
# Get Minikube IP
minikube ip --profile=swim
# Example output: 192.168.49.2

# Access Keycloak
https://keycloak.192.168.49.2.nip.io
```

### 7. Deploy Sample Applications (Optional)

```bash
ansible-playbook swim-local-setup.yml -e deploy_samples=true
```

### 8. Verify, happy path

After the playbook finishes (with or without samples), run:

```bash
# All operators running
kubectl get pods -A | grep -E "cert-manager|strimzi|artemis|swim-kubernetes-operator"

# Keycloak accessible (macOS M1 with tunnel)
curl -sk https://keycloak.127.0.0.1.nip.io/realms/swim/.well-known/openid-configuration | jq .issuer

# After deploy_samples=true, DNOTAM consumer health
curl -sk https://swim-dnotam-consumer.127.0.0.1.nip.io/q/health \
  --cacert swim-ca.crt --cert swim-client.crt --key swim-client.key | jq .status
```

Expected: all operator pods `Running`, Keycloak OIDC discovery responds, consumer health returns `"UP"`.

## Makefile shortcuts

```bash
make setup               # infrastructure only (no samples)
make setup-samples       # infrastructure + deploy sample CRs
make destroy             # tear down the Minikube environment
make cluster-only        # create Minikube cluster only (no operators)

make setup-samples BUILD_OPERATOR=true BUILD_APPS=true   # build images locally
```

## Quick Start (Existing Users)

```bash
# Full setup (infrastructure only, no samples)
ansible-playbook swim-local-setup.yml

# Full setup with sample CRs deployed
ansible-playbook swim-local-setup.yml -e deploy_samples=true

# Build application images locally instead of pulling from quay.io
ansible-playbook swim-local-setup.yml -e build_app_images=true -e deploy_samples=true
```

## Tags

Run specific phases:

```bash
# Only create Minikube cluster
ansible-playbook swim-local-setup.yml --tags minikube

# Only install dependencies (cert-manager, Strimzi, ArtemisCloud)
ansible-playbook swim-local-setup.yml --tags dependencies

# Only install SWIM operator + Keycloak
ansible-playbook swim-local-setup.yml --tags operator

# Only deploy sample CRs
ansible-playbook swim-local-setup.yml --tags samples -e deploy_samples=true
```

## Lifecycle

```bash
# Restart an existing profile
ansible-playbook swim-local-setup.yml -e restart=true

# Destroy the environment
ansible-playbook swim-local-setup.yml -e cleanup=true
```

## What Gets Installed

| Component                     | Namespace                        |
|-------------------------------|----------------------------------|
| cert-manager                  | `cert-manager`                   |
| SWIM PKI (CA + ClusterIssuer) | `cert-manager`                   |
| Strimzi Kafka Operator        | `strimzi-system`                 |
| ArtemisCloud Operator         | `activemq-artemis-operator`      |
| Keycloak                      | `keycloak`                       |
| SWIM Kubernetes Operator      | `swim-kubernetes-operator-system`|

> **Note:** StreamsHub Console Operator is intentionally **not** installed.
> It consumes ~125 OS threads and is not required for SWIM functionality.
> The `kafka.kafkaConsoleEnabled` field in CRs defaults to `false` for the same reason.

When `deploy_samples=true`:

| Sample CR                       | Namespace                 |
|---------------------------------|---------------------------|
| DNOTAM Consumer Validator       | `swim-external-provider`  |
| DNOTAM Consumer                 | `swim-sandbox`            |
| DNOTAM Provider                 | `swim-sandbox`            |

## Configuration

All variables are in `group_vars/all.yml`. Override any variable on the command line:

```bash
ansible-playbook swim-local-setup.yml -e minikube_cpus=4 -e minikube_memory=8192
```

### SWIM Operator Image

By default, the playbook uses a pre-built operator image from Quay.io. You can control this behavior:

**Use pre-built image (default, recommended):**
```bash
# Uses operator_image from group_vars/all.yml (default: quay.io/masales/swim-kubernetes-operator:latest)
ansible-playbook swim-local-setup.yml

# Or specify a different version/tag
ansible-playbook swim-local-setup.yml -e operator_image=quay.io/masales/swim-kubernetes-operator:v1.2.3
```

**Build image locally (for development):**
```bash
# Build from source and load into Minikube
ansible-playbook swim-local-setup.yml -e build_operator_image=true

# Build with custom tag
ansible-playbook swim-local-setup.yml -e build_operator_image=true -e operator_image=controller:dev
```

**Configuration variables:**
- `build_operator_image`: `false` (pull from registry, default) or `true` (build locally from source)
- `operator_image`: Image name/tag (default: `quay.io/masales/swim-kubernetes-operator:latest`)

**Examples:**
```bash
# Use latest stable from Quay.io (default behavior)
ansible-playbook swim-local-setup.yml

# Use specific version from Quay.io
ansible-playbook swim-local-setup.yml -e operator_image=quay.io/masales/swim-kubernetes-operator:v2.0.0

# Development: build and test local changes
ansible-playbook swim-local-setup.yml -e build_operator_image=true -e operator_image=controller:local-dev
```

### SWIM Application Images (Consumer & Provider)

By default, the playbook uses pre-built images from Quay.io for the DNOTAM Consumer and Provider.

**Use pre-built images (default, recommended):**
```bash
ansible-playbook swim-local-setup.yml -e deploy_samples=true
# Pulls quay.io/masales/swim-dnotam-consumer:latest
# Pulls quay.io/masales/swim-dnotam-provider:latest
```

**Build application images locally (for development):**
```bash
ansible-playbook swim-local-setup.yml -e build_app_images=true -e deploy_samples=true
```

When `build_app_images=true`, the playbook:
1. Detects the Minikube VM architecture automatically (`uname -m`)
2. Runs `mvn clean package -DskipTests` for consumer and provider
3. Builds images with `--platform linux/arm64` or `linux/amd64` accordingly
4. Exports each image to `/tmp/*.tar` and loads directly into Minikube
5. Patches `imagePullPolicy: IfNotPresent` so Minikube uses the local image

> **Architecture detection is automatic**, you do not need to specify the platform manually.
> This avoids the `exec format error` that occurs when an `amd64` image runs on an `arm64` VM (e.g., macOS M1/M2/M3).

**Configuration variables:**
| Variable           | Default                                          | Description                            |
|--------------------|--------------------------------------------------|----------------------------------------|
| `build_app_images` | `false`                                          | Build consumer/provider images locally |
| `consumer_image`   | `quay.io/masales/swim-dnotam-consumer:latest`    | Consumer image name/tag                |
| `provider_image`   | `quay.io/masales/swim-dnotam-provider:latest`    | Provider image name/tag                |

---

## Network Access & HTTPS

All services use **HTTPS** with certificates signed by the SWIM internal CA.

### Accessing Services

**macOS M1 with Podman driver:**

Services are accessed via `minikube tunnel` (requires sudo, leave running in separate terminal):

```bash
sudo minikube tunnel --profile=swim
```

Access URLs (port 443 is implicit):
- `https://keycloak.127.0.0.1.nip.io`
- `https://swim-dnotam-provider.127.0.0.1.nip.io`
- `https://swim-ed254-provider.127.0.0.1.nip.io`

**Other platforms (Docker driver, Linux, etc.):**

Dynamic hostnames use [nip.io](https://nip.io/) with the Minikube IP:

- `https://keycloak.<minikube-ip>.nip.io`
- `https://swim-dnotam-provider.<minikube-ip>.nip.io`
- `https://swim-ed254-provider.<minikube-ip>.nip.io`

### Trust SWIM CA (Required)

After running the playbook, the SWIM CA certificate is exported to `automation/swim-ca.crt`.

**Import it to trust HTTPS connections:**

```bash
# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain automation/swim-ca.crt

# Linux
sudo cp automation/swim-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# Windows
certutil -addstore -f "ROOT" automation\swim-ca.crt
```

**Firefox** (all platforms): Preferences → Certificates → Import `swim-ca.crt`

📘 **Detailed TLS documentation**: See [TLS-SETUP.md](./TLS-SETUP.md)
