ARG SILVERBLUE_IMAGE=localhost/fedora-surface-silverblue:latest
FROM ${SILVERBLUE_IMAGE}

RUN <<EORUN
set -xeuo pipefail

dnf -y copr enable copr.fedorainfracloud.org/jloehel/yadm
dnf -y copr enable copr.fedorainfracloud.org/scottames/ghostty
dnf -y install openssh-server ghostty yadm

systemctl enable sshd

# Clean up unnecessary files
dnf clean all
rm -rf /usr/etc
rm -rf /var/{log,cache,lib}/*
rm -rf /run/* /tmp/* || true

bootc container lint
EORUN
