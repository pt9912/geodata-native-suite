#!/bin/bash

#S3_ACCESS="key"
#S3_SECRET="secret"
S3_HOST="nbg1.your-objectstorage.com"
AWS_ACCESS_KEY_ID="$S3_ACCESS"
AWS_SECRET_ACCESS_KEY="$S3_SECRET"
AWS_DEFAULT_REGION="us-east-1"

BUCKET="v1000-geo-terrain"
ENDPOINT="https://nbg1.your-objectstorage.com"

# Alle Objekte löschen
aws s3 --endpoint-url=$ENDPOINT rm "s3://$BUCKET" --recursive

# Bucket löschen
aws s3 --endpoint-url=$ENDPOINT rb "s3://$BUCKET" --force
