#!/usr/bin/env bash
# Pack Ubuntu 22.04 .debs for logging runtime images (jq/openssl/nc extras).
# Filename is logging-specific so it does not overwrite AgentLink's
# /opt/ai/installers/ubuntu-22.04-runtime-apt-debs.tar.gz.
if grep -q $'\r' "$0" 2>/dev/null; then
  sed -i 's/\r$//' "$0"
  exec bash "$0" "$@"
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPS="$REPO_DIR/deps"
AI_ROOT="${AI_ROOT:-/opt/ai}"
INSTALLERS="${INSTALLERS:-$AI_ROOT/installers}"
OUT_FILE="ubuntu-22.04-logging-apt-debs.tar.gz"
PACKAGES_FILE="$REPO_DIR/docker/runtime-apt-packages.txt"
UBUNTU_APT_MIRROR="${UBUNTU_APT_MIRROR:-http://mirrors.aliyun.com/ubuntu}"
UBUNTU_IMAGE="${UBUNTU_IMAGE:-m.daocloud.io/docker.io/library/ubuntu:22.04}"

log() { printf '[runtime-apt-debs] %s\n' "$*"; }
die() { printf '[runtime-apt-debs] ERROR: %s\n' "$*" >&2; exit 1; }

is_valid_tar() {
  local f="$1"
  [[ -s "$f" ]] || return 1
  tar -tf "$f" >/dev/null 2>&1
}

place_file() {
  local src="$1" dest="$2"
  [[ -n "$src" && -n "$dest" && -f "$src" ]] || return 1
  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" ]] && [[ "$src" -ef "$dest" ]]; then
    return 0
  fi
  rm -f "$dest"
  ln "$src" "$dest" 2>/dev/null || cp -f "$src" "$dest"
}

[[ -f "$PACKAGES_FILE" ]] || die "missing $PACKAGES_FILE"
pkg_hash="$(sha256sum "$PACKAGES_FILE" | awk '{print $1}')"

local_packer_id() {
  command -v docker >/dev/null 2>&1 || return 1
  docker image inspect --format '{{.Id}}' "$UBUNTU_IMAGE" 2>/dev/null
}

manifest_matches() {
  local manifest="$1" id
  [[ -f "$manifest" ]] || return 1
  grep -qF "packages=$pkg_hash" "$manifest" || return 1
  grep -qF "image=$UBUNTU_IMAGE" "$manifest" || return 1
  grep -qF "closure=1" "$manifest" || return 1
  if id="$(local_packer_id)"; then
    grep -qF "id=$id" "$manifest" || return 1
  fi
  return 0
}

reuse() {
  local tar="$1" manifest="$2"
  is_valid_tar "$tar" || return 1
  manifest_matches "$manifest" || return 1
  mkdir -p "$DEPS"
  place_file "$tar" "$DEPS/$OUT_FILE"
  if [[ ! "$manifest" -ef "$DEPS/${OUT_FILE}.manifest" ]]; then
    cp -f "$manifest" "$DEPS/${OUT_FILE}.manifest"
  fi
  if mkdir -p "$INSTALLERS" 2>/dev/null; then
    place_file "$DEPS/$OUT_FILE" "$INSTALLERS/$OUT_FILE" || true
    cp -f "$DEPS/${OUT_FILE}.manifest" "$INSTALLERS/${OUT_FILE}.manifest" || true
  fi
  log "cache hit: $tar"
  return 0
}

if reuse "$DEPS/$OUT_FILE" "$DEPS/${OUT_FILE}.manifest"; then
  exit 0
fi
if reuse "$INSTALLERS/$OUT_FILE" "$INSTALLERS/${OUT_FILE}.manifest"; then
  exit 0
fi

command -v docker >/dev/null || die "docker required"
docker info >/dev/null 2>&1 || die "docker daemon not running"
if ! docker image inspect "$UBUNTU_IMAGE" >/dev/null 2>&1; then
  log "pulling packer image $UBUNTU_IMAGE"
  docker pull "$UBUNTU_IMAGE"
fi
packer_id="$(docker image inspect --format '{{.Id}}' "$UBUNTU_IMAGE")"
expected="packages=$pkg_hash image=$UBUNTU_IMAGE id=$packer_id closure=1"

tmp_root="${TMPDIR:-/tmp}"
work="$(mktemp -d "$tmp_root/runtime-apt-debs.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/out"

log "downloading Ubuntu 22.04 logging debs + recursive depends via $UBUNTU_IMAGE"
docker run --rm \
  -e DEBIAN_FRONTEND=noninteractive \
  -e UBUNTU_APT_MIRROR="$UBUNTU_APT_MIRROR" \
  -v "$work/out:/out" \
  -v "$PACKAGES_FILE:/packages.txt:ro" \
  "$UBUNTU_IMAGE" \
  bash -c '
    set -euo pipefail
    sed -i "s#http://archive.ubuntu.com/ubuntu#${UBUNTU_APT_MIRROR}#g; s#http://security.ubuntu.com/ubuntu#${UBUNTU_APT_MIRROR}#g" /etc/apt/sources.list
    apt-get -o Acquire::Retries=3 update
    apt-get install -y --no-install-recommends apt-utils
    mapfile -t pkgs < <(grep -E -v "^[[:space:]]*(#|$)" /packages.txt)
    mapfile -t closure < <(
      apt-cache depends --recurse --no-recommends --no-suggests \
        --no-conflicts --no-breaks --no-replaces --no-enhances "${pkgs[@]}" \
        | awk "/^[a-zA-Z0-9][^:]*\$/ { print \$1 }" | sort -u
    )
    [[ ${#closure[@]} -gt 0 ]] || { echo "empty dependency closure" >&2; exit 1; }
    mkdir -p /tmp/debs-dl
    cd /tmp/debs-dl
    for p in "${closure[@]}"; do
      apt-cache show "$p" >/dev/null 2>&1 || continue
      apt-get download "$p"
    done
    mkdir -p /out/repo
    find /tmp/debs-dl /var/cache/apt/archives -maxdepth 1 -name "*.deb" -exec cp -a {} /out/repo/ \;
    cd /out/repo
    apt-ftparchive packages . > Packages
    gzip -n -k Packages
    test -s Packages
    ls *.deb >/dev/null
  '

[[ -s "$work/out/repo/Packages" ]] || die "apt repo pack produced no Packages index"
mkdir -p "$DEPS"
tar -czf "$DEPS/$OUT_FILE" -C "$work/out/repo" .
printf '%s\n' "$expected" > "$DEPS/${OUT_FILE}.manifest"
if mkdir -p "$INSTALLERS" 2>/dev/null; then
  place_file "$DEPS/$OUT_FILE" "$INSTALLERS/$OUT_FILE" || true
  cp -f "$DEPS/${OUT_FILE}.manifest" "$INSTALLERS/${OUT_FILE}.manifest" || true
  log "cached -> $INSTALLERS/$OUT_FILE"
fi
log "done: $(du -h "$DEPS/$OUT_FILE" | awk '{print $1}')"
