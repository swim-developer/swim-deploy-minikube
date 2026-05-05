# SWIM TLS/mTLS Setup

## Overview

The SWIM local environment uses **cert-manager** to automatically generate and manage TLS certificates for all services.

## Architecture

```
cert-manager (Helm chart)
    ↓
SWIM PKI (swim-pki.yaml)
    ├── selfsigned-bootstrap (ClusterIssuer)
    ├── swim-ca (Certificate - Root CA, 10 years validity)
    └── swim-ca-issuer (ClusterIssuer - signs all service certificates)
         ↓
Service Certificates (auto-generated)
    ├── keycloak-tls (Keycloak HTTPS)
    ├── swim-dnotam-provider-tls
    ├── swim-ed254-provider-tls
    └── artemis-broker-tls (mTLS)
```

## How It Works

### 1. Automatic Certificate Generation

When you run the playbook:

```bash
ansible-playbook swim-local-setup.yml
```

The following happens automatically:

1. **cert-manager installation** (via Helm - more reliable than kubectl apply)
2. **SWIM CA creation** (self-signed root CA, valid for 10 years)
3. **ClusterIssuer setup** (swim-ca-issuer) - signs certificates for all services
4. **Service certificates creation**:
   - Keycloak: `keycloak-tls-secret` with DNS: `keycloak.<MINIKUBE_IP>.nip.io`
   - Providers/Consumers: created when samples are deployed
5. **CA export** to `automation/swim-ca.crt`

### 2. Dynamic IP Handling (nip.io)

**Problem**: Minikube IP can change between restarts.

**Solution**: The playbook detects IP dynamically:

```yaml
minikube_ip: "{{ minikube_ip_result.stdout | trim }}"
keycloak_host: "keycloak.{{ minikube_ip }}.nip.io"
```

Certificates include:
- External DNS: `service.<IP>.nip.io` (for browser access)
- Internal DNS: `service.namespace.svc.cluster.local` (for inter-pod communication)

### 3. Certificate Auto-Renewal

- Certificates are valid for **1 year** (8760h)
- Auto-renewal starts **30 days before expiration** (720h)
- cert-manager handles renewal automatically
- Pods restart automatically when certificates are updated

## Trust SWIM CA (Required for Browsers)

After running the playbook, import `automation/swim-ca.crt`:

### macOS
```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain automation/swim-ca.crt
```

### Linux
```bash
sudo cp automation/swim-ca.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### Windows
```powershell
certutil -addstore -f "ROOT" automation\swim-ca.crt
```

### Firefox (all OS)
1. Preferences → Privacy & Security → Certificates
2. View Certificates → Authorities → Import
3. Select `swim-ca.crt`
4. Trust for identifying websites ✓

## Verify HTTPS

```bash
# Get Minikube IP
minikube ip --profile=swim
# Output: 192.168.49.2

# Access Keycloak via HTTPS
curl -v --cacert automation/swim-ca.crt https://keycloak.192.168.49.2.nip.io:8443

# Or in browser (after importing CA):
https://keycloak.192.168.49.2.nip.io:8443
```

## Manual Certificate Creation (for new services)

If you add a new SWIM service, create a Certificate resource:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-service-tls
  namespace: my-namespace
spec:
  secretName: my-service-tls-secret
  duration: 8760h
  renewBefore: 720h
  isCA: false
  usages:
    - digital signature
    - key encipherment
    - server auth
    - client auth  # for mTLS
  dnsNames:
    - my-service.192.168.49.2.nip.io
    - my-service.my-namespace.svc.cluster.local
  issuerRef:
    name: swim-ca-issuer
    kind: ClusterIssuer
```

Then mount the secret in your deployment:

```yaml
spec:
  containers:
  - name: my-service
    volumeMounts:
    - name: tls
      mountPath: /etc/tls
      readOnly: true
  volumes:
  - name: tls
    secret:
      secretName: my-service-tls-secret
```

## Mutual TLS (mTLS) Between Services

All certificates include `client auth` usage, enabling mTLS:

**Example**: DNOTAM Provider → Artemis Broker

```
Provider presents:
  tls.crt: swim-dnotam-provider.crt
  ca.crt: swim-ca.crt

Broker validates:
  ✓ Certificate signed by swim-ca
  ✓ CN matches expected identity

Broker presents:
  tls.crt: artemis-broker.crt
  ca.crt: swim-ca.crt

Provider validates:
  ✓ Certificate signed by swim-ca
  ✓ CN matches expected identity

Result: Mutual authentication ✓
```

## Troubleshooting

### Certificate not ready
```bash
kubectl describe certificate <name> -n <namespace>
# Check Events section for errors
```

### Manual certificate renewal
```bash
kubectl delete certificate <name> -n <namespace>
# cert-manager recreates it automatically
```

### Export any service certificate
```bash
kubectl get secret <service>-tls-secret -n <namespace> \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > service.crt
```

### Verify certificate details
```bash
openssl x509 -in service.crt -noout -text
```

## IP Changed? Update Certificates

If Minikube IP changes:

```bash
# Get new IP
NEW_IP=$(minikube ip --profile=swim)

# Update Certificate
kubectl patch certificate keycloak-tls -n keycloak --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/dnsNames/0\",\"value\":\"keycloak.${NEW_IP}.nip.io\"}]"

# cert-manager automatically:
# 1. Detects change
# 2. Generates new certificate
# 3. Updates Secret
# 4. Pods restart with new cert
```

## Production Considerations

For production, consider:

1. **Let's Encrypt**: Replace `swim-ca-issuer` with `letsencrypt-prod`
2. **Real DNS**: Replace nip.io with actual domain
3. **External cert-manager**: Use organization's PKI instead of self-signed CA
4. **Certificate monitoring**: Set up alerts for expiring certificates
5. **Secret management**: Use Vault/sealed-secrets for private keys

## Files

- `swim-ca.crt` - Root CA certificate (export this)
- `swim-pki.yaml` - PKI infrastructure manifests
- `swim-local-setup.yml` - Ansible playbook (automated setup)
- `group_vars/all.yml` - Configuration variables

## Related Documentation

- cert-manager: https://cert-manager.io/docs/
- Kubernetes TLS: https://kubernetes.io/docs/concepts/services-networking/ingress/#tls
- nip.io: https://nip.io/
