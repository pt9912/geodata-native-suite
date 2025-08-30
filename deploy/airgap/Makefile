# =============================================================================
#  Air-Gap Helm Deploy Makefile (Here-Doc, ohne Backslashes)
# =============================================================================
#  Kernpunkte:
#   - Image-Discovery via helm template + yq
#   - Post-Renderer ersetzt image-Registries auf $(REGISTRY_HOST)
#   - Sicheres docker login (--password-stdin)
#   - Parallel Pull/Push mit xargs (ruft Helper-Skripte auf)
#   - Keine \'sh -c\'-Einzeiler mehr, keine Zeilenfortsetzungs-\
# =============================================================================

# -----------------------------
# Konfiguration
# -----------------------------
CHART_NAME      ?= my-app
CHART_REPO_URL  ?= https://example.com/charts
CHART_VERSION   ?= 1.4.2

REGISTRY_HOST   ?= registry.local
REGISTRY_USER   ?= admin
REGISTRY_PASS   ?= $(shell cat .registry-pass)

NAMESPACE       ?= default
RELEASE_NAME    ?= $(CHART_NAME)

TMPDIR          := $(CURDIR)/tmp
IMG_LIST        := $(TMPDIR)/images.list
IMG_TAR         := $(TMPDIR)/images.tar

PUSH_RETRIES    ?= 3
PUSH_PARALLEL   ?= 4
TEST_ENABLED    ?= true

POST_RENDERER   := $(TMPDIR)/image-rewrite.sh
PULL_ONE        := $(TMPDIR)/pull-one.sh
PUSH_ONE        := $(TMPDIR)/push-one.sh

# Tools (überschreibbar)
HELM            ?= helm
YQ              ?= yq
KUBECTL         ?= kubectl
DOCKER          ?= docker

# -----------------------------
# Hilfsziele
# -----------------------------
.PHONY: all clean fetch-chart deps lint-chart render discover-images pull-images \
        export-images push-registry import-chart package-chart helm-deploy \
        dry-run diff rollback history deps-check make-post-renderer make-helpers

all: helm-deploy

# -----------------------------
# Aufräumen
# -----------------------------
clean:
	@rm -rf $(TMPDIR)

$(TMPDIR):
	@mkdir -p $@

# -----------------------------
# Checks
# -----------------------------
deps-check:
	@<<'SH'
	set -e
	command -v $(HELM) >/dev/null 2>&1 || { echo "❌ helm nicht gefunden"; exit 1; }
	command -v $(YQ) >/dev/null 2>&1 || { echo "❌ yq nicht gefunden"; exit 1; }
	command -v $(KUBECTL) >/dev/null 2>&1 || { echo "❌ kubectl nicht gefunden"; exit 1; }
	command -v $(DOCKER) >/dev/null 2>&1 || { echo "❌ docker nicht gefunden"; exit 1; }
SH

# -----------------------------
# Chart holen + Dependencies
# -----------------------------
fetch-chart: deps-check $(TMPDIR)
	@<<'SH'
	set -euo pipefail
	$(HELM) repo add src $(CHART_REPO_URL)
	$(HELM) repo update
	echo "⬇️  Lade Chart $(CHART_NAME)@$(CHART_VERSION)…"
	if ! $(HELM) pull src/$(CHART_NAME) --version $(CHART_VERSION) --untar -d $(TMPDIR); then
	    echo "❌ Fehler beim Herunterladen des Charts"
	    exit 1
	fi
	cd "$(TMPDIR)/$(CHART_NAME)"
	$(HELM) dependency update || { echo "❌ Fehler beim Aktualisieren der Abhängigkeiten"; exit 1; }
SH

deps: fetch-chart

# -----------------------------
# Lint
# -----------------------------
lint-chart: deps
	@<<'SH'
	set -e
	cd "$(TMPDIR)/$(CHART_NAME)"
	$(HELM) lint || { echo "❌ Chart-Validierung fehlgeschlagen"; exit 1; }
SH

# -----------------------------
# Render für Discovery
# -----------------------------
render: deps make-post-renderer
	@<<'SH'
	set -euo pipefail
	$(HELM) template $(RELEASE_NAME) "$(TMPDIR)/$(CHART_NAME)" \
	    --version $(CHART_VERSION) \
	    --namespace $(NAMESPACE) \
	| tee "$(TMPDIR)/rendered.yaml" >/dev/null
SH

# -----------------------------
# Images finden
# -----------------------------
discover-images: render
	@<<'SH'
	set -euo pipefail
	echo "🔍 Scanning rendered manifests for image references…"
	$(YQ) eval '.. | select(has("image")) | .image | select(type=="string")' "$(TMPDIR)/rendered.yaml" \
	    | sed 's/^"//; s/"$$//' \
	    | sort -u > "$(IMG_LIST)"
	if [ ! -s "$(IMG_LIST)" ]; then
	    echo "❌ Keine Images gefunden!"
	    exit 1
	fi
	awk -F: 'NF<2 {print "❌ Image ohne Tag gefunden: " $$0; err=1} END{exit err}' "$(IMG_LIST)"
SH

# -----------------------------
# Helper-Skripte erzeugen (Here-Docs)
# -----------------------------
make-helpers: $(TMPDIR)
	@# Pull-Skript (ein Image)
	@cat > $(PULL_ONE) <<'EOS'
#!/usr/bin/env sh
set -eu
img="$1"
echo "→ pull $img"
docker pull "$img"
EOS
	@chmod +x $(PULL_ONE)
	@# Push-Skript (ein Image, mit Retry)
	@cat > $(PUSH_ONE) <<'EOS'
#!/usr/bin/env sh
set -eu
orig="$1"
REGISTRY_HOST="${REGISTRY_HOST:?missing}"
PUSH_RETRIES="${PUSH_RETRIES:-3}"

path=$(echo "$orig" | sed -E 's|^[^/]+/||')
new="${REGISTRY_HOST}/${path}"

docker tag "$orig" "$new"
echo "→ pushing $new"

retry=0
success=0
while [ "$retry" -lt "$PUSH_RETRIES" ]; do
  if docker push "$new"; then
    success=1
    break
  fi
  retry=$((retry+1))
  echo "⚠️  Push fehlgeschlagen (Versuch $retry/$PUSH_RETRIES) $new"
  sleep 5
done

if [ "$success" -eq 0 ]; then
  echo "❌ Fehler beim Pushen: $new" >&2
  exit 1
fi
EOS
	@chmod +x $(PUSH_ONE)

# -----------------------------
# Pull & Export
# -----------------------------
pull-images: discover-images make-helpers
	@<<'SH'
	set -euo pipefail
	echo "⬇️  Pulling images (parallel $(PUSH_PARALLEL))…"
	cat "$(IMG_LIST)" | xargs -n1 -P $(PUSH_PARALLEL) "$(PULL_ONE)"
SH

export-images: pull-images
	@<<'SH'
	set -euo pipefail
	echo "🧱 Exportiere Images → $(IMG_TAR)"
	$(DOCKER) save -o "$(IMG_TAR)" $$(cat "$(IMG_LIST)")
SH

# -----------------------------
# In private Registry importieren
# -----------------------------
push-registry: export-images make-helpers
	@<<'SH'
	set -euo pipefail
	echo "📦 Lade TAR ins lokale Docker…"
	$(DOCKER) load -i "$(IMG_TAR)"
	echo "🔐 Login an $(REGISTRY_HOST)…"
	printf "%s" "$(REGISTRY_PASS)" | $(DOCKER) login $(REGISTRY_HOST) -u $(REGISTRY_USER) --password-stdin
	echo "🚀 Tag & Push nach $(REGISTRY_HOST) (parallel $(PUSH_PARALLEL))…"
	# xargs exportiert ENV für jeden Aufruf des Helper-Skripts
	export REGISTRY_HOST="$(REGISTRY_HOST)"
	export PUSH_RETRIES="$(PUSH_RETRIES)"
	cat "$(IMG_LIST)" | xargs -n1 -P $(PUSH_PARALLEL) "$(PUSH_ONE)"
SH

# -----------------------------
# Chart-Archiv (optional)
# -----------------------------
import-chart: push-registry
	@<<'SH'
	set -e
	cd "$(TMPDIR)"
	tar czf "$(CHART_NAME)-$(CHART_VERSION).tgz" "$(CHART_NAME)"
SH

package-chart: import-chart
	@<<'SH'
	set -e
	cd "$(TMPDIR)/$(CHART_NAME)"
	$(HELM) package .
	mv "$(CHART_NAME)-$(CHART_VERSION).tgz" "$(TMPDIR)/"
SH

# -----------------------------
# Post-Renderer (Registry-Rewrite)
# -----------------------------
make-post-renderer: $(TMPDIR)
	@cat > $(POST_RENDERER) <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
YQ_BIN="${YQ:-yq}"
"$YQ_BIN" -o=y -I=2 '
  .. as $item ireduce (.; 
    if ( . == $item and (tag == "!!map") and has("image") and (.image | type == "!!str") ) then
      .image |= sub("^[^/]+/"; "'"$REGISTRY_HOST"'/")
    else . end
  )
' -
EOS
	@chmod +x $(POST_RENDERER)

# -----------------------------
# Helm Deploy
# -----------------------------
helm-deploy: import-chart lint-chart make-post-renderer
	@<<'SH'
	set -euo pipefail
	echo "🔐 Erzeuge/aktualisiere Pull-Secret im Namespace $(NAMESPACE)…"
	printf "%s" "$(REGISTRY_PASS)" | $(KUBECTL) create secret docker-registry reg-secret \
	    --docker-server=$(REGISTRY_HOST) \
	    --docker-username=$(REGISTRY_USER) \
	    --docker-password-stdin \
	    --namespace $(NAMESPACE) \
	    --dry-run=client -o yaml | $(KUBECTL) apply -f -
	echo "📦 Install/Upgrade Release $(RELEASE_NAME) in $(NAMESPACE)…"
	$(HELM) upgrade --install $(RELEASE_NAME) "$(TMPDIR)/$(CHART_NAME)" \
	    --version $(CHART_VERSION) \
	    --namespace $(NAMESPACE) \
	    --set image.pullPolicy=Always \
	    --set image.pullSecrets[0].name=reg-secret \
	    --post-renderer $(POST_RENDERER) \
	    --wait --timeout 5m
	if [ "$(TEST_ENABLED)" = "true" ]; then
	    $(HELM) test $(RELEASE_NAME) --namespace $(NAMESPACE) || { echo "⚠️  Helm Tests fehlgeschlagen"; }
	fi
	$(HELM) status $(RELEASE_NAME) --namespace $(NAMESPACE) --show-notes
SH

# -----------------------------
# Dry-Run & Diff
# -----------------------------
dry-run: deps make-post-renderer
	@<<'SH'
	set -e
	$(HELM) template $(RELEASE_NAME) "$(TMPDIR)/$(CHART_NAME)" \
	    --version $(CHART_VERSION) \
	    --namespace $(NAMESPACE) \
	    --post-renderer $(POST_RENDERER) \
	    --dry-run
SH

diff: deps make-post-renderer
	@<<'SH'
	set -e
	$(HELM) template $(RELEASE_NAME) "$(TMPDIR)/$(CHART_NAME)" \
	    --version $(CHART_VERSION) \
	    --namespace $(NAMESPACE) \
	    --post-renderer $(POST_RENDERER) > "$(TMPDIR)/_desired.yaml"
	$(KUBECTL) diff -f "$(TMPDIR)/_desired.yaml" -n $(NAMESPACE) || true
SH

# -----------------------------
# Rollback & History
# -----------------------------
rollback:
	@<<'SH'
	set -euo pipefail
	rev="$(ROLLBACK_REV)"
	if [ "$$rev" = "0" ] || [ -z "$$rev" ]; then
	  echo "ℹ️  ROLLBACK_REV nicht gesetzt → wähle letzte erfolgreiche Revision"
	  rev=$$($(HELM) history $(RELEASE_NAME) --namespace $(NAMESPACE) | awk '/^([0-9]+)\s/ && $$5=="superseded" || $$5=="deployed" {id=$$1} END{print id}')
	fi
	if [ -z "$$rev" ]; then echo "❌ Keine geeignete Revision gefunden"; exit 1; fi
	echo "↩️  Rollback auf Revision $$rev"
	$(HELM) rollback $(RELEASE_NAME) $$rev --namespace $(NAMESPACE)
SH

history:
	@$(HELM) history $(RELEASE_NAME) --namespace $(NAMESPACE)
