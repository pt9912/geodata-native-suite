
# import json, os
# from typing import Dict

# KAFKA_BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP_SERVERS")

# def publish(topic: str, payload: Dict):
#     if not KAFKA_BOOTSTRAP:
#         print(f"[events] (dry-run) {topic}: {json.dumps(payload)[:400]}")
#         return
#     try:
#         from confluent_kafka import Producer
#         p = Producer({"bootstrap.servers": KAFKA_BOOTSTRAP})
#         p.produce(topic, json.dumps(payload).encode("utf-8"))
#         p.flush()
#     except Exception as e:
#         print(f"[events] error publishing to {topic}: {e}")

import os
import json
from typing import Dict, Any
from confluent_kafka import SerializingProducer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import StringSerializer

BOOTSTRAP = os.getenv("KAFKA_BOOTSTRAP", "redpanda:9092")
SR_URL = os.getenv("SCHEMA_REGISTRY_URL", "http://redpanda:8081")

_sr = SchemaRegistryClient({"url": SR_URL})
_schema_path = os.getenv("STAC_AVRO_SCHEMA", "/app/schemas/avro/StacItem.avsc")

with open(_schema_path, "r", encoding="utf-8") as f:
    _avro = f.read()

_avro_ser = AvroSerializer(_sr, _avro)
_prod = SerializingProducer({
    "bootstrap.servers": BOOTSTRAP,
    "key.serializer": StringSerializer("utf_8"),
    "value.serializer": _avro_ser
})

def publish_item(event_type: str, item: Dict[str, Any]) -> None:
    topic = {
        "indexed": "stac.item.indexed",
        "updated": "stac.item.updated",
        "deleted": "stac.item.deleted"
    }.get(event_type, "stac.item.indexed")
    _prod.produce(topic=topic, key=item.get("id", ""), value=item)
    _prod.poll(0)

def publish_dlq(kind: str, payload: Dict[str, Any], error: str) -> None:
    msg = {
        "kind": kind,
        "payload": payload,
        "error": error
    }
    _prod.produce(
        topic="index.dlq",
        key=payload.get("bucket", payload.get("endpoint", "")),
        value=json.dumps(msg)
    )
    _prod.poll(0)
