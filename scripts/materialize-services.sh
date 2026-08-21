#!/usr/bin/env bash
# Copy AgentLink-style runtime/docker skel into each logging service repo.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKEL="$ROOT/skel"
OPS="$(cd "$ROOT/.." && pwd)"

copy_tree() {
  local dest="$1"
  mkdir -p "$dest/docker" "$dest/scripts" "$dest/runtime" "$dest/deploy/logrotate" "$dest/deploy/lib" "$dest/deps"
  cp -f "$ROOT/docker/install-minimal-debug-tools.sh" "$dest/docker/"
  cp -f "$ROOT/docker/install-runtime-apt-local.sh" "$dest/docker/"
  cp -f "$ROOT/docker/runtime-apt-packages.txt" "$dest/docker/"
  cp -f "$SKEL/runtime/run.sh" "$dest/runtime/"
  cp -f "$SKEL/runtime/stop.sh" "$dest/runtime/"
  cp -f "$SKEL/deploy/logrotate/logrotate.conf" "$dest/deploy/logrotate/"
  cp -f "$SKEL/deploy/logrotate/run-log-maintenance.sh" "$dest/deploy/logrotate/"
  cp -f "$ROOT/../base-images/skel/deploy/logrotate/cleanup-log-quota.sh" "$dest/deploy/logrotate/" 2>/dev/null || true
  cp -f "$SKEL/deploy/lib/ops-helpers.sh" "$dest/deploy/lib/"
  cp -f "$ROOT/scripts/package-runtime-apt-debs.sh" "$dest/scripts/"
  touch "$dest/deps/.gitkeep"
}

# cleanup script lives next to this after we copy it into skel
if [[ ! -f "$SKEL/deploy/logrotate/cleanup-log-quota.sh" ]]; then
  echo "missing cleanup-log-quota.sh in skel" >&2
  exit 1
fi

for svc in kafka-service elasticsearch-service LogStash kibana-service grafana-service FileBeat; do
  dest="$OPS/$svc"
  mkdir -p "$dest"
  copy_tree "$dest"
  echo "materialized $dest"
done
