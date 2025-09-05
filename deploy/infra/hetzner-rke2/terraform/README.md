# Terraform (Hetzner)

```bash
export HCLOUD_TOKEN=...
cd infra/hetzner/terraform
terraform init
terraform apply -auto-approve -var "hcloud_token=$HCLOUD_TOKEN"
# After apply, copy the 'inventory_ini' output to ../ansible/inventory.ini (apply.sh automates the full flow)
```
