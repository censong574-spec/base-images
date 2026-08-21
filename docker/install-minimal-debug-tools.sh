#!/bin/sh
# Minimal ops tools for offline troubleshooting: curl, ss, vi, ps/top, tcpdump, tailf, ping, dig/nslookup.
# Ubuntu 22.04 dropped the tailf package; install a tail -f wrapper instead.
# Docs/man/locale are excluded to keep the image small.
#
# When AI_SKIP_APT=1 (Dockerfile already installed packages from the
# host-cached local apt repo), this script only writes the tailf wrapper
# and strips docs.
set -eu

printf '%s\n' \
  'path-exclude=/usr/share/doc/*' \
  'path-exclude=/usr/share/man/*' \
  'path-exclude=/usr/share/info/*' \
  'path-exclude=/usr/share/locale/*' \
  'path-exclude=/usr/share/groff/*' \
  'path-exclude=/usr/share/lintian/*' \
  > /etc/dpkg/dpkg.cfg.d/01_nodoc

if [ "${AI_SKIP_APT:-0}" != "1" ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends \
    curl \
    iproute2 \
    vim-tiny \
    procps \
    tcpdump \
    iputils-ping \
    bind9-dnsutils
fi

if ! command -v tailf >/dev/null 2>&1; then
  printf '%s\n' '#!/bin/sh' 'exec tail -f "$@"' > /usr/local/bin/tailf
  chmod 0755 /usr/local/bin/tailf
fi

rm -rf \
  /usr/share/doc/* \
  /usr/share/man/* \
  /usr/share/info/* \
  /usr/share/locale/* \
  /usr/share/groff/* \
  /usr/share/lintian/* \
  /var/cache/debconf/*
