
import os
from celery import Celery

broker_url = os.getenv("CELERY_BROKER_URL","redis://redis:6379/0")
app = Celery("fetch", broker=broker_url, backend=os.getenv("CELERY_BACKEND","redis://redis:6379/1"))

@app.task(bind=True, max_retries=3)
def clip_dataset(self, dataset_id: str, bbox: tuple | None = None, crs: str = "EPSG:4326"):
    # TODO: implement clipping, save to S3, return key
    return {"status":"done","result_key": f"proc:{dataset_id}"}
