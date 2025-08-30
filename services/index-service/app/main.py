
# import os
# from fastapi import FastAPI
# from pydantic import BaseModel
# from .tasks import index_prefix_task
# from .scheduler import setup_scheduler

# class IndexRequest(BaseModel):
#     bucket: str
#     prefix: str = ""
#     endpoint_url: str | None = None

# app = FastAPI(title="index-service", version="0.2.0")

# @app.on_event("startup")
# def _startup():
#     if os.getenv("ENABLE_SCHEDULER","true").lower() in ("1","true","yes"):
#         setup_scheduler()

# @app.get("/health")
# def health():
#     return {"status":"OK"}

# @app.post("/api/v1/index")
# def trigger_index(req: IndexRequest):
#     res = index_prefix_task.delay(req.bucket, req.prefix, req.endpoint_url)
#     return {"status":"queued","task_id":res.id}

from fastapi import FastAPI, HTTPException
#from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
#from opentelemetry.sdk.resources import Resource
#from opentelemetry.sdk.trace.export import BatchSpanProcessor
#from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from prometheus_client import make_asgi_app
import os
from .models import IndexRunRequest
from .db import init_schema
from .celery_app import run_stac_task, run_s3_task
from .scheduler import start_scheduler
from .tracing import init_tracing

# FastAPI App
app = FastAPI(
    title="index-service v2",
    version="2.0.0",
    description="STAC Indexing Service API",
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json"
)

# Prometheus Metrics Endpoint
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

# OpenTelemetry Tracer
#tracer = init_tracing(app)

# Initialisierung
init_schema()

from .celery_app import run_stac_task, run_s3_task
from .scheduler import start_scheduler

_scheduler = start_scheduler()


# Health Check Endpoint
@app.get("/health", summary="Health Check", response_model=dict)
async def health_check():
    with tracer.start_as_current_span("health_check"):
        return {"status": "healthy"}

# Index Run Endpoint
@app.post(
    "/index/run",
    summary="Trigger Indexing Task",
    response_model=dict,
    responses={
        200: {"description": "Task queued or completed"},
        400: {"description": "Invalid request"},
        500: {"description": "Internal server error"}
    }
)
async def run_index(req: IndexRunRequest):
    with tracer.start_as_current_span("run_index") as span:
        span.set_attribute("bucket", req.bucket)
        span.set_attribute("prefix", req.prefix)
        span.set_attribute("mode", req.mode)

        payload = req.model_dump(by_alias=True)

        try:
            if req.async_:
                if req.mode == "stac":
                    result = run_stac_task.delay(payload)
                elif req.mode == "s3":
                    result = run_s3_task.delay(payload)
                else:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Unsupported mode: {req.mode}"
                    )
                return {"status": "queued", "task_id": result.id}
            else:
                if req.mode == "stac":
                    result = run_stac_task.apply(args=(payload,)).get()
                elif req.mode == "s3":
                    result = run_s3_task.apply(args=(payload,)).get()
                else:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Unsupported mode: {req.mode}"
                    )
                return {"status": "completed", "result": result}
        except HTTPException:
            raise
        except Exception as e:
            span.record_exception(e)
            raise HTTPException(
                status_code=500,
                detail=f"Internal server error: {str(e)}"
            )

# Fehlerbehandlung für 404
@app.exception_handler(HTTPException)
async def http_exception_handler(request, exc):
    return JSONResponse(
        status_code=exc.status_code,
        content={"message": exc.detail},
    )

# Fehlerbehandlung für 500
@app.exception_handler(Exception)
async def generic_exception_handler(request, exc):
    return JSONResponse(
        status_code=500,
        content={"message": f"Internal server error: {str(exc)}"},
    )