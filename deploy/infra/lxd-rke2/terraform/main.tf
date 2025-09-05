provider "lxd" {
  generate_client_certificates = true
  accept_remote_certificate    = true

}

# --- LXD-Storage-Pool ---
resource "lxd_storage_pool" "geodata" {
  name   = "${var.vm_prefix}-pool"
  driver = "dir"
}

# --- LXD-Netzwerk ---
resource "lxd_network" "geodata" {
  name   = "${var.vm_prefix}-net"
  type   = "bridge"
  config = {
    "ipv4.address" = var.network_cidr
    "ipv4.nat"     = "true"
    "ipv6.address" = "none"
  }
}

# --- RKE2-Token ---
locals {
  rke2_token = chomp(fileexists("${path.module}/../ansible/rke2.token") ? file("${path.module}/../ansible/rke2.token") : random_password.rke2.result)
}
resource "random_password" "rke2" {
  length  = 24
  special = false
}

# --- Cloud-Init ---
data "template_cloudinit_config" "master_ci" {
  gzip          = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content      = <<EOF
#cloud-config
hostname: ${var.vm_prefix}-master
ssh_authorized_keys:
  - ${var.ssh_pubkey}
package_update: false
packages: [curl]
runcmd:
  - mkdir -p /etc/rancher/rke2
  - echo "token: ${local.rke2_token}" > /etc/rancher/rke2/config.yaml
  # optional: Advertise-Addr setzen (hilft bei Multi-NIC/Bridges)
  # - echo "tls-san:" >> /etc/rancher/rke2/config.yaml
  # - echo "- ${var.vm_prefix}-master" >> /etc/rancher/rke2/config.yaml
  - curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=server sh -
  - systemctl enable --now rke2-server
EOF
  }
}

data "template_cloudinit_config" "worker_ci" {
  count         = var.vm_count_workers
  gzip          = false
  base64_encode = false
  part {
    content_type = "text/cloud-config"
    content      = <<EOF
#cloud-config
hostname: ${var.vm_prefix}-worker-${count.index}
ssh_authorized_keys:
  - ${var.ssh_pubkey}
package_update: false
packages: [curl]
runcmd:
  - mkdir -p /etc/rancher/rke2
  - echo "server: https://${var.vm_prefix}-master:9345" > /etc/rancher/rke2/config.yaml
  - echo "token: ${local.rke2_token}" >> /etc/rancher/rke2/config.yaml
  - curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=agent sh -
  - systemctl enable --now rke2-agent
EOF
  }
}


# --- LXD-Profil (nur für Geräte) ---
resource "lxd_profile" "geodata" {
  name = "${var.vm_prefix}-profile"

  depends_on = [
    lxd_network.geodata,
    lxd_storage_pool.geodata
  ]

  config = {
  "user.user-data" = data.template_cloudinit_config.master_ci.rendered
  "raw.lxc" = "lxc.cgroup2.devices.allow = c 10:200 rwm"
  "security.secureboot" = "false"    
    #"security.nesting" = "true"
    # Fallback, falls es weiterhin klemmt:
    # "security.privileged" = "true"
    # "raw.lxc"            = "lxc.apparmor.profile=unconfined"

  #  "security.privileged" = "true"
  #   "raw.lxc" = <<-EORAW
  #     lxc.apparmor.profile=unconfined
  #     lxc.cap.drop=
  #     lxc.mount.auto=proc:rw sys:rw cgroup:rw
  #     lxc.cgroup2.devices.allow=a
  #     lxc.mount.entry=/dev/kmsg dev/kmsg none bind,create=file 0 0
  #   EORAW    
  }


  device {
    name = "eth0"
    type = "nic"
    properties = {
      network = lxd_network.geodata.name
      #type    = "bridged"
    }
  }
  device {
    name = "root"
    type = "disk"
    properties = {
      pool = lxd_storage_pool.geodata.name
      path = "/"
      size = "${var.disk_gb}GiB"
    }
  }

  #Host-Kernelmodule schreibgeschützt in den Container mounten
  # device {
  #   name = "kmods"
  #   type = "disk"
  #   properties = {
  #     source  = "/usr/lib/modules"
  #     path    = "/usr/lib/modules"
  #     readonly = "true"
  #   }
  # }

}

# --- Master-Instance ---
resource "lxd_instance" "master" {
  name     = "${var.vm_prefix}-master"
  image    = "ubuntu:22.04"
  type  = "virtual-machine"
  profiles = [lxd_profile.geodata.name]

  # Limits separat:
  limits = {
    cpu    = tostring(var.vcpus)
    memory = "${var.memory_mb}MiB"
  }

  # Cloud-Init bleibt in config:
  config = {
    "user.user-data" = data.template_cloudinit_config.master_ci.rendered
    "boot.autostart" = "true"
  }
}

resource "lxd_instance" "worker" {
  count    = var.vm_count_workers
  name     = "${var.vm_prefix}-worker-${count.index}"
  image    = "ubuntu:22.04"
  type  = "virtual-machine"
  profiles = [lxd_profile.geodata.name]

  limits = {
    cpu    = tostring(var.vcpus)
    memory = "${var.memory_mb}MiB"
  }

  config = {
    "user.user-data" = data.template_cloudinit_config.worker_ci[count.index].rendered
    "boot.autostart" = "true"
  }
}

# --- Ansible-Inventory (1:1 übernommen) ---
locals {
  inventory = templatefile("${path.module}/inventory.tpl", {
    master_ip  = lxd_instance.master.ipv4_address
    worker_ips = [for w in lxd_instance.worker : w.ipv4_address]
    rke2_token = local.rke2_token
  })
  inventory_yml = templatefile("${path.module}/inventory-yml.tpl", {
    master_ip  = lxd_instance.master.ipv4_address
    worker_ips = [for w in lxd_instance.worker : w.ipv4_address]
    rke2_token = local.rke2_token
  })  
}

resource "local_file" "inventory" {
  filename = "${path.module}/../ansible/inventory.ini"
  content  = local.inventory
  file_permission      = "0644"
  directory_permission = "0755"  
}

resource "local_file" "inventory_yml" {
  filename = "${path.module}/../ansible/inventory.yml"
  content  = local.inventory_yml
  file_permission      = "0644"
  directory_permission = "0755"  
}