# lxd-rke2

## build
```bash
# 1) Terraform vorbereiten
cd ./terraform

export LXD_DIR=/var/snap/lxd/common/lxd

terraform init

TF_LOG=INFO terraform plan -var "ssh_pubkey=$(cat ~/.ssh/id_rsa.pub)" \
  -var "vm_count_workers=1"

terraform apply -auto-approve \
  -var "ssh_pubkey=$(cat ~/.ssh/id_rsa.pub)" \
  -var "vm_count_workers=1"

./lxd_vm_health_check_legacy.sh geodata-master 
./lxd_vm_health_check_legacy.sh geodata-worker-0
 
# 2) Ansible ausführen
cd ../ansible

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
# inventory.ini wurde von Terraform erzeugt
ansible-playbook -i inventory.yml site.yml

INVENTORY_PATH=./inventory.yml \
./check_ansible_rke2_resources.sh geodata-master


ssh ubuntu@10.0.10.223 # ip anpassen
journalctl -u rke2-server

# 3) Kubeconfig lokal nutzen
export KUBECONFIG=$(pwd)/kube/rke2.yaml
kubectl get nodes -o wide
```

## destroy
```bash
cd ./terraform
terraform destroy -auto-approve -var "ssh_pubkey=$(cat ~/.ssh/id_rsa.pub)"
```