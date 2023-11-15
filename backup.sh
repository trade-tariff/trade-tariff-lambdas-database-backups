#!/bin/sh

set -eo

if [ -z "${ENVIRONMENT}" ]; then
  echo "You need to set the ENVIRONMENT environment variable."
  exit 1
fi

if [ -z "${S3_BUCKET}" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ -z "${POSTGRES_DATABASE}" ]; then
  echo "You need to set the POSTGRES_DATABASE environment variable."
  exit 1
fi

if [ -z "${POSTGRES_HOST}" ]; then
  echo "You need to set the POSTGRES_HOST environment variable."
  exit 1
fi

if [ -z "${POSTGRES_USER}" ]; then
  echo "You need to set the POSTGRES_USER environment variable."
  exit 1
fi

if [ -z "${POSTGRES_PASSWORD}" ]; then
  echo "You need to set the POSTGRES_PASSWORD environment variable or link to a container named POSTGRES."
  exit 1
fi

# env vars needed for pgdump
export PGPASSWORD="$POSTGRES_PASSWORD"

pg_dump -h "$POSTGRES_HOST" \
  -U "$POSTGRES_USER"       \
   "$POSTGRES_DATABASE"     \
  --no-acl                  \
  --no-owner                \
  --clean                   \
  --verbose |
  gzip |
  aws s3 cp - "s3://$S3_BUCKET/tariff-merged-${ENVIRONMENT}.sql.gz" || exit 2

echo "SQL backup uploaded successfully" && exit 0
