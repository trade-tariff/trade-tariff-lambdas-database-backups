ARG FUNCTION_DIR="/home/app/"
ARG RUNTIME_VERSION="3.12"
ARG DISTRO_VERSION="3.21"

FROM python:${RUNTIME_VERSION}-alpine${DISTRO_VERSION} AS python-alpine
RUN apk add --no-cache \
    bash               \
    curl               \
    libcurl            \
    libstdc++          \
    postgresql16-client

FROM python-alpine AS build-image
RUN apk add --no-cache \
    bash               \
    autoconf           \
    automake           \
    build-base         \
    cmake              \
    libcurl            \
    libexecinfo-dev    \
    libtool            \
    make

ARG FUNCTION_DIR
ARG RUNTIME_VERSION
RUN mkdir -p ${FUNCTION_DIR}
COPY . ${FUNCTION_DIR}
RUN python3 -m pip install --no-cache-dir awslambdaric==2.2.1 --target ${FUNCTION_DIR}

FROM python-alpine
ARG FUNCTION_DIR
WORKDIR ${FUNCTION_DIR}
COPY --from=build-image ${FUNCTION_DIR} ${FUNCTION_DIR}

# Use a specific version of RIE for better security and reproducibility
ADD https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/download/v1.20/aws-lambda-rie /usr/bin/aws-lambda-rie
RUN chmod 755 /usr/bin/aws-lambda-rie

ENV ENVIRONMENT=''
ENV S3_BUCKET=''
ENV S3_S3V4=no

# Use AWS CLI v2 which is more actively maintained
RUN python3 -m pip install --no-cache-dir awscli==1.34.34

# Create non-root user for better security
RUN addgroup -g 1000 tariff && \
    adduser -D -u 1000 -G tariff tariff && \
    chown -R tariff:tariff ${FUNCTION_DIR}

USER tariff

ENTRYPOINT [ "/home/app/entry.sh" ]
CMD [ "app.handler" ]
