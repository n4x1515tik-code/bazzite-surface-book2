# Bazzite for the Surface Book 2 13"
#
# Adds the IPTS touchscreen/pen driver (patched for Linux 7.x), iptsd, and a
# base-hub USB fix on top of the stock Bazzite KDE image.
#
# CI resolves BASE_IMAGE to a digest and reads KERNEL_VERSION from its
# ostree.linux label, so the module is always built for the exact kernel.

ARG BASE_IMAGE=ghcr.io/ublue-os/bazzite:stable
ARG KERNEL_VERSION=7.2.4-ogc3.1.fc44.x86_64
ARG KERNEL_FLAVOR=ogc
ARG FEDORA_VERSION=44

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files

# kernel-devel for the base image's kernel, published by Universal Blue
FROM ghcr.io/ublue-os/akmods:${KERNEL_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION} AS akmods

# Throwaway builder stage.
#
# The module-signing key is only ever mounted here, as a build secret: it is
# never written to a layer, and nothing from this stage reaches the final image
# except the files under /out that the final stage explicitly copies. The
# builder stage itself is never pushed.
FROM registry.fedoraproject.org/fedora:${FEDORA_VERSION} AS builder
ARG KERNEL_VERSION
COPY --from=akmods /kernel-rpms/kernel-devel-${KERNEL_VERSION}.rpm /tmp/rpms/
COPY ipts /src/ipts
COPY build_files/builder /builder
RUN /builder/build-iptsd.sh
RUN --mount=type=secret,id=mok_key,required=true \
    --mount=type=secret,id=mok_cert,required=true \
    KERNEL_VERSION=${KERNEL_VERSION} /builder/build-ipts.sh
RUN --mount=type=secret,id=mok_key,required=true \
    --mount=type=secret,id=mok_cert,required=true \
    KERNEL_VERSION=${KERNEL_VERSION} /builder/build-mei-me.sh

# Final image
FROM ${BASE_IMAGE}
ARG KERNEL_VERSION

COPY --from=builder /out/ /

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    KERNEL_VERSION=${KERNEL_VERSION} /ctx/build.sh

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
