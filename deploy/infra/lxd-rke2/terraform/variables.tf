variable "vm_count_workers" {
  type    = number
  default = 1
}
variable "vm_prefix" {
  type    = string
  default = "geodata"
}
variable "memory_mb" {
  type    = number
  default = 4096
}
variable "vcpus" {
  type    = number
  default = 2
}
variable "disk_gb" {
  type    = number
  default = 30
}

variable "ssh_pubkey" { type = string } # z.B. file("~/.ssh/id_rsa.pub")



variable "network_cidr" {
  type    = string
  default = "10.0.10.1/24"
}

variable "image_url" {
  type    = string
  default = "ubuntu:22.04"  # Standard-LXD-Image (kein QCOW2)
}