# Air-Gap Helm Deploy (Makefile)

Dieses Paket liefert ein robustes Makefile für Air-Gap-Deployments von Helm-Charts.

## Kernideen
- **Image Discovery** über `helm template` → keine blind spots.
- **Keine Chart-Anpassungen nötig**: Images werden per **Helm Post-Renderer** auf die private Registry umgeschrieben (`$(REGISTRY_HOST)/<original_path>`).
- **Sicheres Handling**: `docker login --password-stdin`, Pull-Secret via `kubectl`.
- **Parallelisierung** bei Pull/Push.
- **Rollback** nimmt automatisch die letzte erfolgreiche Revision, wenn `ROLLBACK_REV` nicht gesetzt ist.

## Voraussetzungen
- `helm`, `yq`, `kubectl`, `docker`
- Zugriff auf die private Registry (`REGISTRY_HOST`, `REGISTRY_USER`, `.registry-pass` Datei im Projektroot)


## Schnelleinstieg

```bash
# Variablen anpassen
export CHART_NAME=my-app
export CHART_REPO_URL=https://example.com/charts
export CHART_VERSION=1.4.2
export REGISTRY_HOST=registry.local
export REGISTRY_USER=admin
echo 'meinpasswort' > .registry-pass

# Deploy
make helm-deploy

# Nur Images in Registry spiegeln
make push-registry

# Dry-Run/Diff
make dry-run
make diff

# Rollback (automatische letzte erfolgreiche Revision)
make rollback
# …oder explizit
make ROLLBACK_REV=3 rollback
```

## Wie funktioniert der Post-Renderer?
Der Post-Renderer liest die von Helm gerenderten Manifeste und ersetzt jede Zeichenkette an Feldern `image:` so, dass die ursprüngliche Registry-Domain entfernt und durch `$(REGISTRY_HOST)` ersetzt wird. Der Rest des Pfads (Repo + Tag/Digest) bleibt erhalten.

> Beispiel: `ghcr.io/org/app:1.2.3` → `registry.local/org/app:1.2.3`

Dadurch musst du keine chart-spezifischen `values.yaml`-Keys kennen.

## Hinweis
- Für CRDs oder sehr große Diff-Outputs nutzt das Target `diff` `kubectl diff` gegen den Cluster-Zustand.
