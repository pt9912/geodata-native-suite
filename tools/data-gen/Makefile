
IMAGE?=geodata-datagen
OUT?=$(PWD)/out
PG?=postgresql://app:apppw@localhost:5432/geodata
BOOTSTRAP?=localhost:9092
SCHEMA_URL?=http://localhost:8081

all: build

build:
	docker build -t $(IMAGE) .

giant-cog: build
	mkdir -p $(OUT)
	docker run --rm -v $(OUT):/out $(IMAGE) python /app/gen_geotiff.py --width 65536 --height 65536 --dtype float32 --cog --outfile /out/giant_16gb.tif

small-cogs: build
	mkdir -p $(OUT)
	docker run --rm -v $(OUT):/out $(IMAGE) python /app/gen_geotiff.py --width 8192 --height 8192 --dtype uint16 --cog --outfile /out/small1.tif
	docker run --rm -v $(OUT):/out $(IMAGE) python /app/gen_geotiff.py --width 8192 --height 8192 --dtype uint16 --cog --outfile /out/small2.tif

upload-minio: build
	docker run --rm -v $(OUT):/data $(IMAGE) python /app/upload_s3.py --endpoint http://localhost:9000 --access-key minioadmin --secret-key minioadmin123 --bucket mybucket --prefix test --path /data

stac-grid: build
	docker run --rm $(IMAGE) python /app/gen_grid_stac.py --bbox 6.0,49.0,8.0,51.0 --tiles 20,20 --from 2025-08-01 --to 2025-08-07 | \
	docker run -i --rm $(IMAGE) python /app/bulk_index_postgis.py --pg $(PG)

fuzz-events: build
	docker run --rm $(IMAGE) python /app/event_fuzzer.py --bootstrap $(BOOTSTRAP) --schema-url $(SCHEMA_URL) --count 1000 --schema-file /schemas/StacItem.avsc
