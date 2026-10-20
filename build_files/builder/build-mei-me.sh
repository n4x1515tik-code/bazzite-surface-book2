#!/bin/bash
# Build and sign mei-me.ko for $KERNEL_VERSION with the Ice Lake iTouch PCI ID
# (8086:34e4) added. Mainline mei_me has no entry for it, so on Surface Book 3 /
# Pro 7 / Laptop 3 the IPTS MEI client never appears. Installed under updates/
# so depmod prefers it over the stock module.

set -euo pipefail

: "${KERNEL_VERSION:?KERNEL_VERSION must be set}"

KEY=/run/secrets/mok_key
CERT=/run/secrets/mok_cert
test -s "$KEY"  || { echo "mok_key secret missing" >&2; exit 1; }
test -s "$CERT" || { echo "mok_cert secret missing" >&2; exit 1; }

dnf5 install -y gcc make kmod openssl elfutils-libelf-devel curl tar xz /tmp/rpms/kernel-devel-*.rpm

KDIR="/usr/src/kernels/${KERNEL_VERSION}"
test -d "$KDIR"

KBASE="${KERNEL_VERSION%%-*}"      # 7.2.9-ogc3.1.fc44.x86_64 -> 7.2.9
MAJOR="${KBASE%%.*}"               # 7
BASE_URL="https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x"
TARBALL="linux-${KBASE}.tar.xz"

mkdir -p /src/mei-src && cd /src/mei-src
curl -fsSLO "${BASE_URL}/${TARBALL}"
curl -fsSLO "${BASE_URL}/sha256sums.asc"
grep " ${TARBALL}\$" sha256sums.asc | sha256sum -c -

mkdir mei
tar -xJf "$TARBALL" -C mei --strip-components=4 "linux-${KBASE}/drivers/misc/mei"
cd mei

echo "In-tree mei-me objects (for reference):"
grep -n 'mei-me' Makefile || true

# Add the Ice Lake iTouch ID. Anchors match both table styles; the greps fail
# the build if the kernel source changed shape.
sed -i '/#define MEI_DEV_ID_ICP_LP[[:space:]]/a #define MEI_DEV_ID_ICP_LP_3   0x34E4  /* Ice Lake Point LP 3 (iTouch) */' hw-me-regs.h
sed -i '/MEI_PCI_DEVICE(MEI_DEV_ID_ICP_LP,/a {MEI_PCI_DEVICE(MEI_DEV_ID_ICP_LP_3, MEI_ME_PCH12_CFG)},' pci-me.c
grep -n 'ICP_LP_3' hw-me-regs.h pci-me.c
test "$(grep -c 'ICP_LP_3' hw-me-regs.h)" -eq 1
test "$(grep -c 'ICP_LP_3' pci-me.c)" -eq 1

cat > Kbuild <<'EOF'
obj-m += mei-me.o
mei-me-objs := pci-me.o hw-me.o
ccflags-y := -I$(src)
EOF

make -C "$KDIR" M="$PWD" modules

"$KDIR/scripts/sign-file" sha256 "$KEY" "$CERT" mei-me.ko

modinfo mei-me.ko | grep -E '^(vermagic|depends|signer|sig_key|sig_hashalgo)'
modinfo -F vermagic mei-me.ko | grep -q "^${KERNEL_VERSION} " \
    || { echo "vermagic does not match ${KERNEL_VERSION}" >&2; exit 1; }
aliases="$(modinfo -F alias mei-me.ko)"
grep -qi '34E4' <<<"$aliases" || { echo "34E4 alias missing" >&2; exit 1; }

install -D -m 644 mei-me.ko "/out/usr/lib/modules/${KERNEL_VERSION}/updates/mei-me.ko"
