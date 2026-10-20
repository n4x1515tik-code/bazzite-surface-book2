#!/bin/bash

set -ouex pipefail

: "${KERNEL_VERSION:?KERNEL_VERSION must be set}"

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# The IPTS module was copied in from the builder stage; register it so it
# autoloads (it matches the touch controller's MEI client UUID).
test -f "/usr/lib/modules/${KERNEL_VERSION}/extra/ipts/ipts.ko"
depmod -a "${KERNEL_VERSION}"
modinfo -k "${KERNEL_VERSION}" ipts | grep -E '^(filename|signer|alias)'

# Patched mei-me (adds the Ice Lake iTouch PCI ID 8086:34e4). It must beat the
# stock module, carry the new alias, and be signed.
test -f "/usr/lib/modules/${KERNEL_VERSION}/updates/mei-me.ko"
mei_path="$(modinfo -k "${KERNEL_VERSION}" -n mei_me)"
[[ "$mei_path" == */updates/mei-me.ko ]]
mei_alias="$(modinfo -k "${KERNEL_VERSION}" -F alias mei_me)"
grep -qi '34E4' <<<"$mei_alias"
modinfo -k "${KERNEL_VERSION}" -F signer mei_me

# Trust this image's own cosign key, so updates are verified like Bazzite's.
python3 - <<'EOF'
import json
path = "/etc/containers/policy.json"
with open(path) as f:
    policy = json.load(f)
policy["transports"]["docker"]["ghcr.io/roguesergeant/bazzite-surface-book2"] = [{
    "type": "sigstoreSigned",
    "keyPath": "/etc/pki/containers/bazzite-surface-book2.pub",
    "signedIdentity": {"type": "matchRepository"},
}]
with open(path, "w") as f:
    json.dump(policy, f, indent=4)
EOF

# iptsd is started per-device by its udev rule; make sure both landed.
test -x /usr/bin/iptsd
ls /usr/lib/udev/rules.d/*iptsd* /usr/lib/systemd/system/iptsd@.service

# iptsd's unit is BindsTo= its hidraw device unit, but upstream's rule only tags
# the device on ACTION=="add". A later "change" event (e.g. udev coldplug at
# boot) leaves the device untagged, systemd deactivates the device unit, and
# iptsd is stopped a few seconds into every boot. Tag on any non-remove event.
RULE=/usr/lib/udev/rules.d/50-iptsd.rules
grep -q 'ACTION=="add"' "$RULE"
sed -i 's/ACTION=="add"/ACTION!="remove"/' "$RULE"
grep -q 'ACTION!="remove"' "$RULE"
