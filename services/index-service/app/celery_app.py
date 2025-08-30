
# import os
# from celery import Celery

# broker_url = os.getenv("REDIS_URL", "redis://redis:6379/0")
# backend_url = os.getenv("REDIS_BACKEND_URL", "redis://redis:6379/1")
# celery = Celery("index", broker=broker_url, backend=backend_url)

import os
import json
import time
import anyio
from celery import Celery
from redis import Redis
from .db import init_schema, upsert_item
from .stac_client import StacClient
from .s3_client import list_prefix, to_stac_from_key
from .edl import EDLTokenManager
from .events import publish_item, publish_dlq

broker = os.getenv("RABBITMQ_URL", "amqp://guest:guest@rabbitmq:5672//")
backend = os.getenv("REDIS_URL", "redis://redis:6379/0")
celery = Celery("index", broker=broker, backend=backend)

celery.conf.task_routes = {"app.celery_app.*": {"queue": "index"}}
celery.conf.task_acks_late = True
celery.conf.broker_heartbeat = 0

_dlq = Redis.from_url(os.getenv("REDIS_URL", "redis://redis:6379/0"))

@celery.task(
    bind=True,
    autoretry_for=(Exception,),
    retry_backoff=5,
    retry_jitter=True,
    retry_kwargs={"max_retries": 5}
)
def run_stac_task(self, payload: dict) -> dict:
    try:
        init_schema()
        edl = EDLTokenManager()

        async def headers():
            tok = await edl.get_token()
            return {"Authorization": f"Bearer {tok}"} if tok else {}

        hdr = anyio.run(headers)
        client = StacClient(
            payload["endpoint"],
            header_provider=lambda: hdr
        )

        async def run() -> dict:
            count = 0
            async for feat in client.search(
                collections=payload.get("collections", []),
                bbox=payload.get("bbox"),
                datetime=payload.get("datetime"),
                limit=int(payload.get("limit", 100))
            ):
                props = feat.get("properties", {})
                dt = props.get("datetime") or props.get("start_datetime") or props.get("end_datetime")
                if not dt:
                    continue

                state = upsert_item(
                    id=feat.get("id"),
                    collection=feat.get("collection", "unknown"),
                    dt_iso=dt,
                    geom_geojson=feat.get("geometry"),
                    props=props
                )
                publish_item(
                    state,
                    {
                        "id": feat.get("id"),
                        "collection": feat.get("collection", "unknown"),
                        "datetime": dt,
                        "geometry": feat.get("geometry"),
                        "properties": props
                    }
                )
                count += 1
            return {"indexed": count}

        return anyio.run(run)

    except Exception as e:
        error_msg = {"task": "stac", "payload": payload, "error": str(e), "ts": time.time()}
        _dlq.lpush("index:dlq", json.dumps(error_msg))
        publish_dlq("stac", payload, str(e))
        raise

@celery.task(
    bind=True,
    autoretry_for=(Exception,),
    retry_backoff=5,
    retry_jitter=True,
    retry_kwargs={"max_retries": 5}
)
def run_s3_task(self, payload: dict) -> dict:
    try:
        init_schema()
        bucket = payload["bucket"]
        prefix = payload.get("prefix", "")
        region = payload.get("region")
        req_pays = bool(payload.get("requester_pays", False))

        count = 0
        for obj in list_prefix(bucket, prefix, region, requester_pays=req_pays):
            feat = to_stac_from_key(bucket, obj["key"])
            props = feat["properties"] or {}

            if obj.get("last_modified"):
                props["last_modified"] = obj["last_modified"]
            if obj.get("etag"):
                props["etag"] = obj["etag"]
            if obj.get("size"):
                props["size"] = obj["size"]

            dt = props.get("datetime") or obj.get("last_modified") or "1970-01-01T00:00:00Z"
            state = upsert_item(
                id=feat["id"],
                collection=feat["collection"],
                dt_iso=dt,
                geom_geojson=feat.get("geometry"),
                props=props
            )
            publish_item(
                state,
                {
                    "id": feat["id"],
                    "collection": feat["collection"],
                    "datetime": dt,
                    "geometry": feat.get("geometry"),
                    "properties": props
                }
            )
            count += 1

        return {"indexed": count}

    except Exception as e:
        error_msg = {"task": "s3", "payload": payload, "error": str(e), "ts": time.time()}
        _dlq.lpush("index:dlq", json.dumps(error_msg))
        publish_dlq("s3", payload, str(e))
        raise
