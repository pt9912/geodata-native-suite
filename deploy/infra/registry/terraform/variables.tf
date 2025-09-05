# Infra
variable "hcloud_token" {
  type      = string
  sensitive = true
}
variable "server_location" {
  type    = string
  default = "nbg1"
}
variable "server_type" {
  type    = string
  default = "cx22"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}
variable "ssh_allowed_cidr" {
  type    = string
  default = "0.0.0.0/0"
}
variable "image_name" {
  type = string
}
variable "image_id" {
  type = number
}

# DNS/TLS
variable "registry_domain" {
  type    = string
  default = ""
}
variable "acme_email" {
  type    = string
  default = ""
}

# Basic Auth
variable "registry_username" {
  type    = string
  default = "registryuser"
}
variable "registry_password" {
  type      = string
  sensitive = true
}

# S3
variable "s3_endpoint" {
  type = string
}
variable "s3_endpoint_host" {
  type = string
}
variable "s3_location" {
  type    = string
  default = "nbg1"
}
variable "s3_region" {
  type    = string
  default = "us-east-1"
}
variable "s3_bucket_name" {
  type = string
}
variable "s3_access_key" {
  type      = string
  sensitive = true
}
variable "s3_secret_key" {
  type      = string
  sensitive = true
}
variable "s3_use_path_style" {
  type    = bool
  default = true
}
variable "s3_encrypt" {
  type    = bool
  default = true
}
variable "s3_create_bucket" {
  type    = bool
  default = true
}

# Cloudflare DNS
variable "cf_api_token" {
  type      = string
  sensitive = true
  default   = ""
}
variable "cf_zone_id" {
  type    = string
  default = ""
}
variable "cf_record_name" {
  type    = string
  default = "registry"
}
variable "cf_proxied" {
  type    = bool
  default = false
}
