
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional, List
import os

app = FastAPI(title="index-service", version="0.1.0")

class IndexRequest(BaseModel):
    provider: str
    prefix: Optional[str] = None
    bucket: Optional[str] = None
    requester_pays: bool = False
    max_keys: int = 1000

@app.get("/health")
def health():
    return {"status":"OK"}

@app.post("/api/v1/index")
def run_index(req: IndexRequest):
    # TODO: S3 Prefix Listing, STAC ableiten, Kafka Events publizieren
    return {"status":"scheduled", "provider": req.provider, "prefix": req.prefix, "bucket": req.bucket}
