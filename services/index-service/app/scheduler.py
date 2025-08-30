
# import os, yaml
# from apscheduler.schedulers.asyncio import AsyncIOScheduler
# from .tasks import index_prefix_task

# CONFIG_PATH = os.getenv("INDEX_CONFIG","/app/config/providers.yaml")

# def load_jobs():
#     try:
#         with open(CONFIG_PATH, "r") as fh:
#             return yaml.safe_load(fh) or {}
#     except FileNotFoundError:
#         return {}

# def setup_scheduler():
#     sched = AsyncIOScheduler()
#     jobs = load_jobs().get("jobs", [])
#     for j in jobs:
#         cron = j.get("cron","15 */6 * * *")
#         bucket = j["bucket"]; prefix = j.get("prefix",""); endpoint = j.get("endpoint_url")
#         sched.add_job(index_prefix_task.delay, "cron",
#                       args=[bucket, prefix, endpoint], id=f"idx:{bucket}:{prefix}", **cron_to_kwargs(cron))
#     sched.start()
#     return sched

# def cron_to_kwargs(expr: str):
#     m,h,dom,mon,dow = expr.split()
#     return dict(minute=m, hour=h, day=dom, month=mon, day_of_week=dow)

import os
import yaml
import logging
from apscheduler.schedulers.background import BackgroundScheduler  # type: ignore
from apscheduler.triggers.cron import CronTrigger  # type: ignore
from apscheduler.jobstores.redis import RedisJobStore  # type: ignore
from apscheduler.executors.pool import ThreadPoolExecutor, ProcessPoolExecutor  # type: ignore
from opentelemetry import trace
from .celery_app import run_stac_task, run_s3_task

logger = logging.getLogger(__name__)
tracer = trace.get_tracer(__name__)

def start_scheduler(config_path: str = "/app/config/config.yaml"):
    """Startet den Hintergrund-Scheduler mit Konfiguration aus YAML."""

    # Prüfe, ob Scheduler aktiviert ist
    if os.getenv("SCHEDULER_ENABLED", "true").lower() not in ("true", "1", "yes"):
        logger.info("Scheduler deaktiviert (SCHEDULER_ENABLED)")
        return None

    try:
        # Lade Konfiguration
        with open(config_path, "r") as f:
            cfg = yaml.safe_load(f) or {}

        schedules = cfg.get("schedules", [])
        stac_cfg = cfg.get("stac", {})
        s3_cfg = cfg.get("s3", {})

        # Konfiguriere Job-Store und Executors
        jobstores = {
            'default': RedisJobStore(
                jobs_key='apscheduler.jobs',
                run_times_key='apscheduler.run_times',
                host=os.getenv("REDIS_HOST", "redis"),
                port=int(os.getenv("REDIS_PORT", 6379)),
                db=os.getenv("REDIS_DB", 0)
            )
        }

        executors = {
            'default': ThreadPoolExecutor(10),
            'processpool': ProcessPoolExecutor(5)
        }

        # Initialisiere Scheduler
        sched = BackgroundScheduler(
            jobstores=jobstores,
            executors=executors,
            timezone=os.getenv("TZ", "UTC")
        )

        # Füge Jobs hinzu
        for job_cfg in schedules:
            with tracer.start_as_current_span("schedule_job") as span:
                span.set_attribute("job.config", str(job_cfg))

                try:
                    mode = job_cfg.get("mode")
                    cron = job_cfg.get("cron")
                    job_id = job_cfg.get("id", f"{mode}_{cron}")

                    if not cron:
                        logger.warning(f"Kein Cron-Ausdruck für Job: {job_cfg}")
                        continue

                    # Erstelle Payload mit Standardkonfiguration + Job-spezifischen Überschreibungen
                    base_cfg = stac_cfg if mode == "stac" else s3_cfg
                    payload = {**base_cfg, **job_cfg.get("payload", {})}

                    trigger = CronTrigger.from_crontab(cron)

                    if mode == "stac":
                        sched.add_job(
                            lambda p=payload: run_stac_task.delay(p),
                            trigger,
                            id=job_id,
                            name=f"STAC Indexing: {cron}",
                            replace_existing=True,
                            jobstore='default',
                            executor='default'
                        )
                    elif mode == "s3":
                        sched.add_job(
                            lambda p=payload: run_s3_task.delay(p),
                            trigger,
                            id=job_id,
                            name=f"S3 Indexing: {cron}",
                            replace_existing=True,
                            jobstore='default',
                            executor='default'
                        )
                    else:
                        logger.warning(f"Unbekannter Modus: {mode}")
                        continue

                    logger.info(f"Job hinzugefügt: {job_id} (Cron: {cron}, Modus: {mode})")

                except Exception as e:
                    logger.error(f"Fehler beim Hinzufügen von Job {job_cfg}: {str(e)}")
                    span.record_exception(e)

        # Starte Scheduler
        sched.start()
        logger.info("Scheduler erfolgreich gestartet")
        return sched

    except FileNotFoundError:
        logger.error(f"Konfigurationsdatei nicht gefunden: {config_path}")
        return None
    except yaml.YAMLError as e:
        logger.error(f"Fehler beim Parsen der YAML-Konfiguration: {str(e)}")
        return None
    except Exception as e:
        logger.error(f"Unbekannter Fehler beim Starten des Schedulers: {str(e)}")
        return None
