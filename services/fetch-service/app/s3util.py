
import boto3, os
from botocore.config import Config
from .config import REQUEST_PAYER, S3_ENDPOINT_URL

def client():
    #return boto3.client("s3", endpoint_url=S3_ENDPOINT_URL)
    c = boto3.client("s3", 
                     region_name=region or os.getenv("AWS_REGION","us-east-1"),
                     config=Config(signature_version="s3v4")
                     )
    return c

def presign(bucket: str, key: str, expires: int = 3600) -> str:
    s3 = client()
    params = {"Bucket": bucket, "Key": key}
    if REQUEST_PAYER:
        params["RequestPayer"] = REQUEST_PAYER
    return s3.generate_presigned_url("get_object", Params=params, ExpiresIn=expires)


def presign(bucket, key, expires=1800, region=None, requester_pays=False):
    c = boto3.client("s3", region_name=region or os.getenv("AWS_REGION","us-east-1"),
                     config=Config(signature_version="s3v4"))
    params = {"Bucket": bucket, "Key": key}
    if requester_pays: 
        params["RequestPayer"]="requester"
    return c.generate_presigned_url("get_object", Params=params, ExpiresIn=int(expires))
