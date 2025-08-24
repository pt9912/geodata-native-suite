
import os, json, traceback, redis
from .celery_app import celery
from .s3_indexer import list_objects, to_stac_item
from .events import publish

REDIS_URL = os.getenv("REDIS_URL","redis://redis:6379/0")
DLQ_KEY = os.getenv("DLQ_KEY","index:dlq")
r = redis.Redis.from_url(REDIS_URL, decode_responses=True)

@celery.task(bind=True, max_retries=3)
def index_prefix_task(self, bucket: str, prefix: str, endpoint_url: str | None = None):
    try:
        import asyncio
        async def run():
            async for obj in list_objects(bucket, prefix, endpoint_url):
                item = to_stac_item(bucket, obj["Key"])
                publish("stac.item.indexed", item)
        asyncio.run(run())
        return {"status":"done","bucket":bucket,"prefix":prefix}
    except Exception as e:
        tb = traceback.format_exc()
        r.lpush(DLQ_KEY, json.dumps({"bucket":bucket,"prefix":prefix,"error":str(e),"trace":tb}))
        raise self.retry(exc=e, countdown=60)
