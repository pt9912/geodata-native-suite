
import os, yaml

MODE = os.getenv("FETCH_MODE","presigned")
REQUEST_PAYER = os.getenv("REQUEST_PAYER")
ALLOWED_BUCKETS_FILE = os.getenv("ALLOWED_BUCKETS_FILE","/app/config/allowed-buckets.yaml")
S3_ENDPOINT_URL = os.getenv("S3_ENDPOINT_URL")

def load_allowed():
    try:
        with open(ALLOWED_BUCKETS_FILE,"r") as fh:
            y = yaml.safe_load(fh) or {}
            return set(y.get("buckets",[]))
    except FileNotFoundError:
        return set()
ALLOWED_BUCKETS = load_allowed()
