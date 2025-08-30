import boto3
import os
import csv
import json
from botocore.config import Config
from typing import Iterator, Dict, Any, Optional

_TILE_PATH = "/app/data/tiles/sentinel2_tiles_sample.csv"
_TILE = {}

if os.path.exists(_TILE_PATH):
    with open(_TILE_PATH, "r", encoding="utf-8") as f:
        # columns: mgrs, xmin, ymin, xmax, ymax (EPSG:4326)
        reader = csv.DictReader(f)
        for row in reader:
            _TILE[row["mgrs"].strip()] = [
                float(row["xmin"]),
                float(row["ymin"]),
                float(row["xmax"]),
                float(row["ymax"])
            ]

def s3_client(region: Optional[str] = None) -> boto3.client:
    return boto3.client(
        "s3",
        region_name=region or os.getenv("AWS_REGION", "us-east-1"),
        config=Config(signature_version="s3v4")
    )

def list_prefix(
    bucket: str,
    prefix: str,
    region: Optional[str] = None,
    requester_pays: bool = False
) -> Iterator[Dict[str, Any]]:
    client = s3_client(region)
    paginator = client.get_paginator("list_objects_v2")
    kwargs = {"Bucket": bucket, "Prefix": prefix}

    if requester_pays:
        kwargs["RequestPayer"] = "requester"

    for page in paginator.paginate(**kwargs):
        for obj in page.get("Contents", []):
            yield {
                "bucket": bucket,
                "key": obj["Key"],
                "size": obj.get("Size"),
                "etag": obj.get("ETag", "").replace('"', ''),
                "last_modified": (
                    obj.get("LastModified").isoformat()
                    if obj.get("LastModified")
                    else None
                )
            }

def _mgrs_from_key(key: str) -> Optional[str]:
    # Beispiel: sentinel-s2-l1c tiles/32/U/QC/2025/8/22/...  -> tile 32UQC
    parts = key.split("/")
    try:
        return parts[1] + parts[2] + parts[3]  # 'tiles','32','U','QC',...
    except (IndexError, AttributeError):
        return None

def to_stac_from_key(bucket: str, key: str) -> Dict[str, Any]:
    parts = key.split("/")
    datetime = None

    try:
        year = int(parts[-5])
        month = int(parts[-4])
        day = int(parts[-3])
        datetime = f"{year:04d}-{month:02d}-{day:02d}T00:00:00Z"
    except (ValueError, IndexError, TypeError):
        pass

    bbox = None
    mgrs = _mgrs_from_key(key)

    if mgrs and mgrs in _TILE:
        bbox = _TILE[mgrs]

    geometry = {
        "type": "Polygon",
        "coordinates": [
            [
                [bbox[0], bbox[1]],
                [bbox[2], bbox[1]],
                [bbox[2], bbox[3]],
                [bbox[0], bbox[3]],
                [bbox[0], bbox[1]]
            ]
        ]
    } if bbox else None

    return {
        "id": f"{bucket}:{key}",
        "collection": bucket,
        "geometry": geometry,
        "properties": {
            "datetime": datetime,
            "s3:key": key,
            "mgrs": mgrs
        },
        "assets": {}
    }
