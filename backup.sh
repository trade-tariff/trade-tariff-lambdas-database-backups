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

# NOTE: This streams line-by-line without spiking memory usage or using a file.
#       Try not to break this model as it works best within the bounds of a lambda function
{
  pg_dump "$DATABASE_URL" \
    --no-acl            \
    --no-owner          \
    --clean             \
    --verbose | \
    sed '/^REFRESH MATERIALIZED VIEW/d'
  cat after.sql
} |
  gzip |
  aws s3 cp - "$latest" || exit 2

aws s3 cp "$latest" "$today" || exit 3

ENDED=$(date +"%Y-%m-%d %H:%M:%S")
SECONDS=$(( $(date -d "$ENDED" +%s) - $(date -d "$STARTED" +%s) ))

echo "SQL backup uploaded successfully. Time: ${SECONDS}s" && exit 0
