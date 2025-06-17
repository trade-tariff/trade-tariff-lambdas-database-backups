#!/usr/bin/env bash

STARTED=$(date +"%Y-%m-%d %H:%M:%S")

set -eo

if [ -z "${ENVIRONMENT}" ]; then
  echo "You need to set the ENVIRONMENT environment variable."
  exit 1
fi

if [ -z "${S3_BUCKET}" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ -z "${DATABASE_SECRET}" ]; then
  echo "You need to set the DATABASE_SECRET environment variable."
  exit 1
fi

DATABASE_URL=$(aws secretsmanager get-secret-value \
  --secret-id "$DATABASE_SECRET" \
  --query SecretString \
  --output text
)

latest="s3://$S3_BUCKET/tariff-merged-${ENVIRONMENT}.sql.gz" 
today="s3://$S3_BUCKET/$(date +"%Y/%m/%d")/tariff-merged-${ENVIRONMENT}.sql.gz" 

pg_dump "$DATABASE_URL" \
  --no-acl            \
  --no-owner          \
  --clean             \
  --verbose |
  gzip |
  aws s3 cp - "$latest" || exit 2

aws s3 cp "$latest" "$today" || exit 3

ENDED=$(date +"%Y-%m-%d %H:%M:%S")
SECONDS=$(( $(date -d "$ENDED" +%s) - $(date -d "$STARTED" +%s) ))

echo "SQL backup uploaded successfully. Time: ${SECONDS}s" && exit 0
