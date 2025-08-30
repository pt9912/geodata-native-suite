
#!/usr/bin/env python3
import argparse, os, sys, pathlib, boto3
from botocore.config import Config

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--access-key", required=True)
    ap.add_argument("--secret-key", required=True)
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--prefix", default="")
    ap.add_argument("--path", required=True, help="local file or directory")
    args = ap.parse_args()

    s3 = boto3.client("s3",
        endpoint_url=args.endpoint,
        aws_access_key_id=args.access_key,
        aws_secret_access_key=args.secret_key,
        config=Config(signature_version="s3v4"),
    )

    p = pathlib.Path(args.path)
    files = [p] if p.is_file() else [x for x in p.rglob("*") if x.is_file()]
    for f in files:
        key = f"{args.prefix.strip('/')}/{f.name}" if args.prefix else f.name
        s3.upload_file(str(f), args.bucket, key)
        print(f"uploaded s3://{args.bucket}/{key}", file=sys.stderr)

if __name__ == "__main__":
    main()
