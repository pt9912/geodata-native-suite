
import os, asyncio
from typing import AsyncGenerator, Dict, Optional
import aioboto3

REQUEST_PAYER = os.getenv("REQUEST_PAYER")

async def list_objects(bucket: str, prefix: str, endpoint_url: Optional[str] = None) -> AsyncGenerator[Dict, None]:
    session = aioboto3.Session()
    async with session.client("s3", endpoint_url=endpoint_url) as s3:
        paginator = s3.get_paginator("list_objects_v2")
        async for page in paginator.paginate(Bucket=bucket, Prefix=prefix, RequestPayer=REQUEST_PAYER):
            for obj in page.get("Contents", []):
                yield obj

def to_stac_item(bucket: str, key: str) -> Dict:
    return {
        "id": key.replace("/", "_"),
        "type": "Feature",
        "geometry": None,
        "properties": {"datetime": None, "provider": bucket},
        "assets": {"data": {"href": f"s3://{bucket}/{key}", "type": "application/octet-stream"}}
    }
