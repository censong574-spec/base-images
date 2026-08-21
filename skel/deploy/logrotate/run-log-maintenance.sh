#!/usr/bin/env bash
set -euo pipefail
APP_DIR="${APP_DIR:-/opt/ai/app}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CONF="$APP_DIR/conf/logrotate.conf"
LOG_DIR="${AI_LOG_DIR:-$APP_DIR/logs}"
STATE="$LOG_DIR/.logrotate.status"
CLEANUP="$HERE/cleanup-log-quota.sh"
LOG_DIRS=("$LOG_DIR")
QUOTA_GIB="${APP_LOG_QUOTA_GIB:-5}"
mkdir -p "$APP_DIR/conf" "${LOG_DIRS[@]}"

if ! command -v logrotate >/dev/null 2>&1; then
  echo "run-log-maintenance: logrotate is required but not installed in this image." >&2
  exit 1
fi
if [[ ! -f "$CONF" ]]; then
  echo "run-log-maintenance: missing config $CONF" >&2
  exit 1
fi

if [[ -x /usr/sbin/logrotate ]]; then
  /usr/sbin/logrotate -s "$STATE" "$CONF"
else
  logrotate -s "$STATE" "$CONF"
fi

for dir in "${LOG_DIRS[@]}"; do
  if [[ -x "$CLEANUP" ]]; then
    "$CLEANUP" "$dir" "$QUOTA_GIB" || true
  fi
done
