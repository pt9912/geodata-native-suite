import os
import json
import traceback
import redis
from datetime import datetime
import logging
from opentelemetry import trace, metrics
from opentelemetry.trace import get_current_span
from opentelemetry.propagate import inject
from botocore.exceptions import ClientError
from .celery_app import celery
from .s3_indexer import list_objects, to_stac_item
from .events import publish
from .tracing import tracer

REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
DLQ_STREAM_KEY = os.getenv("DLQ_STREAM_KEY", "index:dlq:stream")
BATCH_SIZE = 100  # Anzahl der Items pro Batch

r = redis.Redis.from_url(REDIS_URL, decode_responses=True)
logger = logging.getLogger(__name__)

meter = metrics.get_meter(__name__)
item_counter = meter.create_counter(
    "stac.items.indexed",
    description="Number of STAC items indexed",
)
error_counter = meter.create_counter(
    "stac.items.error",
    description="Number of STAC items that failed processing",
)
dlq_counter = meter.create_counter(
    "stac.dlq.entries",
    description="Number of entries added to the DLQ",
)
batch_size_histogram = meter.create_histogram(
    "stac.batch.size",
    description="Distribution of STAC item batch sizes",
)

@celery.task(bind=True, max_retries=3)
async def index_prefix_task(self, bucket: str, prefix: str, endpoint_url: str | None = None):
    task_id = self.request.id
    current_span = get_current_span()
    logger.info(
        "Starting index_prefix_task",
        extra={
            "task_id": task_id,
            "bucket": bucket,
            "prefix": prefix,
            "trace_id": current_span.get_span_context().trace_id,
            "span_id": current_span.get_span_context().span_id,
        }
    )
    with tracer.start_as_current_span("index_prefix_task") as span:
        span.set_attribute("bucket", bucket)
        span.set_attribute("prefix", prefix)
        try:
            batch = []
            async for obj in list_objects(bucket, prefix, endpoint_url):
                with tracer.start_as_current_span("process_object") as obj_span:
                    obj_span.set_attribute("s3.key", obj["Key"])
                    try:
                        item = to_stac_item(bucket, obj["Key"])
                        batch.append(item)
                        if len(batch) >= BATCH_SIZE:
                            headers = {}
                            inject(get_current(), headers)
                            await publish("stac.items.batch", batch, headers=headers)
                            item_counter.add(len(batch), {"bucket": bucket, "prefix": prefix})
                            batch_size_histogram.record(len(batch), {"bucket": bucket, "prefix": prefix})
                            batch = []
                    except ClientError as e:
                        error_code = e.response.get("Error", {}).get("Code", "Unknown")
                        obj_span.set_attribute("s3.error_code", error_code)
                        error_counter.add(1, {"bucket": bucket, "key": obj["Key"], "error_code": error_code})
                        dlq_counter.add(1, {"bucket": bucket, "reason": f"s3_error:{error_code}"})
                        logger.error(
                            "S3 error processing object",
                            extra={
                                "task_id": task_id,
                                "bucket": bucket,
                                "key": obj["Key"],
                                "error_code": error_code,
                                "error": str(e),
                                "trace_id": current_span.get_span_context().trace_id,
                            }
                        )
                        r.xadd(
                            DLQ_STREAM_KEY,
                            {
                                "task_id": task_id,
                                "bucket": bucket,
                                "key": obj["Key"],
                                "error_code": error_code,
                                "error": str(e),
                                "trace": traceback.format_exc(),
                                "timestamp": datetime.utcnow().isoformat(),
                            },
                            maxlen=10000,
                            approximate=True
                        )
                    except Exception as obj_error:
                        obj_span.record_exception(obj_error)
                        error_counter.add(1, {"bucket": bucket, "key": obj["Key"]})
                        dlq_counter.add(1, {"bucket": bucket, "reason": "object_processing_failed"})
                        logger.error(
                            "Failed to process object",
                            extra={
                                "task_id": task_id,
                                "bucket": bucket,
                                "key": obj["Key"],
                                "error": str(obj_error),
                                "trace_id": current_span.get_span_context().trace_id,
                            }
                        )
                        r.xadd(
                            DLQ_STREAM_KEY,
                            {
                                "task_id": task_id,
                                "bucket": bucket,
                                "key": obj["Key"],
                                "error": str(obj_error),
                                "trace": traceback.format_exc(),
                                "timestamp": datetime.utcnow().isoformat(),
                            },
                            maxlen=10000,
                            approximate=True
                        )
            if batch:  # Veröffentliche restliche Items im Batch
                headers = {}
                inject(get_current(), headers)
                await publish("stac.items.batch", batch, headers=headers)
                item_counter.add(len(batch), {"bucket": bucket, "prefix": prefix})
                batch_size_histogram.record(len(batch), {"bucket": bucket, "prefix": prefix})
            logger.info(
                "Task completed successfully",
                extra={
                    "task_id": task_id,
                    "bucket": bucket,
                    "prefix": prefix,
                    "trace_id": current_span.get_span_context().trace_id,
                }
            )
            return {"status": "done", "bucket": bucket, "prefix": prefix}
        except Exception as e:
            span.record_exception(e)
            dlq_counter.add(1, {"bucket": bucket, "reason": "task_failure"})
            logger.error(
                "Task failed, scheduling retry",
                extra={
                    "task_id": task_id,
                    "bucket": bucket,
                    "prefix": prefix,
                    "error": str(e),
                    "trace_id": current_span.get_span_context().trace_id,
                }
            )
            r.xadd(
                DLQ_STREAM_KEY,
                {
                    "task_id": task_id,
                    "bucket": bucket,
                    "prefix": prefix,
                    "error": str(e),
                    "trace": traceback.format_exc(),
                    "timestamp": datetime.utcnow().isoformat(),
                },
                maxlen=10000,
                approximate=True
            )
            raise self.retry(exc=e, countdown=60)


@celery.task(name="process_dlq_stream")
def process_dlq_stream():
    logger = logging.getLogger(__name__)
    last_id = "$"  # Start vom Anfang des Streams
    while True:
        try:
            # Blockierend auf neue Einträge warten
            messages = r.xread({DLQ_STREAM_KEY: last_id}, count=10, block=5000)
            if not messages:
                continue

            for stream, entries in messages:
                for entry_id, entry in entries:
                    try:
                        logger.warning(
                            "Processing DLQ entry",
                            extra={
                                "entry_id": entry_id,
                                "task_id": entry["task_id"],
                                "bucket": entry["bucket"],
                                "key": entry.get("key", ""),
                                "error": entry["error"],
                            }
                        )
                        # Hier können Sie z. B.:
                        # - Benachrichtigungen senden (Slack, E-Mail)
                        # - Manuelle Wiederholung auslösen
                        # - Statistiken aktualisieren
                    except Exception as e:
                        logger.error(
                            "Failed to process DLQ entry",
                            extra={"entry_id": entry_id, "error": str(e)}
                        )
                    finally:
                        last_id = entry_id  # Fortschritt speichern
        except redis.ConnectionError:
            logger.error("Redis connection lost, retrying...")
            time.sleep(5)
            
            
# @celery.task(bind=True, max_retries=3)
# def index_prefix_task(self, bucket: str, prefix: str, endpoint_url: str | None = None):
#     try:
#         import asyncio
#         async def run():
#             async for obj in list_objects(bucket, prefix, endpoint_url):
#                 item = to_stac_item(bucket, obj["Key"])
#                 publish("stac.item.indexed", item)
#         asyncio.run(run())
#         return {"status":"done","bucket":bucket,"prefix":prefix}
#     except Exception as e:
#         tb = traceback.format_exc()
#         r.lpush(DLQ_KEY, json.dumps({"bucket":bucket,"prefix":prefix,"error":str(e),"trace":tb}))
#         raise self.retry(exc=e, countdown=60)        