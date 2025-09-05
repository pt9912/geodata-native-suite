output "server_ipv4" { value = hcloud_server.registry_server.ipv4_address }
output "registry_fqdn" { value = var.registry_domain }
