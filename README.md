# Fedora Atomic Surface

A bootc image for Microsoft Surface devices, built with the
[linux-surface](https://github.com/linux-surface/linux-surface) kernel 
and Fedora's silverblue userspace.

Currently builds Fedora 43 with kernel 6.19.8.

## Layout

The image is built in three layered containerfiles:

| Containerfile | Contents |
| --- | --- |
| `base.containerfile` | Fedora bootc base with a patched linux-surface kernel and Intel WiFi firmware |
| `silverblue.containerfile` | Fedora Silverblue package set, resolved from the upstream atomic-desktops manifest |
| `mine.containerfile` | My personal additions (ghostty, yadm) |
| `installer.containerfile` | Anaconda-based installer payload for `bootc-image-builder` |

## Usage

```sh
make            # alias to `make mine`
make base       # base kernel/firmware image
make silverblue # base + Silverblue package set
make mine       # silverblue + personal additions
make rechunk    # rechunk the image in-place (bootc-base-imagectl)
make disk       # build a qcow2 disk image via bootc-image-builder
make run        # boot the qcow2 in QEMU
make installer  # build a bootc-installer ISO
make run-installer # boot the installer ISO in QEMU
make all        # make the rechunked iamge and disk
make clean      # remove output/
```
