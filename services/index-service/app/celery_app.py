
import os
from celery import Celery

broker_url = os.getenv("REDIS_URL", "redis://redis:6379/0")
backend_url = os.getenv("REDIS_BACKEND_URL", "redis://redis:6379/1")
celery = Celery("index", broker=broker_url, backend=backend_url)
