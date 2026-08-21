#!/usr/bin/env bash
# Shared helpers for logging-stack service image builds.
ops_log() { printf '[ops-helpers] %s\n' "$*"; }
ops_die() { printf '[ops-helpers] ERROR: %s\n' "$*" >&2; return 1; }

ops_bases_dir() {
  local d="${OPS_BASE_IMAGES_DIR:-}"
  if [[ -n "$d" && -d "$d" ]]; then
    printf '%s\n' "$(cd "$d" && pwd)"
    return 0
  fi
  d="${REPO_DIR:-}/../base-images"
  if [[ -d "$d" ]]; then
    printf '%s\n' "$(cd "$d" && pwd)"
    return 0
  fi
  return 1
}

ops_ensure_image() {
  local img="$1"
  docker image inspect "$img" >/dev/null 2>&1
}

ops_ensure_jdk_bases() {
  local build_img="${JDK_BUILD_IMAGE:-local/ai-jdk-build:21.0.12}"
  local runtime_img="${JDK_RUNTIME_IMAGE:-local/ai-jdk-runtime:21.0.12}"
  ops_ensure_image "$build_img" && ops_ensure_image "$runtime_img" && return 0
  local b
  b="$(ops_bases_dir)" || {
    ops_die "missing $build_img / $runtime_img (build base-images first)"
    return 1
  }
  ops_log "building JDK bases via $b"
  bash "$b/scripts/build-bases.sh" jdk
}

ops_ensure_go_bases() {
  local img="${GO_TOOLCHAIN_IMAGE:-local/ai-go-toolchain:1.26.5}"
  ops_ensure_image "$img" && return 0
  local b
  b="$(ops_bases_dir)" || {
    ops_die "missing $img"
    return 1
  }
  bash "$b/scripts/build-bases.sh" go
}

ops_ensure_node_bases() {
  local build_img="${NODE_BUILD_IMAGE:-local/ai-node-build:24.18.0}"
  local runtime_img="${NODE_RUNTIME_IMAGE:-local/ai-node-runtime:24.18.0}"
  ops_ensure_image "$build_img" && ops_ensure_image "$runtime_img" && return 0
  local b
  b="$(ops_bases_dir)" || {
    ops_die "missing $build_img / $runtime_img"
    return 1
  }
  bash "$b/scripts/build-bases.sh" node
}

ops_ensure_source() {
  local file="$1"
  local installers="${INSTALLERS:-/opt/ai/installers}"
  mkdir -p "${REPO_DIR}/deps"
  if [[ -s "${REPO_DIR}/deps/$file" ]]; then
    return 0
  fi
  if [[ -s "$installers/$file" ]]; then
    cp -f "$installers/$file" "${REPO_DIR}/deps/$file"
    ops_log "reuse $installers/$file"
    return 0
  fi
  local b
  if b="$(ops_bases_dir)"; then
    if [[ ! -s "$b/deps/$file" ]]; then
      OPS_DEPS_ONLY_FILES="$file" bash "$b/scripts/download-deps.sh"
    fi
    cp -f "$b/deps/$file" "${REPO_DIR}/deps/$file"
    return 0
  fi
  ops_die "missing source archive ${REPO_DIR}/deps/$file"
  return 1
}

ops_ensure_apt_debs() {
  local dest="${REPO_DIR}/deps/ubuntu-22.04-logging-apt-debs.tar.gz"
  if [[ -s "$dest" ]]; then
    return 0
  fi
  local b
  if b="$(ops_bases_dir)"; then
    bash "$b/scripts/package-runtime-apt-debs.sh"
    mkdir -p "${REPO_DIR}/deps"
    cp -f "$b/deps/ubuntu-22.04-logging-apt-debs.tar.gz" "$dest"
    return 0
  fi
  bash "${REPO_DIR}/scripts/package-runtime-apt-debs.sh"
}
