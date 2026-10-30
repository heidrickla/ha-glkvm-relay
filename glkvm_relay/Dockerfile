# rttys is built from GL.iNet's glkvm-cloud source at the commit of its v2.8.0 release, fetched by
# commit and checked. The source, UI and Go stages run on the build machine's own platform and Go
# cross-compiles for the target, so an aarch64 image builds at native speed on an x86 host.
ARG GLKVM_COMMIT=be821d46f674bbba20267d2fe8160fcbe4ad97a6

FROM --platform=$BUILDPLATFORM golang:1.24.13-alpine3.23@sha256:8bee1901f1e530bfb4a7850aa7a479d17ae3a18beb6e09064ed54cfd245b7191 AS source
ARG GLKVM_COMMIT
# hadolint ignore=DL3018
RUN apk add --no-cache git \
 && git init -q /src \
 && git -C /src fetch -q --depth 1 https://github.com/gl-inet/glkvm-cloud.git "${GLKVM_COMMIT}" \
 && git -C /src checkout -q FETCH_HEAD \
 && test "$(git -C /src rev-parse HEAD)" = "${GLKVM_COMMIT}" \
 && rm -rf /src/.git

# The web console, embedded into rttys. Every package in yarn.lock carries its sha512, which yarn
# checks; the lock names a mirror of the npm registry, read here from the registry itself.
FROM --platform=$BUILDPLATFORM node:24.22.2-alpine3.24@sha256:8a32c8cf649a49915a66e81e7a609223c708d0adabf288ee3f4077d765542f85 AS ui
WORKDIR /src/ui
COPY --from=source /src/ui ./
RUN sed -i 's#https://registry.npmmirror.com/#https://registry.npmjs.org/#' yarn.lock \
 && yarn install --frozen-lockfile --ignore-scripts --non-interactive --network-timeout 600000 \
 && yarn build \
 && test -s dist/index.html

# Pure Go (CGO off, SQLite through modernc), as upstream's Makefile builds it; go.sum checks every module.
FROM --platform=$BUILDPLATFORM golang:1.24.13-alpine3.23@sha256:8bee1901f1e530bfb4a7850aa7a479d17ae3a18beb6e09064ed54cfd245b7191 AS rttys
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY --from=source /src ./
COPY --from=ui /src/ui/dist ./ui/dist
RUN GOTOOLCHAIN=local CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
      go build -mod=readonly -trimpath -ldflags "-s -w" -o /rttys ./cmd/glkvm-cloud

# Home Assistant's multi-architecture base image, pinned to its Alpine release.
FROM ghcr.io/home-assistant/base:3.24

# The checksum check below pipes into sha256sum; failures must propagate.
SHELL ["/bin/ash", "-o", "pipefail", "-c"]

ARG BUILD_ARCH=amd64
ARG GLKVM_COMMIT
ARG SCHEMA_SHA256=37aa75cff56ba7e03cdc89daf0824a4614c09388cac92ce66c1f04f6df16dcbd

# rttys reads its schema from the database directory; upstream mounts it from its compose folder.
# hadolint ignore=DL3018
RUN apk add --no-cache bash coturn curl iproute2 jq openssl sqlite \
 && mkdir -p /usr/share/glkvm \
 && curl -fsSL -o /usr/share/glkvm/schema.sql \
      "https://raw.githubusercontent.com/gl-inet/glkvm-cloud/${GLKVM_COMMIT}/docker-compose/database/schema.sql" \
 && echo "${SCHEMA_SHA256}  /usr/share/glkvm/schema.sql" | sha256sum -c -

COPY --from=rttys /rttys /usr/bin/rttys
COPY run.sh /run.sh
RUN chmod +x /run.sh /usr/bin/rttys

CMD ["/run.sh"]

ARG BUILD_DATE
ARG BUILD_REF
ARG BUILD_VERSION
LABEL \
    io.hass.name="GLKVM Relay" \
    io.hass.description="Self-hosted GLKVM Cloud relay (rttys) and its TURN server for GL.iNet KVMs" \
    io.hass.url="https://github.com/heidrickla/ha-glkvm-relay" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="app" \
    io.hass.version="${BUILD_VERSION}" \
    maintainer="Lewis Heidrick" \
    org.opencontainers.image.title="GLKVM Relay" \
    org.opencontainers.image.description="Self-hosted GLKVM Cloud relay (rttys) and its TURN server for GL.iNet KVMs" \
    org.opencontainers.image.source="https://github.com/heidrickla/ha-glkvm-relay" \
    org.opencontainers.image.vendor="Lewis Heidrick" \
    org.opencontainers.image.authors="Lewis Heidrick" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${BUILD_REF}" \
    org.opencontainers.image.version="${BUILD_VERSION}"
