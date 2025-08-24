
import json, os
from typing import Dict

KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS")

def publish(topic: str, payload: Dict):
    if not KAFKA_BOOTSTRAP:
        print(f"[events] (dry-run) {topic}: {json.dumps(payload)[:400]}")
        return
    try:
        from confluent_kafka import Producer
        p = Producer({"bootstrap.servers": KAFKA_BOOTSTRAP})
        p.produce(topic, json.dumps(payload).encode("utf-8"))
        p.flush()
    except Exception as e:
        print(f"[events] error publishing to {topic}: {e}")
