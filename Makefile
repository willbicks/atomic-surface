IMG_OUT     ?= localhost/fedora-surface:latest
IMG_CHUNKED ?= localhost/fedora-surface:chunked
OUTPUT      ?= output
CONFIG      ?= config.toml

IMG_BUILDER    ?= quay.io/centos-bootc/bootc-image-builder:latest
IMG_RECHUNKER  ?= quay.io/centos-bootc/centos-bootc:stream10

VM_MEM     ?= 8192
VM_CPUS    ?= 2

.SUFFIXES:
.DEFAULT_GOAL := build
.PHONY: all build rechunk disk run clean

all: rechunk disk

## Build the surface-kernel bootc image
build:
	sudo podman build -f Containerfile \
		--isolation=chroot \
		--cap-add=all \
		--security-opt label=type:unconfined_t \
		--security-opt seccomp=unconfined \
		-t $(IMG_OUT) .

## Rechunk the image in-place storage via bootc-base-imagectl
rechunk: build
	sudo podman run \
	    --rm \
	    --privileged \
	    --security-opt label=type:unconfined_t \
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
	    --privileged \
	    --pull=newer \
	    --security-opt label=type:unconfined_t \
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

clean:
	rm -rf $(OUTPUT)
