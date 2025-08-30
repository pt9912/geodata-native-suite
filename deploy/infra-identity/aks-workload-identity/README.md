
# AKS Workload Identity – Federated Credentials + RBAC

Erstellt User Assigned Managed Identities (UAMI) + **Federated Identity Credentials** für:
- `external-dns` (Namespace `external-dns`) → Azure DNS Zone Contributor
- `fetch` (Namespace `geodata`) → Key Vault **Secrets User**
- `index-service` (Namespace `geodata`) → Key Vault **Secrets User**

## Nutzung
```bash
terraform init
terraform apply -var='location=westeurope' -var='resource_group=rg-geodata'   -var='cluster_oidc_issuer_url=https://oidc.prod-aks.azure.com/TENANT/CLUSTER_GUID/'   -var='dns_zone_id=/subscriptions/..../resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/geodata.example.com'   -var='key_vault_id=/subscriptions/.../resourceGroups/rg-kv/providers/Microsoft.KeyVault/vaults/kv-geodata'
```
