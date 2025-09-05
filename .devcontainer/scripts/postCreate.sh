#!/usr/bin/env bash
set -euo pipefail


# Determine the GID of the mounted LXD unix socket on the host
SOCKET="/var/snap/lxd/common/lxd/unix.socket"
if [ ! -S "$SOCKET" ]; then
  echo "❌ LXD socket not mounted at $SOCKET"
  exit 1
fi

GID=$(stat -c %g "$SOCKET")
GROUP_NAME="lxd"

# If a group with this GID doesn't exist in the container, create one (named lxd)
if ! getent group "$GID" >/dev/null; then
  if getent group "$GROUP_NAME" >/dev/null; then
    # rename existing group name if gid mismatch
    EXISTING_GID=$(getent group "$GROUP_NAME" | cut -d: -f3)
    if [ "$EXISTING_GID" != "$GID" ]; then
      sudo groupmod -n lxd_old "$GROUP_NAME" || true
    fi
  fi
  sudo groupadd -g "$GID" "$GROUP_NAME" || true
else
  # ensure it is named lxd (optional)
  EXISTING_NAME=$(getent group "$GID" | cut -d: -f1)
  if [ "$EXISTING_NAME" != "$GROUP_NAME" ]; then
    sudo groupmod -n "$GROUP_NAME" "$EXISTING_NAME" || true
  fi
fi

# Add current user to lxd group if not already
USERNAME=${USERNAME:-ubuntu}
if ! id -nG "$USERNAME" | tr ' ' '\n' | grep -q "^${GROUP_NAME}$"; then
  sudo usermod -aG "$GROUP_NAME" "$USERNAME"
fi

# Make sure the env var is present in shell sessions
PROFILE_FILE="/home/${USERNAME}/.bashrc"
if ! grep -q 'export LXD_DIR=' "$PROFILE_FILE"; then
  echo 'export LXD_DIR=/var/snap/lxd/common/lxd' >> "$PROFILE_FILE"
fi

echo "✅ LXD group mapped (gid=$GID) and user ${USERNAME} added."


# SOCKETS=(
#   "/var/run/docker.sock:dockersock"
#   "/dev/kvm:kvmhost"
#   "/var/run/libvirt/libvirt-sock:libvirt"
# )

# for entry in "${SOCKETS[@]}"; do
#   IFS=":" read -r path gname <<<"$entry"
#   if [ -e "$path" ]; then
#     ls -la "$path"

#     gid=$(stat -c %g "$path")
#     # Gruppe mit exakt dieser GID sicherstellen
#     if ! getent group "$gid" >/dev/null; then
#       sudo groupadd -g "$gid" "$gname" || true
#     else
#       # Wenn die GID bereits existiert, hole den vorhandenen Namen
#       GROUP_NAME=$(getent group "$gid" | cut -d: -f1)
#       echo "GID $gid already belongs to group $GROUP_NAME" 
#     fi
#     # ubuntu zur Gruppe (per Name oder GID) hinzufügen
#     sudo usermod -aG "$gid" ubuntu || sudo usermod -aG "$gname" ubuntu || true

#     ls -la "$path"
#   fi
# done
# getent group | grep ubuntu

# Verzeichnisse für kube/helm
sudo mkdir -p /home/ubuntu/.kube /home/ubuntu/.local/share/helm/plugins
sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube /home/ubuntu/.local


echo "[postCreate] tool versions:"
kubectl version --client=true || true
helm version || true
#k3d version || true
yq --version || true
docker version || true

# Sanity: docker socket accessible?
if ! docker ps >/dev/null 2>&1; then
  echo "[WARN] Docker socket not accessible. Mount /var/run/docker.sock into the DevContainer."
fi

# Optionale k3d Cluster-Schnellstart-Hilfe
#echo "[hint] Create local cluster:"
#echo "  k3d cluster create geodata-local --agents 2 --api-port 6550 \\"
#echo "    --port '8080:80@loadbalancer' --port '8443:443@loadbalancer'"
#echo "  kubectl config use-context k3d-geodata-local"



echo ">>> Gruppen jetzt: $(id -nG)"
echo ">>> Bitte das Terminal neu öffnen, damit die neuen Gruppen aktiv sind."