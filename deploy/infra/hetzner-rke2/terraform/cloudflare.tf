# --- Cloudflare provider & records ---
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0.0"
    }
  }
}

# Only configure provider if token/zone are provided (allows running without CF)
provider "cloudflare" {
  api_token = var.cf_api_token
  alias     = "cf"
  # If cf_api_token is null, users can omit CF by not setting it; Terraform may error if used.
}

# Application FQDN: <app_subdomain>.<zone>
resource "cloudflare_record" "app" {
  count   = var.cf_zone_id == null || var.cf_api_token == null ? 0 : 1
  zone_id = var.cf_zone_id
  name    = var.app_subdomain
  type    = "A"
  value   = hcloud_server.cp.ipv4_address
  proxied = var.cf_proxied_app
  ttl     = 1 # auto
}

# Kubernetes API FQDN: <api_subdomain>.<zone>
resource "cloudflare_record" "api" {
  count   = var.cf_zone_id == null || var.cf_api_token == null ? 0 : 1
  zone_id = var.cf_zone_id
  name    = var.api_subdomain
  type    = "A"
  value   = hcloud_server.cp.ipv4_address
  proxied = var.cf_proxied_api
  ttl     = 1
}
