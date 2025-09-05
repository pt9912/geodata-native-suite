
output "app_fqdn" {
  value       = var.cf_zone_id == null ? null : format("%s.%s", var.app_subdomain, "ZONE_NAME")
  description = "Application FQDN (replace ZONE_NAME with your domain)"
}

output "api_fqdn" {
  value       = var.cf_zone_id == null ? null : format("%s.%s", var.api_subdomain, "ZONE_NAME")
  description = "API FQDN (replace ZONE_NAME with your domain)"
}
