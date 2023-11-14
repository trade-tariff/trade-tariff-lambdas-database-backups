ARG FUNCTION_DIR="/home/app/"
ARG RUNTIME_VERSION="3.9"
ARG DISTRO_VERSION="3.12"

FROM python:${RUNTIME_VERSION}-alpine${DISTRO_VERSION} AS python-alpine
RUN apk add --no-cache \
    libstdc++

FROM python-alpine AS build-image
RUN apk add --no-cache \
    build-base         \
    libtool            \
    autoconf           \
    automake           \
    libexecinfo-dev    \
    make               \
    cmake              \
    libcurl

ARG FUNCTION_DIR
ARG RUNTIME_VERSION
RUN mkdir -p ${FUNCTION_DIR}

COPY app.py ${FUNCTION_DIR}

RUN python3 -m pip install --no-cache-dir awslambdaric==2.0.8 --target ${FUNCTION_DIR}

FROM python-alpine
ARG FUNCTION_DIR
WORKDIR ${FUNCTION_DIR}
COPY --from=build-image ${FUNCTION_DIR} ${FUNCTION_DIR}
ADD https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie /usr/bin/aws-lambda-rie
RUN chmod 755 /usr/bin/aws-lambda-rie

ENV POSTGRES_DATABASE ''
ENV POSTGRES_HOST ''
ENV POSTGRES_PORT 5432
ENV POSTGRES_USER ''
ENV POSTGRES_PASSWORD ''
ENV POSTGRES_EXTRA_OPTS ''
ENV S3_BUCKET ''
ENV S3_PATH 'auto-backups'
ENV S3_S3V4 no

RUN apk add --no-cache postgresql && python3 -m pip install --no-cache-dir awscli==1.29.85

COPY entry.sh ${FUNCTION_DIR}
RUN chmod 755 ${FUNCTION_DIR}/entry.sh

COPY backup.sh ${FUNCTION_DIR}
RUN chmod 755 ${FUNCTION_DIR}/backup.sh

ENTRYPOINT [ "/home/app/entry.sh" ]
CMD [ "app.handler" ]
