resource "hcloud_network" "net" { name = "${var.cluster_name}-net"; ip_range = "10.42.0.0/16" }
resource "hcloud_server" "cp" {
  name = "${var.cluster_name}-cp-1"; server_type = var.server_type_cp; image = "ubuntu-24.04"; location = var.location
}
resource "hcloud_server" "worker" {
  count = var.workers
  name = "${var.cluster_name}-w-${count.index + 1}"; server_type = var.server_type_worker; image = "ubuntu-24.04"; location = var.location
}
output "control_plane_ip" { value = hcloud_server.cp.ipv4_address }
output "worker_ips" { value = [for w in hcloud_server.worker : w.ipv4_address] }
