
import os
from fastapi import FastAPI
from pydantic import BaseModel
from .tasks import index_prefix_task
from .scheduler import setup_scheduler

class IndexRequest(BaseModel):
    bucket: str
    prefix: str = ""
    endpoint_url: str | None = None

app = FastAPI(title="index-service", version="0.2.0")

@app.on_event("startup")
def _startup():
    if os.getenv("ENABLE_SCHEDULER","true").lower() in ("1","true","yes"):
        setup_scheduler()

@app.get("/health")
def health():
    return {"status":"OK"}

@app.post("/api/v1/index")
def trigger_index(req: IndexRequest):
    res = index_prefix_task.delay(req.bucket, req.prefix, req.endpoint_url)
    return {"status":"queued","task_id":res.id}
