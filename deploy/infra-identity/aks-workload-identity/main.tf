
data "azurerm_client_config" "current" {}

# User Assigned Managed Identities
resource "azurerm_user_assigned_identity" "fetch" {
  name                = "uami-geodata-fetch"
  resource_group_name = var.resource_group
  location            = var.location
}
resource "azurerm_user_assigned_identity" "index" {
  name                = "uami-geodata-index"
  resource_group_name = var.resource_group
  location            = var.location
}
resource "azurerm_user_assigned_identity" "extdns" {
  name                = "uami-external-dns"
  resource_group_name = var.resource_group
  location            = var.location
}

# Federated Identity Credentials – subject = system:serviceaccount:<ns>:<sa>
resource "azurerm_federated_identity_credential" "fic_fetch" {
  name                = "fic-fetch"
  resource_group_name = var.resource_group
  parent_id           = azurerm_user_assigned_identity.fetch.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.cluster_oidc_issuer_url
  subject             = "system:serviceaccount:geodata:fetch"
}
resource "azurerm_federated_identity_credential" "fic_index" {
  name                = "fic-index"
  resource_group_name = var.resource_group
  parent_id           = azurerm_user_assigned_identity.index.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.cluster_oidc_issuer_url
  subject             = "system:serviceaccount:geodata:index-service"
}
resource "azurerm_federated_identity_credential" "fic_extdns" {
  name                = "fic-external-dns"
  resource_group_name = var.resource_group
  parent_id           = azurerm_user_assigned_identity.extdns.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.cluster_oidc_issuer_url
  subject             = "system:serviceaccount:external-dns:external-dns"
}

# Role Assignments
# Key Vault RBAC (enable RBAC on KV): Secrets User
resource "azurerm_role_assignment" "kv_fetch" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.fetch.principal_id
}
resource "azurerm_role_assignment" "kv_index" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.index.principal_id
}

# Azure DNS – DNS Zone Contributor für external-dns
resource "azurerm_role_assignment" "dns_extdns" {
  scope                = var.dns_zone_id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.extdns.principal_id
}

output "uamis" {
  value = {
    fetch  = { client_id = azurerm_user_assigned_identity.fetch.client_id, resource_id = azurerm_user_assigned_identity.fetch.id }
    index  = { client_id = azurerm_user_assigned_identity.index.client_id, resource_id = azurerm_user_assigned_identity.index.id }
    extdns = { client_id = azurerm_user_assigned_identity.extdns.client_id, resource_id = azurerm_user_assigned_identity.extdns.id }
  }
}
