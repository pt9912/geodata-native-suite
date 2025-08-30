
# Harte Testdaten – Generator

Dieses Tooling erzeugt große GeoTIFF/COG-Dateien, synthetische STAC-Items, lädt Daten nach MinIO/S3 und publiziert Events nach Kafka.

## Beispiele
- **16GB COG**: `make giant-cog`
- **2× 8k COG**: `make small-cogs`
- **Upload zu MinIO**: `make upload-minio` (nach `small-cogs`)
- **STAC-Grid in PostGIS**: `make stac-grid` (erfordert laufenden Postgres)
- **Kafka-Fuzzer**: `make fuzz-events`



###
```bash
mkdir -p out
docker run --rm -u $(id -u):$(id -g) -v $PWD/out:/out geodata-datagen  python /app/gen_geotiff.py \
    --width 1200 --height 1200 --dtype float32 --cog --outfile /out/demo_1200x1200.tif

docker run --rm -u $(id -u):$(id -g) -v $PWD/out:/out geodata-datagen  python /app/gen_geotiff.py \
    --width 2400 --height 2400 --dtype float32 --cog --outfile /out/demo_2400x2400.tif

docker run --rm -u $(id -u):$(id -g) -v $PWD/out:/out geodata-datagen  python /app/gen_geotiff.py \
    --width 4800 --height 4800 --dtype float32 --cog --outfile /out/demo_4800x4800.tif

docker run --rm -u $(id -u):$(id -g) -v $PWD/out:/out geodata-datagen  python /app/gen_geotiff.py \
    --width 9600 --height 9600 --dtype float32 --cog --outfile /out/demo_9600x9600.tif

docker run --rm -u $(id -u):$(id -g) -v $PWD/out:/out geodata-datagen  python /app/gen_geotiff.py \
    --width 19200 --height 19200 --dtype float32 --cog --outfile /out/demo_19200x19200.tif
```


```bash
mkdir -p out
docker run --rm -u $(id -u):$(id -g) -v $PWD/out:/out geodata-datagen python /app/bulk_index_spatialite.py \
   --db /out/spatialite_test.db 


docker run --rm geodata-datagen   python /app/gen_grid_stac.py --bbox 6.0,49.0,8.0,51.0 --tiles 10,10 --from 2025-08-01 --to 2025-08-31  | \
docker run --rm -u $(id -u):$(id -g) -v $PWD/out:/out geodata-datagen python /app/bulk_index_spatialite.py \
   --db /out/geodata_202508.db 


docker run --rm -u $(id -u):$(id -g) -v $PWD/out:/out geodata-datagen sqlite3 /out/geodata_202508.db \
    "SELECT load_extension('mod_spatialite'); SELECT id, collection, dt props, AsText(geom) FROM items LIMIT 5;"
```
