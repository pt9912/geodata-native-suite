provider "hcloud" { token = var.hcloud_token }



# Hetzner Object Storage via MinIO-Provider
provider "minio" {
  alias = "object"
  # WICHTIG: ohne Schema (kein https://), nur Hostname!
  minio_server   = var.s3_endpoint_host # z.B. "v1000-geo-terrain.nbg1.your-objectstorage.com"
  minio_user     = var.s3_access_key
  minio_password = var.s3_secret_key
  minio_region   = var.s3_location # z.B. "nbg1" (hier ist nbg1 OK)
  #minio_region = var.s3_region # z.B. "nbg1" (hier ist nbg1 OK)
  minio_ssl = true
}

provider "cloudflare" { api_token = var.cf_api_token }
