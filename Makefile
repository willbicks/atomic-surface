IMG_BASE       ?= localhost/fedora-surface-base:latest
IMG_SILVERBLUE ?= localhost/fedora-surface-silverblue:latest
IMG_OUT        ?= localhost/fedora-surface:latest
IMG_CHUNKED    ?= localhost/fedora-surface:chunked

OUTPUT         ?= output
CONFIG         ?= config.toml

IMG_INSTALLER     ?= localhost/fedora-surface:installer
INSTALLER_PAYLOAD ?= $(IMG_OUT)

IMG_BUILDER    ?= quay.io/centos-bootc/bootc-image-builder:latest
IMG_RECHUNKER  ?= quay.io/centos-bootc/centos-bootc:stream10

VM_MEM     ?= 8192
VM_CPUS    ?= 2

PRIV_BUILD ?= --isolation=chroot --cap-add=all \
              --security-opt label=type:unconfined_t \
              --security-opt seccomp=unconfined
PRIV_RUN   ?= --privileged --security-opt label=type:unconfined_t

.SUFFIXES:
.DEFAULT_GOAL := build
.PHONY: all build base silverblue mine rechunk disk run installer installer-img run-installer clean

all: rechunk disk

build: mine

base:
	sudo podman build -f base.containerfile \
		$(PRIV_BUILD) \
		-t $(IMG_BASE) .

silverblue: base
	sudo podman build -f silverblue.containerfile \
		--build-arg BASE_IMAGE=$(IMG_BASE) \
		$(PRIV_BUILD) \
		-t $(IMG_SILVERBLUE) .

mine: silverblue
	sudo podman build -f mine.containerfile \
		--build-arg SILVERBLUE_IMAGE=$(IMG_SILVERBLUE) \
		$(PRIV_BUILD) \
		-t $(IMG_OUT) .

## Rechunk the image in-place storage via bootc-base-imagectl
rechunk: build
	sudo podman run \
	    --rm \
	    $(PRIV_RUN) \
	    -v /var/lib/containers:/var/lib/containers \
	    $(IMG_RECHUNKER) \
	    /usr/libexec/bootc-base-imagectl rechunk \
	        $(IMG_OUT) \
	        $(IMG_CHUNKED)

## Build the qcow2 disk image
disk: build
	mkdir -p $(OUTPUT)
	sudo podman run \
	    --rm \
	    -it \
	    --pull=newer \
	    $(PRIV_RUN) \
	    -v $(CURDIR)/$(CONFIG):/config.toml:ro \
	    -v $(CURDIR)/$(OUTPUT):/output \
	    -v /var/lib/containers/storage:/var/lib/containers/storage \
	    $(IMG_BUILDER) \
	    --type qcow2 \
	    --use-librepo=True \
	    --rootfs ext4 \
	    $(IMG_OUT)

## Boot the qcow2 in QEMU
run: disk
	qemu-system-x86_64 \
	    -M accel=kvm \
	    -cpu host \
	    -smp $(VM_CPUS) \
	    -m $(VM_MEM) \
	    -bios /usr/share/OVMF/OVMF_CODE.fd \
	    -serial stdio \
	    -snapshot $(OUTPUT)/qcow2/disk.qcow2

# Build the installer image
installer-img: build
	sudo podman build \
	    --build-arg PAYLOAD_IMAGE=$(INSTALLER_PAYLOAD) \
	    -f installer.containerfile -t $(IMG_INSTALLER) .

## Build the bootc-installer ISO
installer: installer-img
	mkdir -p $(OUTPUT)
	sudo podman run \
	    --rm \
	    -it \
	    --pull=newer \
	    $(PRIV_RUN) \
	    -v $(CURDIR)/$(OUTPUT):/output \
	    -v $(CURDIR)/$(CONFIG):/config.toml:ro \
	    -v /var/lib/containers/storage:/var/lib/containers/storage \
	    $(IMG_BUILDER) \
	    --type bootc-installer \
		--rootfs ext4 \
	    --installer-payload-ref $(INSTALLER_PAYLOAD) \
	    $(IMG_INSTALLER)

## Boot the bootc-installer ISO in QEMU
run-installer: installer
	qemu-system-x86_64 \
	    -M accel=kvm \
	    -cpu host \
	    -smp $(VM_CPUS) \
	    -m $(VM_MEM) \
	    -bios /usr/share/OVMF/OVMF_CODE.fd \
	    -serial stdio \
	    -cdrom $(OUTPUT)/iso/install.iso

clean:
	rm -rf $(OUTPUT)
