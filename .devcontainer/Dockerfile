
FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive
ARG KUBECTL_VERSION=v1.30.4
ARG HELM_VERSION=v3.15.3
ARG YQ_VERSION=v4.44.3
ARG KUSTOMIZE_VERSION=v5.4.2
ARG DOCKER_CLI_STATIC_VERSION=26.1.4
#ARG K3D_VERSION=v5.6.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates sudo curl gnupg git unzip zip jq gettext-base \
    make bash-completion less nano vim iputils-ping dnsutils \
    python3 python3-pip openssl procps \
 && rm -rf /var/lib/apt/lists/*

# Docker CLI (repo + fallback static)
RUN set -eux; \
    apt-get update; apt-get install -y ca-certificates curl gnupg; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; \
    chmod a+r /etc/apt/keyrings/docker.gpg; \
    . /etc/os-release; echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list; \
    apt-get update || true; \
    if ! apt-get install -y --no-install-recommends docker-ce-cli; then \
      echo "Falling back to static Docker CLI ${DOCKER_CLI_STATIC_VERSION}"; \
      curl -fsSL -o /tmp/docker.tgz https://download.docker.com/linux/static/stable/$(uname -m)/docker-${DOCKER_CLI_STATIC_VERSION}.tgz; \
      tar -xzf /tmp/docker.tgz -C /usr/local/bin --strip-components=1 docker/docker; \
      rm -f /tmp/docker.tgz; \
    fi; rm -rf /var/lib/apt/lists/*
RUN groupadd -g "992" docker
RUN usermod -aG docker ubuntu
RUN newgrp docker

# yamllint
RUN set -eux; \
    apt-get update; apt-get install -y yamllint

    # terraform
# 1️⃣ Grundpakete (falls noch nicht vorhanden)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg lsb-release && \
    rm -rf /var/lib/apt/lists/*

# 2️⃣ HashiCorp‑GPG‑Schlüssel holen und dearmoren
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | \
    gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# 3️⃣ Repository‑Eintrag anlegen (komplett und korrekt)
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list

# 4️⃣ Terraform installieren
RUN apt-get update && \
    apt-get install -y --no-install-recommends terraform && \
    rm -rf /var/lib/apt/lists/*
        
# ansible
RUN apt update && apt install -y software-properties-common && \
    add-apt-repository --yes --update ppa:ansible/ansible && \
    apt install -y ansible && \
    rm -rf /var/lib/apt/lists/*
    
# kubectl
RUN curl -fsSL -o /usr/local/bin/kubectl https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
 && chmod +x /usr/local/bin/kubectl

# helm
RUN curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o /tmp/helm.tgz \
 && tar -xzf /tmp/helm.tgz -C /tmp && mv /tmp/linux-amd64/helm /usr/local/bin/helm \
 && chmod +x /usr/local/bin/helm && rm -rf /tmp/helm.tgz /tmp/linux-amd64

# yq
RUN curl -fsSL -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64 \
 && chmod +x /usr/local/bin/yq

# kustomize
RUN curl -fsSL -o /tmp/kustomize.tar.gz https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_amd64.tar.gz \
 && tar -xzf /tmp/kustomize.tar.gz -C /usr/local/bin && chmod +x /usr/local/bin/kustomize && rm -f /tmp/kustomize.tar.gz

# Locale-Setup
RUN apt-get update && apt-get install -y locales \
 && sed -i 's/^# *\(de_DE.UTF-8 UTF-8\)/\1/' /etc/locale.gen \
 && locale-gen de_DE.UTF-8 \
 && update-locale LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8
ENV LANG=de_DE.UTF-8
ENV LC_ALL=de_DE.UTF-8

# k3d
#RUN curl -L "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-amd64" -o /usr/local/bin/k3d \
# && chmod +x /usr/local/bin/k3d


# Pakete für Dev libvirt
#RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
#    sudo \
#    qemu-utils libvirt-clients libguestfs-tools genisoimage cloud-image-utils \
#    python3-libvirt sshpass  \
#    && rm -rf /var/lib/apt/lists/*


# User vscode (1000:1000)
#RUN useradd -ms /bin/bash -u 1000 vscode \
#    && echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
#    && usermod -aG kvm,libvirt vscode
#RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
#&& usermod -aG dockersock,kvmhost,libvirt ubuntu

USER ubuntu
WORKDIR /workspaces/geodata-native-suite

# bash goodies
RUN echo 'source /usr/share/bash-completion/bash_completion' >> /home/ubuntu/.bashrc \
 && echo 'source <(kubectl completion bash)' >> /home/ubuntu/.bashrc \
 && echo 'source <(helm completion bash)' >> /home/ubuntu/.bashrc \
 && echo "alias k='kubectl'" >> /home/ubuntu/.bashrc \
 && echo "complete -F __start_kubectl k" >> /home/ubuntu/.bashrc \
 && echo "alias kgp='kubectl get pods -A'" >> /home/ubuntu/.bashrc \
 && echo "alias kgs='kubectl get svc -A'" >> /home/ubuntu/.bashrc \
 && echo "alias kgi='kubectl get ingress -A'" >> /home/ubuntu/.bashrc

COPY scripts/postCreate.sh /usr/local/bin/postCreate.sh
USER root

# Ensure ubuntu can sudo without password
RUN usermod -aG sudo ubuntu \
 && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/99-ubuntu-nopasswd \
 && chmod 440 /etc/sudoers.d/99-ubuntu-nopasswd

RUN chmod +x /usr/local/bin/postCreate.sh

USER ubuntu