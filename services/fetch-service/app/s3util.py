import os
from pathlib import Path
from typing import Optional

import boto3
from botocore.config import Config

from .config import REQUEST_PAYER, S3_ENDPOINT_URL


def client(region: Optional[str] = None):
    """Create an S3 client with shared configuration."""
    return boto3.client(
        "s3",
        region_name=region or os.getenv("AWS_REGION", "us-east-1"),
        endpoint_url=S3_ENDPOINT_URL,
        config=Config(signature_version="s3v4"),
    )


def presign(bucket: str, key: str, expires: int = 1800, region: Optional[str] = None, requester_pays: bool = False) -> str:
    s3 = client(region)
    params = {"Bucket": bucket, "Key": key}
    payer = REQUEST_PAYER or ("requester" if requester_pays else None)
    if payer:
        params["RequestPayer"] = payer
    return s3.generate_presigned_url("get_object", Params=params, ExpiresIn=int(expires))


def copy_object(source_bucket: str, source_key: str, dest_bucket: str, dest_key: str, requester_pays: bool = False):
    extra_args = {}
    payer = REQUEST_PAYER or ("requester" if requester_pays else None)
    if payer:
        extra_args["RequestPayer"] = payer
    s3 = client()
    s3.copy({"Bucket": source_bucket, "Key": source_key}, dest_bucket, dest_key, ExtraArgs=extra_args or None)


def download_to_path(bucket: str, key: str, dest_path: Path, requester_pays: bool = False) -> None:
    s3 = client()
    extra_args = {}
    payer = REQUEST_PAYER or ("requester" if requester_pays else None)
    if payer:
        extra_args["RequestPayer"] = payer
    dest_path.parent.mkdir(parents=True, exist_ok=True)
    if extra_args:
        s3.download_file(bucket, key, str(dest_path), ExtraArgs=extra_args)
    else:
        s3.download_file(bucket, key, str(dest_path))


def upload_file(bucket: str, key: str, src_path: Path) -> None:
    s3 = client()
    s3.upload_file(str(src_path), bucket, key)
