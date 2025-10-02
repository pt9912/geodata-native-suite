import json
import logging
import os
import time
import uuid
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Iterable, Optional

from celery import Celery
from confluent_kafka import Producer
from botocore.exceptions import ClientError

from .clipper import ClipError, clip_geotiff
from .s3util import download_to_path, upload_file


logger = logging.getLogger(__name__)


broker_url = os.getenv("CELERY_BROKER_URL", "redis://redis:6379/0")
backend_url = os.getenv("CELERY_BACKEND", "redis://redis:6379/1")
celery_app = Celery("fetch", broker=broker_url, backend=backend_url)
celery_app.conf.task_default_queue = "fetch"

producer = Producer({"bootstrap.servers": os.getenv("KAFKA_BOOTSTRAP", "redpanda:9092")})


def emit_status(job_id: str, status: str, extra: Optional[dict] = None):
    payload = {"id": job_id, "status": status, "ts": int(time.time())}
    if extra:
        payload.update(extra)
    try:
        producer.produce("fetch.job.status", key=job_id, value=json.dumps(payload).encode("utf-8"))
        producer.poll(0)
    except Exception as exc:  # pragma: no cover - telemetry failures must not abort jobs
        logger.warning("failed to emit job status event", exc_info=exc)


def _normalize_bbox(bbox: Optional[Iterable[float]]) -> Optional[list[float]]:
    if bbox is None:
        return None
    values = list(bbox)
    if len(values) != 4:
        raise ValueError("bbox must contain exactly four values [minx,miny,maxx,maxy]")
    return [float(v) for v in values]


@celery_app.task(bind=True, max_retries=3, default_retry_delay=10)
def clip_dataset(
    self,
    source_bucket: str,
    source_key: str,
    dest_bucket: Optional[str] = None,
    bbox: Optional[Iterable[float]] = None,
    crs: str = "EPSG:4326",
    requester_pays: bool = False,
):
    job_id = self.request.id or uuid.uuid4().hex
    normalized_bbox = _normalize_bbox(bbox)
    emit_status(job_id, "running", {
        "bucket": source_bucket,
        "key": source_key,
        "bbox": normalized_bbox,
        "crs": crs,
    })

    dest_bucket = dest_bucket or source_bucket
    result_prefix = os.getenv("CLIP_OUTPUT_PREFIX", "processed/").rstrip("/")
    result_key = f"{result_prefix}/{uuid.uuid4().hex}-{os.path.basename(source_key)}"

    try:
        with TemporaryDirectory() as tmpdir:
            src_path = Path(tmpdir) / "source.tif"
            dst_path = Path(tmpdir) / "clip.tif"
            download_to_path(source_bucket, source_key, src_path, requester_pays=requester_pays)
            clip_geotiff(src_path, dst_path, normalized_bbox, crs)
            upload_file(dest_bucket, result_key, dst_path)
    except (ClientError, ClipError) as exc:
        emit_status(job_id, "error", {"reason": str(exc)})
        raise self.retry(exc=exc)

    result = {
        "status": "done",
        "bucket": dest_bucket,
        "key": result_key,
        "bbox": normalized_bbox,
        "crs": crs,
    }
    emit_status(job_id, "done", result)
    return result
