FROM quay.io/fedora/fedora-bootc:43 as builder

ARG KERNEL_VERSION=6.19.8
ARG KERNEL_MINOR=6.19
ARG SURFACE_VERSION=fedora-43-6.19.8-3

RUN dnf install -y @development-tools bc dwarves bubblewrap \
	elfutils-libelf-devel openssl-devel dracut

RUN mkdir /var/roothome \
	&& git config --global advice.defaultBranchName false \
	&& git config --global advice.detachedHead false \
	&& git config --global user.name "Will Bicks" \
	&& git config --global user.email "will@willbicks.com"

RUN git init linux && cd linux \
	&& git remote add origin https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
	&& git fetch --depth 1 origin refs/tags/v${KERNEL_VERSION}:refs/tags/v${KERNEL_VERSION} \
	&& git checkout v${KERNEL_VERSION}

RUN git init linux-surface && cd linux-surface \
	&& git remote add origin https://github.com/linux-surface/linux-surface.git \
	&& git fetch --depth 1 origin refs/tags/${SURFACE_VERSION}:refs/tags/${SURFACE_VERSION} \
	&& git checkout ${SURFACE_VERSION}

# Pull a base config from a current Fedora kernel package
RUN dnf install -y kernel-core-${KERNEL_VERSION}-*

WORKDIR /linux

RUN git switch -c v${KERNEL_VERSION}-surface-wbicks

# Apply surface patches as commits on top of the kernel tag
RUN git am -3 /linux-surface/patches/${KERNEL_MINOR}/*.patch

RUN ./scripts/kconfig/merge_config.sh /lib/modules/${KERNEL_VERSION}*/config \
		/linux-surface/configs/surface-${KERNEL_MINOR}.config \
	&& ./scripts/config --disable LOCALVERSION_AUTO

RUN git tag -a v${KERNEL_VERSION}-surface-wbicks -m "v${KERNEL_VERSION} + linux-surface patches" \
	&& echo "-surface-wbicks" > localversion-surface

# Build the kernel
RUN make olddefconfig && make -j"$(nproc)"

# Generate the minimal root filesystem
RUN /usr/libexec/bootc-base-imagectl build-rootfs /target-rootfs

# Remove the distro kernel from the target rootfs rpmdb
RUN dnf -y --installroot=/target-rootfs --releasever=43 remove 'kernel*' \
	&& rm -rf /target-rootfs/usr/lib/modules/*

# Install the built kernel into the target rootfs
RUN krel=$(make -s kernelrelease) \
	&& make INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH=/target-rootfs modules_install \
	&& install -Dm644 arch/x86/boot/bzImage "/target-rootfs/usr/lib/modules/${krel}/vmlinuz" \
	&& install -Dm644 .config "/target-rootfs/usr/lib/modules/${krel}/config" \
	&& install -Dm644 System.map "/target-rootfs/usr/lib/modules/${krel}/System.map" \
	&& dracut --force --no-hostonly --kver "${krel}" \
		--kmoddir "/target-rootfs/usr/lib/modules/${krel}" \
		"/target-rootfs/usr/lib/modules/${krel}/initramfs.img"

# Begin scratch image creation
FROM scratch

ARG OS_VARIANT="Atomic Surface"
ARG OS_VARIANT_ID="com.willbicks.fedora-atomic-surface"

COPY --from=builder /target-rootfs/ /

RUN echo "VARIANT=\"${OS_VARIANT}\"" >> /usr/lib/os-release \
	&& echo "VARIANT_ID=${OS_VARIANT_ID}" >> /usr/lib/os-release

RUN <<EORUN
set -xeuo pipefail

dnf -y install @gnome-desktop openssh-server

systemctl enable sshd

# Clean up unnecessary files
dnf clean all
rm -rf /usr/etc
rm -rf /var/{log,cache,lib}/*
rm -rf /run/* /tmp/* || true

bootc container lint
EORUN

LABEL containers.bootc 1
LABEL ostree.bootable 1

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
