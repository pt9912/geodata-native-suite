terraform {
  required_version = ">= 1.5.0"
  required_providers {
    lxd = {
      source = "terraform-lxd/lxd"
      version = ">= 2.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2.0"  # Für Cloud-Init-Templates (ersetzt cloudinit-Provider)
    }
  }
}