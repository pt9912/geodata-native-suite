
# RKE2 + Vault (Kubernetes Auth, KV v2)

Dieses Modul:
- aktiviert **auth/kubernetes**
- konfiguriert Kubernetes-API für TokenReview
- erstellt KV v2 Mount `kv/`
- legt Policy `geodata-read` (read-only auf `kv/data/geodata/*`) an
- mappt ServiceAccounts (`fetch`, `index-service`) im Namespace `geodata` auf die Policy.

## Nutzung
```bash
export VAULT_ADDR=https://vault.geodata.local:8200
export VAULT_TOKEN=<root-or-bootstrap-token>

terraform init
terraform apply -var='kubernetes_host=https://10.0.0.1:6443'   -var='kubernetes_ca_cert_base64=$(cat /etc/rancher/rke2/rke2.yaml | awk "/certificate-authority-data/ {{print $2}}")'   -var='token_reviewer_jwt=$(kubectl -n geodata get secret $(kubectl -n geodata get sa vault-auth -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}")'
```
> Vorher im Cluster: `kubectl -n geodata create sa vault-auth`
