
#!/usr/bin/env python3
import argparse, json, time, random, string
from confluent_kafka import SerializingProducer
from confluent_kafka.serialization import StringSerializer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer

def rand_id(prefix="item"):
    s=''.join(random.choice(string.ascii_lowercase+string.digits) for _ in range(12))
    return f"{prefix}-{s}"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bootstrap", default="redpanda:9092")
    ap.add_argument("--schema-url", default="http://redpanda:8081")
    ap.add_argument("--topic", default="stac.item.indexed")
    ap.add_argument("--count", type=int, default=100)
    ap.add_argument("--schema-file", default="/schemas/StacItem.avsc")
    args = ap.parse_args()

    sr = SchemaRegistryClient({"url": args.schema_url})
    with open(args.schema_file,"r") as f:
        avro = f.read()
    serializer = AvroSerializer(sr, avro)
    producer = SerializingProducer({
        "bootstrap.servers": args.bootstrap,
        "key.serializer": StringSerializer("utf_8"),
        "value.serializer": serializer
    })

    for i in range(args.count):
        item = {
            "id": rand_id("fuzz"),
            "collection": "test-collection",
            "datetime": "2025-08-01T00:00:00Z",
            "geometry": None,
            "properties": json.dumps({"q": "fuzz", "i": i})
        }
        producer.produce(topic=args.topic, key=item["id"], value=item)
        if i % 100 == 0: producer.flush()
    producer.flush()

if __name__ == "__main__":
    main()
