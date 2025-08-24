
import os, yaml
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from .tasks import index_prefix_task

CONFIG_PATH = os.getenv("INDEX_CONFIG","/app/config/providers.yaml")

def load_jobs():
    try:
        with open(CONFIG_PATH, "r") as fh:
            return yaml.safe_load(fh) or {}
    except FileNotFoundError:
        return {}

def setup_scheduler():
    sched = AsyncIOScheduler()
    jobs = load_jobs().get("jobs", [])
    for j in jobs:
        cron = j.get("cron","15 */6 * * *")
        bucket = j["bucket"]; prefix = j.get("prefix",""); endpoint = j.get("endpoint_url")
        sched.add_job(index_prefix_task.delay, "cron",
                      args=[bucket, prefix, endpoint], id=f"idx:{bucket}:{prefix}", **cron_to_kwargs(cron))
    sched.start()
    return sched

def cron_to_kwargs(expr: str):
    m,h,dom,mon,dow = expr.split()
    return dict(minute=m, hour=h, day=dom, month=mon, day_of_week=dow)
