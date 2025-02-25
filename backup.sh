#!/bin/sh

SECONDS=0

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
  --secret-id $DATABASE_SECRET \
  --query SecretString \
  --output text
)

pg_dump $DATABASE_URL \
  --no-acl            \
  --no-owner          \
  --clean             \
  --verbose |
  gzip |
  aws s3 cp - "s3://$S3_BUCKET/tariff-merged-${ENVIRONMENT}.sql.gz" || exit 2

echo "SQL backup uploaded successfully. Time: ${SECONDS}s" && exit 0
