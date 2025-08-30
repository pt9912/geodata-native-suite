# Docker Registry (S3) auf Hetzner – **DNS‑01 (Cloudflare)**
Caddy nutzt die **Cloudflare DNS Challenge** für Let's Encrypt. **Port 80** ist nicht nötig/geschlossen.

## Highlights
- Caddy mit Plugin **github.com/caddy-dns/cloudflare** (per xcaddy gebaut)
- TLS via DNS‑01 (Cloudflare) → kein HTTP‑01, Port 80 kann dicht bleiben
- Token wird als **Envfile** in den Container injiziert (kein Klartext im Caddyfile)
- Registry nutzt **Hetzner Object Storage (S3)** als Backend
- Optionaler Cloudflare A‑Record per Terraform (proxied=false empfohlen)

## Quickstart
1) **Packer**: Golden Image bauen (Docker + Compose sind gebaked)
```bash
cd packer
cp packer.auto.pkrvars.hcl.example packer.auto.pkrvars.hcl
./build-image.sh
```
→ `ImageName=...` notieren.

2) **Terraform**: deployen
```bash
cd ../terraform
cp terraform.tfvars.example terraform.tfvars
# image_name, S3‑Werte, registry_domain, acme_email, cf_api_token, cf_zone_id setzen
./apply.sh
```

3) **Push testen**
```bash
export FQDN=$(terraform output -raw registry_fqdn 2>/dev/null || terraform output -raw server_ipv4)
docker login https://$FQDN
docker push $FQDN/demo/alpine:latest
```

## Sicherheit
- Cloudflare‑Token liegt in `/opt/registry/.env.caddy` (600) und wird als env in den Caddy‑Container gemountet.
- Firewall: **nur 22 und 443** offen (80 geschlossen).
