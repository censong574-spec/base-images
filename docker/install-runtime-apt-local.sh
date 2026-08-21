#!/bin/sh
# Install a per-image subset from the host-cached local file repo.
# Inputs (COPY or bind-mount):
#   /tmp/apt-debs.tgz
#   /tmp/runtime-apt-install.txt
#   /tmp/install-minimal-debug-tools.sh
set -eu

install_list=/tmp/runtime-apt-install.txt
[ -f "$install_list" ] || install_list=/tmp/runtime-apt-packages.txt
[ -f "$install_list" ] || { echo "missing runtime apt install list" >&2; exit 1; }

saved_list=/tmp/ai-apt-sources.list
saved_dir=/tmp/ai-apt-sources.list.d
if [ -f /etc/apt/sources.list ]; then
  cp -a /etc/apt/sources.list "$saved_list"
fi
if [ -d /etc/apt/sources.list.d ]; then
  cp -a /etc/apt/sources.list.d "$saved_dir"
fi

mkdir -p /opt/ai/apt-local
tar -xzf /tmp/apt-debs.tgz -C /opt/ai/apt-local
printf 'deb [trusted=yes] file:/opt/ai/apt-local ./\n' > /etc/apt/sources.list
rm -f /etc/apt/sources.list.d/*
export DEBIAN_FRONTEND=noninteractive
apt-get update
# shellcheck disable=SC2046
apt-get install -y --no-install-recommends \
  $(grep -E -v '^[[:space:]]*(#|$)' "$install_list")
AI_SKIP_APT=1 sh /tmp/install-minimal-debug-tools.sh
rm -rf /opt/ai/apt-local /var/lib/apt/lists/*

if [ -f "$saved_list" ]; then
  cp -a "$saved_list" /etc/apt/sources.list
else
  : >/etc/apt/sources.list
fi
rm -rf /etc/apt/sources.list.d
if [ -d "$saved_dir" ]; then
  cp -a "$saved_dir" /etc/apt/sources.list.d
else
  mkdir -p /etc/apt/sources.list.d
fi
