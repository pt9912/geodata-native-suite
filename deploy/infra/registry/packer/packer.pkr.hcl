packer {
  required_version = ">= 1.10.0"
  required_plugins {
    hcloud = {
      version = ">= 1.7.0"
      source  = "github.com/hetznercloud/hcloud"
    }
  }
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "server_type" {
  type    = string
  default = "cx22"
}

variable "location" {
  type    = string
  default = "nbg1"
}

variable "ssh_username" {
  type    = string
  default = "root"
}

locals {
  timestamp  = formatdate("YYYYMMDDhhmmss", timestamp())
  image_name = "golden-registry-base-${local.timestamp}"
}

source "hcloud" "ubuntu" {
  token        = var.hcloud_token
  server_type  = var.server_type
  location     = var.location
  image        = "ubuntu-24.04"
  ssh_username = var.ssh_username

  
  snapshot_name   = local.image_name
  snapshot_labels = { 
    role = "registry-base"
    tool = "packer" 
  }
}

build {
  name    = "golden-registry-base"
  sources = ["source.hcloud.ubuntu"]

  provisioner "shell" {
    # Shebang ohne Mehrfach-Optionen
    inline_shebang = "/usr/bin/env bash"

    inline = [
      # Optionen hier setzen, nicht im Shebang
      "set -Eeuo pipefail",
      "export DEBIAN_FRONTEND=noninteractive",

      "apt-get update",
      "apt-get install -y ca-certificates curl gnupg apt-transport-https software-properties-common",

      "install -m 0755 -d /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "chmod a+r /etc/apt/keyrings/docker.gpg",
      "sh -c 'echo deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable > /etc/apt/sources.list.d/docker.list'",

      "apt-get update",
      "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "systemctl enable --now docker",

      "sh -c 'id ubuntu >/dev/null 2>&1 && usermod -aG docker ubuntu || true'",

      "docker pull registry:2 || true",
      "mkdir -p /opt/registry/{auth,config,caddy}",

      <<-COMPOSE
      cat >/opt/registry/docker-compose.yml <<'EOF'
      services:
        registry:
          image: registry:2
          container_name: registry
          restart: unless-stopped
          ports:
            - "5000:5000"
          volumes:
            - ./config:/etc/docker/registry
            - /var/lib/registry:/var/lib/registry
      EOF
      COMPOSE
      ,
      # Systemd-Unit in EINEM Inline-String via HCL-Heredoc schreiben
      <<-UNIT
      cat >/etc/systemd/system/registry-stack.service <<'EOF'
      [Unit]
      Description=Registry + Caddy stack (dns01)
      After=docker.service network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      WorkingDirectory=/opt/registry
      ExecStart=/usr/bin/docker compose up -d
      ExecStop=/usr/bin/docker compose down
      TimeoutStartSec=0

      [Install]
      WantedBy=multi-user.target
      EOF
      UNIT
      ,
      "systemctl daemon-reload",
      "systemctl enable registry-stack.service",
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "true"
    ]
  }
}
