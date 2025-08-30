
# Enable Kubernetes auth
resource "vault_auth_backend" "k8s" {
  type = "kubernetes"
  path = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "cfg" {
  backend                = vault_auth_backend.k8s.path
  kubernetes_host        = var.kubernetes_host
  kubernetes_ca_cert     = base64decode(var.kubernetes_ca_cert_base64)
  token_reviewer_jwt     = base64decode(var.token_reviewer_jwt)
  disable_issuer_verification = true
}

# KV v2 mount
resource "vault_mount" "kv" {
  path        = "kv"
  type        = "kv-v2"
  description = "Geodata app secrets"
}

# Policy – read-only auf geodata Pfad
resource "vault_policy" "geodata_read" {
  name = "geodata-read"
  policy = <<EOT
path "kv/data/geodata/*" {
  capabilities = ["read"]
}
EOT
}

# Role mapping: SA -> Policy
resource "vault_kubernetes_auth_backend_role" "fetch" {
  backend                          = vault_auth_backend.k8s.path
  role_name                        = "geodata-fetch"
  bound_service_account_names      = ["fetch"]
  bound_service_account_namespaces = ["geodata"]
  token_policies                   = [vault_policy.geodata_read.name]
  token_ttl                        = 3600
}

resource "vault_kubernetes_auth_backend_role" "index" {
  backend                          = vault_auth_backend.k8s.path
  role_name                        = "geodata-index"
  bound_service_account_names      = ["index-service"]
  bound_service_account_namespaces = ["geodata"]
  token_policies                   = [vault_policy.geodata_read.name]
  token_ttl                        = 3600
}
