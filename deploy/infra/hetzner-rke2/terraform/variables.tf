variable "hcloud_token" { 
  description = "Hetzner Cloud API token"
  type = string; sensitive = true 
}
variable "cluster_name" { 
  type = string
  default = "geodata-rke2" 
}
variable "location"     { 
  type = string
  default = "nbg1" 
}
variable "server_type_cp" { 
  type = string
  default = "cx22" 
}
variable "server_type_worker" { 
  type = string
  default = "cx22" 
}
variable "workers" { 
  type = number
  default = 2 
}

# --- Cloudflare ---
variable "cf_api_token" {
  description = "Cloudflare API Token with DNS edit on the target zone"
  type        = string
  sensitive   = true
  default     = null
}

variable "cf_zone_id" {
  description = "Cloudflare Zone ID for your domain"
  type        = string
  default     = null
}

variable "app_subdomain" {
  description = "App subdomain (e.g., 'geodata' for geodata.example.com)"
  type        = string
  default     = "geodata"
}

variable "api_subdomain" {
  description = "API subdomain (e.g., 'kubeapi' for kubeapi.example.com)"
  type        = string
  default     = "kubeapi"
}

variable "cf_proxied_app" {
  description = "Whether to enable Cloudflare proxy (orange cloud) for the app record"
  type        = bool
  default     = true
}

variable "cf_proxied_api" {
  description = "Whether to enable Cloudflare proxy for the API record"
  type        = bool
  default     = false
}
