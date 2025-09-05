
SHELL := /bin/bash
include .env
export

DOMAIN := $(ENV).$(BASE)
SEARCH_HOST := search.$(DOMAIN)
FETCH_HOST  := fetch.$(DOMAIN)
INDEX_HOST  := index.$(DOMAIN)
DATA_HOST   := data.$(DOMAIN)
AUTH_HOST   := auth.$(DOMAIN)

KUBECTL ?= kubectl
HELM ?= helm

.PHONY: ns identity dns tls secrets apps ingress status status-dev delete redpanda redpanda-clean


ns:
	-$(KUBECTL) create ns $(NS) >/dev/null 2>&1 || true
	-$(KUBECTL) create ns $(NS_INFRA) >/dev/null 2>&1 || true
	-$(KUBECTL) create ns $(NS_IDP) >/dev/null 2>&1 || true

redpanda: ns
	$(HELM) repo add redpanda https://charts.redpanda.com >/dev/null 2>&1 || true
	$(HELM) repo update >/dev/null
	$(HELM) upgrade --install redpanda redpanda/redpanda -n $(NS_INFRA) \
	  -f ../values/infra/redpanda/base/values.yaml \
	  -f ../values/infra/redpanda/platform/rke2/values.yaml \
	  -f ../values/infra/redpanda/env/$(ENV)/values.yaml


redpanda-console: redpanda
	$(HELM) upgrade --install redpanda-console redpanda/console -n $(NS_INFRA) \
	  --set config.kafka.brokers="redpanda-0.redpanda.$(NS_INFRA).svc.cluster.local:9092"

identity: ns
	$(HELM) repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
	$(HELM) upgrade --install keycloak bitnami/keycloak -n $(NS_IDP) \
	  -f ../values/infra/identity/base/values.yaml \
	  -f ../values/infra/identity/platform/rke2/values.yaml \
	  -f ../values/infra/identity/env/$(ENV)/values.yaml \
	  --set ingress.hostname=$(AUTH_HOST) \
	  --set smtp.from=$(SMTP_FROM) --set smtp.host=$(SMTP_HOST) --set smtp.port=$(SMTP_PORT) --set smtp.tls=$(SMTP_TLS)

dns: ns
	-$(KUBECTL) -n $(NS_INFRA) create secret generic hetzner-token --from-literal=token=$(HETZNER_API_TOKEN) >/dev/null 2>&1 || true
	$(HELM) repo add external-dns https://kubernetes-sigs.github.io/external-dns/ >/dev/null
	$(HELM) upgrade --install external-dns external-dns/external-dns -n $(NS_INFRA) \
	  -f ../values/infra/externaldns/platform/rke2/values.yaml \
	  --set "domainFilters={$(PARENT_ZONE)}" \
	  --set txtOwnerId="geodata-suite" \
	  --set sources="{ingress}"

tls: ns
	$(HELM) repo add jetstack https://charts.jetstack.io >/dev/null
	$(HELM) upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set installCRDs=true -f tls/cert-manager/values.yaml
	-$(KUBECTL) -n cert-manager create secret generic hetzner-dns --from-literal=api-token=$(HETZNER_API_TOKEN) >/dev/null 2>&1 || true
	# Hinweis: Hetzner Webhook Chart-Repo ggf. anpassen
	# $(HELM) upgrade --install cert-manager-webhook-hetzner <repo>/cert-manager-webhook-hetzner -n cert-manager -f tls/hetzner-webhook/values-variant-a.yaml

secrets: ns
	$(HELM) repo add external-secrets https://charts.external-secrets.io >/dev/null
	$(HELM) upgrade --install external-secrets external-secrets/external-secrets -n $(NS_INFRA) -f ../values/infra/externalsecrets/base/values.yaml
	envsubst < ../values/infra/externalsecrets/platform/rke2/clustersecretstore-vault.yaml | $(KUBECTL) -n $(NS_INFRA) apply -f -
	-$(KUBECTL) -n $(NS) apply -f ../values/infra/externalsecrets/examples/externalsecret-minio.yaml || true
	-$(KUBECTL) -n $(NS_IDP) apply -f ../values/infra/externalsecrets/examples/externalsecret-smtp-proton.yaml || true

apps: ns redpanda
	$(HELM) upgrade --install search-postgis $(CHARTS_DIR)/search-postgis -n $(NS) \
	  -f ../values/search-postgis/base/values.yaml \
	  -f ../values/search-postgis/platform/rke2/values.yaml \
	  -f ../values/search-postgis/env/$(ENV)/values.yaml
	$(HELM) upgrade --install fetch $(CHARTS_DIR)/fetch -n $(NS) \
	  -f ../values/fetch/base/values.yaml \
	  -f ../values/fetch/platform/rke2/values.yaml \
	  -f ../values/fetch/env/$(ENV)/values.yaml
	$(HELM) upgrade --install index-service $(CHARTS_DIR)/index-service -n $(NS) \
	  -f ../values/index-service/base/values.yaml \
	  -f ../values/index-service/platform/rke2/values.yaml \
	  -f ../values/index-service/env/$(ENV)/values.yaml
	$(HELM) upgrade --install nginx-stream $(CHARTS_DIR)/nginx-stream -n $(NS) \
	  -f ../values/nginx-stream/base/values.yaml \
	  -f ../values/nginx-stream/platform/rke2/values.yaml \
	  -f ../values/nginx-stream/env/$(ENV)/values.yaml

status-dev:
	$(KUBECTL) -n $(NS) get deploy,svc,ingress

status-redpanda:
	$(KUBECTL) -n $(NS_INFRA) get pods -l app.kubernetes.io/instance=redpanda
	$(KUBECTL) -n $(NS_INFRA) get svc -l app.kubernetes.io/instance=redpanda

status:
	$(KUBECTL) -n $(NS) get deploy,svc,ingress
	-$(KUBECTL) -n $(NS_INFRA) logs deploy/external-dns --tail=50

redpanda-clean:
	-$(HELM) uninstall redpanda -n $(NS_INFRA) || true

delete:
	-$(HELM) uninstall keycloak -n $(NS_IDP) || true
	-$(HEM) uninstall external-dns -n $(NS_INFRA) || true
	-$(HELM) uninstall cert-manager -n cert-manager || true
	-$(HELM) uninstall external-secrets -n $(NS_INFRA) || true
	-$(HELM) uninstall search-postgis -n $(NS) || true
	-$(HELM) uninstall fetch -n $(NS) || true
	-$(HELM) uninstall index-service -n $(NS) || true
	-$(HELM) uninstall nginx-stream -n $(NS) || true
	-$(KUBECTL) delete ns $(NS) || true
	-$(KUBECTL) delete ns $(NS_INFRA) || true
	-$(KUBECTL) delete ns $(NS_IDP) || true
	-$(KUBECTL) delete ns cert-manager || true