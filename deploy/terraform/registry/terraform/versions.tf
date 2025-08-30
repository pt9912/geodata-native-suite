terraform {
  required_version = ">= 1.5.0"
  required_providers {
    hcloud     = { source = "hetznercloud/hcloud", version = "~> 1.48" }
    template   = { source = "hashicorp/template", version = "~> 2.2" }
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 4.0" }
    minio = {
      source  = "aminueza/minio"
      version = "3.6.4"
    }
  }
}
