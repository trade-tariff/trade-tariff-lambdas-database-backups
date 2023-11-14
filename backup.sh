#!/bin/sh

set -eo

if [ -z "${S3_BUCKET}" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ -z "${POSTGRES_DATABASE}" ]; then
  echo "You need to set the POSTGRES_DATABASE environment variable."
  exit 1
fi

if [ -z "${POSTGRES_HOST}" ]; then
  if [ -n "${POSTGRES_PORT_5432_TCP_ADDR}" ]; then
    POSTGRES_HOST=$POSTGRES_PORT_5432_TCP_ADDR
    POSTGRES_PORT=$POSTGRES_PORT_5432_TCP_PORT
  else
    echo "You need to set the POSTGRES_HOST environment variable."
    exit 1
  fi
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
POSTGRES_HOST_OPTS="-h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER $POSTGRES_EXTRA_OPTS"

pg_dump "$POSTGRES_HOST_OPTS" "$POSTGRES_DATABASE" |
  gzip |
  aws s3 cp - "s3://$S3_BUCKET/$S3_PREFIX/${POSTGRES_DATABASE}_$(date +%Y-%m-%dT%H:%M:%SZ).sql.gz" || exit 2

echo "SQL backup uploaded successfully" && exit 0
