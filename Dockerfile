ARG FUNCTION_DIR="/home/app/"
ARG RUNTIME_VERSION="3.9"
ARG DISTRO_VERSION="3.16"

FROM python:${RUNTIME_VERSION}-alpine${DISTRO_VERSION} AS python-alpine
RUN apk add --no-cache \
    curl               \
    libcurl            \
    libstdc++          \
    postgresql13

FROM python-alpine AS build-image
RUN apk add --no-cache \
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

COPY app.py ${FUNCTION_DIR}

RUN python3 -m pip install --no-cache-dir awslambdaric==2.0.8 --target ${FUNCTION_DIR}

FROM python-alpine
ARG FUNCTION_DIR
WORKDIR ${FUNCTION_DIR}
COPY --from=build-image ${FUNCTION_DIR} ${FUNCTION_DIR}
ADD https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie /usr/bin/aws-lambda-rie
RUN chmod 755 /usr/bin/aws-lambda-rie

ENV ENVIRONMENT ''
ENV S3_BUCKET ''
ENV S3_S3V4 no

RUN python3 -m pip install --no-cache-dir awscli==1.29.85

COPY entry.sh ${FUNCTION_DIR}
RUN chmod 755 ${FUNCTION_DIR}/entry.sh

COPY backup.sh ${FUNCTION_DIR}
RUN chmod 755 ${FUNCTION_DIR}/backup.sh

ENTRYPOINT [ "/home/app/entry.sh" ]
CMD [ "app.handler" ]
