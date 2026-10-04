ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base:3.24

# rttys from GL.iNet's published image, pinned by digest (v2.8.0, upstream commit be821d4).
FROM glzhitong/glkvm-cloud:v2.8.0@sha256:6cf8dc8cd3d071324c1523037133949c8a966e640b2c36dad4326a48f1e65333 AS glkvm

# Tag is in the ARG default and build.yaml; the Supervisor overrides BUILD_FROM per architecture.
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

# The checksum check below pipes into sha256sum; failures must propagate.
SHELL ["/bin/ash", "-o", "pipefail", "-c"]

ARG BUILD_ARCH=amd64
ARG GLKVM_COMMIT=be821d46f674bbba20267d2fe8160fcbe4ad97a6
ARG SCHEMA_SHA256=37aa75cff56ba7e03cdc89daf0824a4614c09388cac92ce66c1f04f6df16dcbd

# rttys reads its schema from the database directory; upstream mounts it from its compose folder.
# hadolint ignore=DL3018
RUN apk add --no-cache bash coturn curl iproute2 jq openssl \
 && mkdir -p /usr/share/glkvm \
 && curl -fsSL -o /usr/share/glkvm/schema.sql \
      "https://raw.githubusercontent.com/gl-inet/glkvm-cloud/${GLKVM_COMMIT}/docker-compose/database/schema.sql" \
 && echo "${SCHEMA_SHA256}  /usr/share/glkvm/schema.sql" | sha256sum -c -

COPY --from=glkvm /usr/bin/rttys /usr/bin/rttys
COPY run.sh /run.sh
RUN chmod +x /run.sh /usr/bin/rttys

CMD ["/run.sh"]

ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION
LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version="${BUILD_VERSION}" \
    maintainer="Lewis Heidrick" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="Lewis Heidrick" \
    org.opencontainers.image.authors="Lewis Heidrick" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${BUILD_REF}" \
    org.opencontainers.image.version="${BUILD_VERSION}"
