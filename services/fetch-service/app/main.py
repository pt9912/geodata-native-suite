
from fastapi import FastAPI, HTTPException, Response
from pydantic import BaseModel
from typing import Optional
from .config import MODE, ALLOWED_BUCKETS
from .s3util import presign

app = FastAPI(title="fetch-service", version="0.2.0")

class FetchJob(BaseModel):
    bucket: str
    key: str
    mode: Optional[str] = None
    content_type: Optional[str] = "application/octet-stream"

@app.get("/health")
def health():
    return {"status":"OK","mode":MODE}

@app.post("/api/v1/fetch")
def fetch(job: FetchJob):
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
