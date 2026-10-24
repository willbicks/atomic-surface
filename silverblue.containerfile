# Silverblue image: layered on base and adds packages based on upstream
# silverblue lists.

ARG BASE_IMAGE=localhost/fedora-surface-base:latest

FROM quay.io/fedora/fedora-bootc:43 AS builder

ARG ATOMIC_CONFIG_REF=f43

RUN dnf install -y rpm-ostree git jq \
	&& git clone --depth 1 -b ${ATOMIC_CONFIG_REF} \
		https://forge.fedoraproject.org/atomic-desktops/config.git /atomic-config

# Resolve the upstream manifest to flattened package lists
RUN <<EOF
set -euo pipefail
cd /atomic-config

rpm-ostree compose tree --print-only --repo=repo silverblue.yaml > /manifest.json

jq -r '.packages | if type == "array" then .[] else error("packages missing from rendered manifest") end' \
	/manifest.json | sort -u > /pkgs-all.txt
jq -r '."exclude-packages" | if type == "array" then .[] else error("exclude-packages missing from rendered manifest") end' \
	/manifest.json | sort -u > /pkgs-excluded.txt

test -s /pkgs-all.txt

printf '%s\n' gnome-software gnome-software-rpm-ostree PackageKit-glib rpm-ostree \
	virtualbox-guest-additions >> /pkgs-excluded.txt

comm -23 /pkgs-all.txt <(sort -u /pkgs-excluded.txt) \
	| grep -v '^kernel' > /pkgs.txt

sed 's/^/--exclude=/' /pkgs-excluded.txt | tr '\n' ' ' > /pkgs-exclude-args.txt
EOF

FROM ${BASE_IMAGE}

COPY --from=builder /pkgs.txt /pkgs-exclude-args.txt /run/

RUN <<EORUN
set -xeuo pipefail

xargs dnf -y install $(cat /run/pkgs-exclude-args.txt) < /run/pkgs.txt

systemctl enable gdm

cat > /usr/lib/systemd/system-generators/90-graphical-default <<'EOF'
#!/bin/bash
current=$(readlink /etc/systemd/system/default.target 2>/dev/null) || true
[ -n "$current" ] || current=$(readlink /run/systemd/system/default.target 2>/dev/null) || true
[ -n "$current" ] || current=$(readlink /usr/lib/systemd/system/default.target 2>/dev/null) || true
case "${current##*/}" in
	graphical.target) exit 0 ;;
esac
out="${2:-$1}"
[ -n "$out" ] || exit 0
ln -sfn /usr/lib/systemd/system/graphical.target "$out/default.target"
exit 0
EOF

chmod +x /usr/lib/systemd/system-generators/90-graphical-default

dnf clean all
rm -rf /usr/etc
rm -rf /var/{log,cache,lib}/*
rm -rf /run/* /tmp/* || true
rm -rf /boot/*

# Delete and configure tmptiles.d for cups / plymouth
rm -rf /var/spool/cups /var/spool/plymouth
cat > /usr/lib/tmpfiles.d/spool.conf <<'EOF'
d /var/spool/cups 0710 root root - -
d /var/spool/plymouth 0755 root root - -
EOF

bootc container lint
EORUN
