# syntax=docker/dockerfile:1

# Build with docker-bake.hcl, which selects linux/amd64 (the only platform oc is published for).

ARG UBUNTU_IMAGE=ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c
ARG ALPINE_IMAGE=alpine:3@sha256:3f4d6b32e26703c6082839234f43769d5046b3ac7c910033911d1e71d8cd630a
ARG GOLANG_IMAGE=golang:1.27.3@sha256:e519d3b0a5b285e5aa53ab9eef02bc6bbb9cb04608389b743a136a9ce75f0d1e
# Comma-separated tools.lock names or apt packages to leave out.
ARG TOOLBOX_EXCLUDE=""
ARG TOOLBOX_VERSION=dev

# Only downloads, verifies and unpacks, so it runs natively even when the target is emulated.
FROM --platform=$BUILDPLATFORM ${ALPINE_IMAGE} AS fetch
ARG TOOLBOX_EXCLUDE
RUN apk add --no-cache bash coreutils curl findutils tar unzip xz
COPY build/fetch-tools.sh build/tools.lock /build/
RUN --mount=type=cache,id=toolbox-downloads,target=/cache,sharing=shared \
    /build/fetch-tools.sh /build/tools.lock /cache /out

# Also native: Go cross-compiles, so these builds are not slowed down by emulation.
FROM --platform=$BUILDPLATFORM ${GOLANG_IMAGE} AS gotools
ARG TOOLBOX_EXCLUDE
RUN --mount=type=bind,source=build,target=/build \
    --mount=type=cache,id=toolbox-go-mod,target=/go/pkg/mod,sharing=shared \
    --mount=type=cache,id=toolbox-go-build,target=/root/.cache/go-build,sharing=shared \
    /build/build-go-tools.sh /build/go-tools.lock /out

FROM ${UBUNTU_IMAGE} AS rsync
ARG TOOLBOX_EXCLUDE
COPY --from=fetch /out/rsync-src/ /src/
RUN --mount=type=bind,source=build,target=/build \
    /build/build-rsync.sh /src /out

FROM ${UBUNTU_IMAGE} AS system
ARG TOOLBOX_EXCLUDE
RUN --mount=type=bind,source=build,target=/build \
    --mount=type=cache,id=toolbox-apt-archives,target=/var/cache/apt/archives,sharing=locked \
    --mount=type=cache,id=toolbox-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    /build/install-apt.sh

FROM ${UBUNTU_IMAGE} AS python
COPY --from=fetch /out/bin/uv /usr/local/bin/uv
RUN --mount=type=bind,source=build,target=/build \
    --mount=type=cache,id=toolbox-uv,target=/root/.cache/uv,sharing=locked \
    /build/install-python.sh

FROM system AS toolbox
ARG TOOLBOX_EXCLUDE
ARG TOOLBOX_VERSION
LABEL org.opencontainers.image.title="toolbox" \
      org.opencontainers.image.description="Project-independent Ubuntu base image with Python, Node, Kubernetes, database and network tools and a browser terminal" \
      org.opencontainers.image.source="https://github.com/ozncv2/toolbox" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${TOOLBOX_VERSION}"

ENV PATH=/opt/toolbox/bin:/opt/python/current/bin:/opt/node/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    EDITOR=nano \
    PAGER=less \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_PYTHON_DOWNLOADS=never \
    UV_NATIVE_TLS=true \
    UV_LINK_MODE=copy \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    TOOLBOX_VERSION=${TOOLBOX_VERSION}

# --link keeps these layers independent, so changing one tool does not rebuild the others.
COPY --link --from=python /opt/python/ /opt/python/
COPY --link --from=python /opt/toolbox/venv/ /opt/toolbox/venv/
COPY --link --from=fetch /out/node/ /opt/node/
COPY --link --from=fetch /out/bin/ /usr/local/bin/
COPY --link --from=gotools /out/bin/ /usr/local/bin/
COPY --link --from=rsync /out/ /usr/local/bin/
COPY --link --from=fetch /out/web/ /opt/toolbox/terminal/static/vendor/
COPY --link --from=fetch /out/licenses/ /opt/toolbox/share/licenses/
COPY --link --from=gotools /out/licenses/ /opt/toolbox/share/licenses/
COPY --link rootfs/ /
COPY --link THIRD_PARTY_NOTICES.md /opt/toolbox/share/THIRD_PARTY_NOTICES.md

RUN --mount=type=bind,source=build,target=/build /build/finalize.sh

WORKDIR /workspace
USER 1001:0
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/opt/toolbox/bin/entrypoint"]
CMD ["/bin/bash"]
