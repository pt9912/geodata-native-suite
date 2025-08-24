# Patch v1 für `geodata-3`

Dieser Patch ergänzt Stubs/Implementierungen für:
- **search-service**: STAC `/search` (POST), Textsuche-Feld `q`, BBox-Reprojektion `EPSG:3857→EPSG:4326`.
- **index-service**: S3 Prefix-Listing (Requester-Pays), STAC-Minimalableitung, Kafka-Events (Stub), APScheduler, Retry/DLQ via Redis.
- **fetch-service**: Presigned-URL **oder** `X-Accel-Redirect` (NGINX Offloading), Bucket-Whitelist.
- **nginx-stream**: internes Ziel `/internal/s3/...` für `X-Accel-Redirect`.

## Anwendung
Im Repo-Root (Branch `geodata-3`) ausführen:
```bash
unzip geodata-native-suite-patch-geodata-3-v1.zip -d .
git add services/* deploy/* || true
git commit -m "patch: STAC search + indexer scheduler + fetch accel/presigned + nginx internal"
git push
```

## Env
- **S3**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, optional `S3_ENDPOINT_URL`
- **Requester-Pays**: `REQUEST_PAYER=requester`
- **index-service**: `REDIS_URL`, `KAFKA_BOOTSTRAP_SERVERS` (optional), `INDEX_CONFIG=/app/config/providers.yaml`
- **fetch-service**: `FETCH_MODE=presigned|accel`, `ALLOWED_BUCKETS_FILE=/app/config/allowed-buckets.yaml`
