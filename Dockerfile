ARG FUNCTION_DIR="/home/app/"
ARG RUNTIME_VERSION="3.12"
ARG DISTRO_VERSION="3.22"

FROM python:${RUNTIME_VERSION}-alpine${DISTRO_VERSION} AS python-alpine
RUN apk add --no-cache \
    bash               \
    libstdc++          \
    postgresql17-client

FROM python-alpine AS build-image
RUN apk add --no-cache \
    bash               \
    autoconf           \
    automake           \
    build-base         \
    cmake              \
    curl               \
    libcurl            \
    libtool            \
    make &&            \
    apk add --no-cache --repository=https://dl-cdn.alpinelinux.org/alpine/v3.16/main/ libexecinfo-dev

ARG FUNCTION_DIR
ARG RUNTIME_VERSION
RUN mkdir -p ${FUNCTION_DIR}
COPY . ${FUNCTION_DIR}
RUN python3 -m pip install --no-cache-dir awslambdaric==3.1.1 --target ${FUNCTION_DIR}

FROM python-alpine
ARG FUNCTION_DIR
WORKDIR ${FUNCTION_DIR}
COPY --from=build-image ${FUNCTION_DIR} ${FUNCTION_DIR}

ADD https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/download/v1.26/aws-lambda-rie /usr/bin/aws-lambda-rie
RUN chmod 755 /usr/bin/aws-lambda-rie

ENV ENVIRONMENT=''
ENV S3_BUCKET=''
ENV S3_S3V4=no

RUN python3 -m pip install --no-cache-dir awscli==1.41.6

# Create non-root user for better security
RUN addgroup -g 1000 tariff && \
    adduser -D -u 1000 -G tariff tariff && \
    chown -R tariff:tariff ${FUNCTION_DIR}

USER tariff

ENTRYPOINT [ "/home/app/entry.sh" ]
CMD [ "app.handler" ]
