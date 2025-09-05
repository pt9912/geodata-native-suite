[master]
${master_ip}

[workers]
%{ for ip in worker_ips ~}
${ip}
%{ endfor ~}

[rke2:children]
master
workers

[rke2:vars]
ansible_user=ubuntu
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
rke2_token=${rke2_token}
