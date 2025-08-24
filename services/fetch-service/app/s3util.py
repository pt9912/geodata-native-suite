
import boto3, os
from .config import REQUEST_PAYER, S3_ENDPOINT_URL

def client():
    return boto3.client("s3", endpoint_url=S3_ENDPOINT_URL)

def presign(bucket: str, key: str, expires: int = 3600) -> str:
    s3 = client()
    params = {"Bucket": bucket, "Key": key}
    if REQUEST_PAYER:
        params["RequestPayer"] = REQUEST_PAYER
    return s3.generate_presigned_url("get_object", Params=params, ExpiresIn=expires)
