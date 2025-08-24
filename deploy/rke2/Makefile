
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

.PHONY: identity dns tls secrets apps ingress status

identity:
	-$(KUBECTL) create ns $(NS) >/dev/null 2>&1 || true
	-$(KUBECTL) create ns $(NS_INFRA) >/dev/null 2>&1 || true
	-$(KUBECTL) create ns $(NS_IDP) >/dev/null 2>&1 || true
	$(HELM) repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
	$(HELM) upgrade --install keycloak bitnami/keycloak -n $(NS_IDP) \
	  -f ../values/infra/identity/base/values.yaml \
	  -f ../values/infra/identity/platform/rke2/values.yaml \
	  -f ../values/infra/identity/env/$(ENV)/values.yaml \
	  --set ingress.hostname=$(AUTH_HOST) \
	  --set smtp.from=$(SMTP_FROM) --set smtp.host=$(SMTP_HOST) --set smtp.port=$(SMTP_PORT) --set smtp.tls=$(SMTP_TLS)

dns:
	-$(KUBECTL) -n $(NS_INFRA) create secret generic hetzner-token --from-literal=token=$(HETZNER_API_TOKEN) >/dev/null 2>&1 || true
	$(HELM) repo add external-dns https://kubernetes-sigs.github.io/external-dns/ >/dev/null
	$(HELM) upgrade --install external-dns external-dns/external-dns -n $(NS_INFRA) \
	  -f ../values/infra/externaldns/platform/rke2/values.yaml \
	  --set "domainFilters={$(PARENT_ZONE)}" \
	  --set txtOwnerId="geodata-suite" \
	  --set sources="{ingress}"

tls:
	$(HELM) repo add jetstack https://charts.jetstack.io >/dev/null
	$(HELM) upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set installCRDs=true -f tls/cert-manager/values.yaml
	-$(KUBECTL) -n cert-manager create secret generic hetzner-dns --from-literal=api-token=$(HETZNER_API_TOKEN) >/dev/null 2>&1 || true
	# Hinweis: Hetzner Webhook Chart-Repo ggf. anpassen
	# $(HELM) upgrade --install cert-manager-webhook-hetzner <repo>/cert-manager-webhook-hetzner -n cert-manager -f tls/hetzner-webhook/values-variant-a.yaml

secrets:
	$(HELM) repo add external-secrets https://charts.external-secrets.io >/dev/null
	$(HELM) upgrade --install external-secrets external-secrets/external-secrets -n $(NS_INFRA) -f ../values/infra/externalsecrets/base/values.yaml
	envsubst < ../values/infra/externalsecrets/platform/rke2/clustersecretstore-vault.yaml | $(KUBECTL) -n $(NS_INFRA) apply -f -
	-$(KUBECTL) -n $(NS) apply -f ../values/infra/externalsecrets/examples/externalsecret-minio.yaml || true
	-$(KUBECTL) -n $(NS_IDP) apply -f ../values/infra/externalsecrets/examples/externalsecret-smtp-proton.yaml || true

apps:
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

status:
	$(KUBECTL) -n $(NS) get deploy,svc,ingress
	-$(KUBECTL) -n $(NS_INFRA) logs deploy/external-dns --tail=50
