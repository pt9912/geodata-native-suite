
FROM ubuntu:24.04
ARG DEBIAN_FRONTEND=noninteractive
ARG KUBECTL_VERSION=v1.30.4
ARG HELM_VERSION=v3.15.3
ARG YQ_VERSION=v4.44.3
ARG KUSTOMIZE_VERSION=v5.4.2
ARG DOCKER_CLI_STATIC_VERSION=26.1.4

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git unzip zip jq gettext-base \
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

# bash goodies
RUN echo 'source /usr/share/bash-completion/bash_completion' >> /root/.bashrc \
 && echo 'source <(kubectl completion bash)' >> /root/.bashrc \
 && echo 'source <(helm completion bash)' >> /root/.bashrc \
 && echo "alias k='kubectl'" >> /root/.bashrc \
 && echo "complete -F __start_kubectl k" >> /root/.bashrc \
 && echo "alias kgp='kubectl get pods -A'" >> /root/.bashrc \
 && echo "alias kgs='kubectl get svc -A'" >> /root/.bashrc \
 && echo "alias kgi='kubectl get ingress -A'" >> /root/.bashrc

COPY scripts/postCreate.sh /usr/local/bin/postCreate.sh
RUN chmod +x /usr/local/bin/postCreate.sh
