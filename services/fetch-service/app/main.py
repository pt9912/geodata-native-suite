
from fastapi import FastAPI, HTTPException, Response, Request
from pydantic import BaseModel
from typing import Optional
from .config import MODE, ALLOWED_BUCKETS
from .s3util import presign

import os, json, uuid, time, urllib.parse
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from confluent_kafka import Producer

from botocore.exceptions import ClientError


app = FastAPI(title="fetch-service", version="0.2.0")


PRESIGN_ERRORS = Counter('geodata_presign_errors_total','Presign errors')
RELAY_REQ = Counter('geodata_relay_requests_total','Relay requests')
RELAY_LAT = Histogram('geodata_relay_latency_seconds','Relay latency')
DEMO_TOKEN = os.getenv("DEMO_TOKEN","demo")
CONFIG_FILE = os.getenv("CONFIG_FILE","/app/config/config.yaml")
KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP","redpanda:9092")

producer = Producer({"bootstrap.servers": KAFKA_BOOTSTRAP})

class FetchJob(BaseModel):
    bucket: str
    key: str
    mode: Optional[str] = None
    content_type: Optional[str] = "application/octet-stream"

def authed(request: Request):
    a = request.headers.get("Authorization", "")
    return a.startswith("Bearer ") and a.split(" ",1)[1] == DEMO_TOKEN

def emit_status(id, status, extra=None):
    value = {"id": id, "status": status, "ts": int(time.time()), **(extra or {})}
    producer.produce("fetch.job.status", key=id, value=json.dumps(value).encode("utf-8"))
    producer.poll(0)




@app.get("/health")
def health():
    return {"status":"OK","mode":MODE}

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


@app.get("/download/s3/<bucket>/<path:key>")
def dl(bucket, key, request: Request):
    req_id = str(uuid.uuid4())
    emit_status(req_id, "queued", {"bucket":bucket,"key":key})
    if not authed(request):
        emit_status(req_id, "error", {"reason":"unauthorized"})
        return Response("Unauthorized\n",401)
    if bucket.lower() not in ALLOWED:
        emit_status(req_id, "error", {"reason":"forbidden"})
        return Response("Forbidden\n",403)
    try:
        url = presign(bucket, key, request.args.get("expires","1800"),
                      request.args.get("region"), request.args.get("requester_pays","0") in ("1","true","yes"))
    except ClientError as e:
        emit_status(req_id, "error", {"reason":str(e)})
        return Response(f"Presign error: {e}\n", 502)
    loc = "/internal/relay?u=" + urllib.parse.quote(url, safe="")
    emit_status(req_id, "running")
    emit_status(req_id, "done")
    return Response(status=200, headers={"X-Accel-Redirect": loc,
                                         "X-Accel-Buffering":"yes",
                                         "Content-Disposition": f'attachment; filename="{os.path.basename(key)}"',
                                         "X-Request-Id": req_id})


@app.post("/api/v1/fetch")
def fetch(job: FetchJob, request: Request):
    if ALLOWED_BUCKETS and job.bucket not in ALLOWED_BUCKETS:
        raise HTTPException(status_code=403, detail="Bucket not allowed")
    mode = (job.mode or MODE).lower()
    if mode == "presigned":
        url = presign(job.bucket, job.key)
        return {"status":"ok","mode":"presigned","url":url}
    elif mode == "accel":
        headers = {
            "X-Accel-Redirect": f"/internal/s3/{job.bucket}/{job.key}",
            "Content-Type": job.content_type or "application/octet-stream"
        }
        return Response(status_code=200, headers=headers)
    else:
        raise HTTPException(status_code=400, detail="mode must be presigned|accel")
