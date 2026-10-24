ARG PAYLOAD_IMAGE=quay.io/fedora/fedora-bootc:43
FROM ${PAYLOAD_IMAGE}

RUN dnf install -y \
	anaconda \
	anaconda-install-env-deps \
	anaconda-dracut \
	dracut-config-generic \
	dracut-network \
	net-tools \
	squashfs-tools \
	grub2-efi-x64-cdboot \
	python3-mako \
	lorax-templates-* \
	biosdevname \
	prefixdevname \
	&& dnf clean all

RUN dnf reinstall -y shim-x64 grub2-efi-x64 \
	&& mkdir -p /boot/efi

RUN mkdir /var/mnt
