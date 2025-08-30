
import os, asyncio
from typing import AsyncGenerator, Dict, Optional
import aioboto3
import hashlib
from typing import TypedDict, Optional, Dict, Literal
from datetime import datetime
import re

REQUEST_PAYER = os.getenv("REQUEST_PAYER")

async def list_objects(bucket: str, prefix: str, endpoint_url: Optional[str] = None) -> AsyncGenerator[Dict, None]:
    session = aioboto3.Session()
    try:
        async with session.client("s3", endpoint_url=endpoint_url) as s3:
            paginator = s3.get_paginator("list_objects_v2")
            async for page in paginator.paginate(Bucket=bucket, Prefix=prefix, RequestPayer=REQUEST_PAYER):
                if "Contents" in page:
                    for obj in page["Contents"]:
                        yield obj
    except Exception as e:
        print(f"Fehler beim Auflisten von Objekten: {e}")
        raise  # oder: yield {"error": str(e)}


class STACAsset(TypedDict):
    href: str
    type: str
    roles: list[str]  # Optional, z. B. ["data", "thumbnail"]

class STACItem(TypedDict):
    stac_version: Literal["1.0.0"]
    id: str
    type: Literal["Feature"]
    geometry: Optional[Dict]  # GeoJSON-Geometrie
    properties: Dict
    assets: Dict[str, STACAsset]
    links: list[Dict]  # Optional


def extract_datetime_from_key(key: str) -> Optional[datetime]:
    # Beispiel: Extrahiere Datum aus dem Dateinamen (z. B. "2023-01-01_sentinel2.tif")
    match = re.search(r"(\d{4}-\d{2}-\d{2})", key)
    if match:
        return datetime.strptime(match.group(1), "%Y-%m-%d")
    return None

def to_stac_item(bucket: str, key: str) -> Dict:
    item_id = hashlib.md5(key.encode()).hexdigest()
    return {
        "id": item_id,
        "type": "Feature",
        "geometry": None,
        "properties": {
            "datetime": None,
            "provider": bucket,
            "original_key": key,  # Optional: Originalen Key speichern
        },
        "assets": {
            "data": {
                "href": f"s3://{bucket}/{key}",
                "type": "application/octet-stream"
            }
        },
    }
