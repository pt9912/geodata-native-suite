# Changelog

## 2025-08-28 – Here-Doc ohne Backslashes
- Hilfsskripte via Here-Docs erzeugt (pull-one.sh, push-one.sh)
- xargs ruft Hilfsskripte direkt auf → keine Backslashes, bessere Lesbarkeit
- Funktionalität identisch zur vorherigen Here-Doc-Version

## 2025-08-28 – Here-Doc-Version
- Rezepte auf Here-Docs umgestellt (bessere Lesbarkeit, weniger `\`).
- Funktional identisch zu vormaliger robuster Version.

## [2025-08-28] Air-Gap Makefile Überarbeitung
- Image Discovery via `helm template` + `yq`
- Helm Post-Renderer zur registry-Umschreibung
- Parallelisierte Pull/Push-Pipeline
- Sichere Logins via `--password-stdin`
- Robustere Rollback-Logik
