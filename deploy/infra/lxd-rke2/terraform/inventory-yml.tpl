all:
  hosts:
    master1:
      ansible_host: ${master_ip}
      hostname: master1.rke2.local

%{ for index, ip in worker_ips ~}
    ${format("worker%d:", index + 1)}
      ansible_host: ${ip}
      ${format("hostname: worker%d.rke2.local", index + 1)}
%{ endfor ~}

  children:
    masters:
      hosts:
        master1:
    workers:
      hosts:
%{ for index, ip in worker_ips ~}
        ${format("worker%d:", index + 1)}
%{ endfor ~}

