
variable "hcloud_ssh_key_name" {
  description = "Name des vorhandenen SSH-Keys in Hetzner"
  type        = string
}

data "hcloud_ssh_key" "this" {
  name = var.hcloud_ssh_key_name
}
resource "hcloud_firewall" "registry_fw" {
  name = "registry-fw"
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = [var.ssh_allowed_cidr]
  }
  # Port 80 ist geschlossen (DNS-01 benötigt ihn nicht)
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "minio_s3_bucket" "registry" {
  provider       = minio.object
  count          = var.s3_create_bucket ? 1 : 0
  bucket         = var.s3_bucket_name
  acl            = "private"
  object_locking = false
  force_destroy  = true
}

/* Öffentlich brauchst du vermutlich nicht; falls doch: 
resource "minio_s3_bucket_policy" "public_read" {
  provider = minio.object
  count    = 0 # auf 1 setzen, wenn wirklich public read gewünscht ist
  bucket   = var.s3_bucket_name
  policy   = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "PublicReadGetObject",
      Effect    = "Allow",
      Principal = "*",
      Action    = ["s3:GetObject"],
      Resource  = ["arn:aws:s3:::${var.s3_bucket_name}/*"]
    }]
  })
}
*/
data "template_file" "cloud_init" {
  template = file("${path.module}/cloud-init.yaml.tftpl")
  vars = {
    registry_domain = var.registry_domain
    acme_email      = var.acme_email
    registry_user   = var.registry_username
    registry_pass   = var.registry_password
    s3_bucket       = var.s3_bucket_name
    s3_region       = var.s3_region
    s3_endpoint     = var.s3_endpoint
    s3_access       = var.s3_access_key
    s3_secret       = var.s3_secret_key
    s3_forceps      = var.s3_use_path_style ? "true" : "false"
    s3_encrypt      = var.s3_encrypt ? "true" : "false"
    cf_api_token    = var.cf_api_token
  }
}

resource "hcloud_server" "registry_server" {
  name         = "reg-s3-dns01"
  image        = var.image_id
  server_type  = var.server_type
  location     = var.server_location
  ssh_keys     = [data.hcloud_ssh_key.this.id]
  firewall_ids = [hcloud_firewall.registry_fw.id]
  user_data    = data.template_file.cloud_init.rendered
}

resource "hcloud_rdns" "server_ptr" {
  server_id  = hcloud_server.registry_server.id
  ip_address = hcloud_server.registry_server.ipv4_address
  dns_ptr    = var.registry_domain != "" ? var.registry_domain : hcloud_server.registry_server.name
}

# Cloudflare A-Record (optional)
resource "cloudflare_record" "registry_a" {
  count = (var.cf_zone_id != "" && var.registry_domain != "") ? 1 : 0

  zone_id         = var.cf_zone_id
  name            = var.cf_record_name
  type            = "A"
  content         = hcloud_server.registry_server.ipv4_address
  ttl             = 300
  proxied         = var.cf_proxied
  allow_overwrite = true
}
