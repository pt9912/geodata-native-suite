
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
import os

app = FastAPI(title="fetch-service", version="0.1.0")

class FetchJob(BaseModel):
    dataset_id: str
    bbox: Optional[list[float]] = None
    crs: Optional[str] = "EPSG:4326"
    format: Optional[str] = "COG"

@app.get("/health")
def health():
    return {"status":"OK"}

@app.post("/api/v1/fetch")
def fetch(job: FetchJob):
    # TODO: Enqueue Celery Job; presigned URL oder X-Accel-Redirect
    return {"status":"accepted", "job": job.model_dump()}
