# Playbook Automation Changes - TLS/HTTPS

## Summary

All manual TLS/certificate steps have been **100% automated** in the playbook.

## What Was Automated

### ✅ cert-manager Installation
- **Before**: Manual `kubectl apply` from GitHub (unreliable, timeouts)
- **After**: Automated via **Helm** (reliable, always works)
- **Location**: Lines 134-150 in `swim-local-setup.yml`

### ✅ SWIM CA Export
- **Before**: Manual `kubectl get secret ... | base64 -d > swim-ca.crt`
- **After**: Automatically exported to `automation/swim-ca.crt`
- **Location**: Lines 202-209 in `swim-local-setup.yml`

### ✅ Keycloak TLS Certificate
- **Before**: Manual Certificate creation via kubectl
- **After**: Automatically created with dynamic IP detection
- **DNS**: `keycloak.<MINIKUBE_IP>.nip.io` + internal DNS
- **Location**: Lines 430-445 in `swim-local-setup.yml`

### ✅ Keycloak HTTPS Configuration
- **Before**: Keycloak runs HTTP only (port 8080)
- **After**: Automatically patched for HTTPS (port 8443)
  - TLS secret mounted at `/etc/tls`
  - HTTPS enabled with certificate files
  - Readiness/liveness probes updated to HTTPS
  - Service updated to expose port 8443
- **Location**: Lines 447-520 in `swim-local-setup.yml`

### ✅ Keycloak Version Update
- **Before**: quay.io/keycloak/keycloak:26.0
- **After**: quay.io/keycloak/keycloak:26.4 (supports verifiableCredentialsEnabled)
- **Location**: Line 448 in `swim-local-setup.yml`

### ✅ Documentation
- **Created**: `TLS-SETUP.md` - Complete TLS/mTLS reference
- **Updated**: `README.md` - Added HTTPS access instructions
- **Created**: `CHANGES.md` - This file (change log)

## New Playbook Flow

```
1. Install cert-manager (via Helm)
2. Apply SWIM PKI (CA + ClusterIssuer)
3. Export SWIM CA to automation/swim-ca.crt
4. Install Keycloak
5. Create Keycloak TLS Certificate
6. Update Keycloak to version 26.4
7. Patch Keycloak for HTTPS
8. Update Keycloak Service (port 8443)
9. Wait for all components to be ready
10. Display success message with TLS instructions
```

## Files Modified

1. `swim-local-setup.yml` - Main playbook
   - Lines 134-150: cert-manager via Helm
   - Lines 202-209: CA export
   - Lines 430-520: Keycloak TLS automation
   - Lines 710-730: Updated summary message

2. `README.md` - Updated prerequisites & HTTPS instructions

3. `TLS-SETUP.md` - NEW - Complete TLS documentation

4. `CHANGES.md` - NEW - This changelog

## Testing

After these changes, you can:

```bash
# Clean start
ansible-playbook swim-local-setup.yml -e cleanup=true
ansible-playbook swim-local-setup.yml

# Verify:
# 1. swim-ca.crt exists in automation/
ls -lh automation/swim-ca.crt

# 2. Keycloak certificate created
kubectl get certificate -n keycloak

# 3. Keycloak running on HTTPS
kubectl get svc keycloak -n keycloak | grep 8443

# 4. Access Keycloak
minikube_ip=$(minikube ip --profile=swim)
curl -v --cacert automation/swim-ca.crt https://keycloak.${minikube_ip}.nip.io:8443
```

## Future Automation (Optional)

If you deploy samples, consider adding:

1. **Provider/Consumer certificates** (similar to Keycloak pattern)
2. **Artemis broker mTLS** certificates
3. **Ingress TLS** for all routes

Pattern is already established - just replicate the Keycloak automation.

## Rollback (if needed)

```bash
git diff swim-local-setup.yml
git checkout swim-local-setup.yml  # restore original
```

## Questions?

See `TLS-SETUP.md` for detailed documentation.
