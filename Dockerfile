# Stage 1: Builder — install dependencies
FROM python:3.12-slim AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml .
COPY src/ src/

RUN pip install --no-cache-dir --prefix=/install ".[web]"

# Stage 2: Runtime — slim image with installed packages
FROM python:3.12-slim

COPY --from=builder /install /usr/local

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ARG UID=1000
ARG GID=100
RUN useradd -u ${UID} -g ${GID} -s /bin/sh -d /var/lib/baker baker \
    && mkdir -p /var/lib/baker \
    && chown ${UID}:${GID} /var/lib/baker

ENV BAKER_DATA_DIR=/var/lib/baker
ENV BAKER_HOST=0.0.0.0
ENV BAKER_PORT=2108

USER baker
WORKDIR /var/lib/baker

EXPOSE 2108

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
