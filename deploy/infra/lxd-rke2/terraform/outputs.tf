output "ssh_master" {
   value = "ssh ubuntu@${lxd_instance.master.ipv4_address}" 
}



output "master_ip" {
  value = lxd_instance.master.ipv4_address
}
output "worker_ips" {
  value = [for w in lxd_instance.worker : w.ipv4_address]
}
output "inventory_path" {
  value = local_file.inventory.filename
}
output "rke2_token" {
  value     = local.rke2_token
  sensitive = true
}