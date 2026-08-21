#!/bin/sh
# Container PID1: start app, then stay alive for in-container hotfix (stop/edit/start).
set -eu
BIN_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
export APP_PID_FILE="${APP_PID_FILE:-/var/run/app.pid}"
APP_DIR="${APP_DIR:-/opt/ai/app}"
MAINT_ENTRY=""
maint_pid=""

path_ok() {
  case "$1" in
    ""|*[!A-Za-z0-9/._+-]*|*"#"*|*"'"*|*"\\"* ) return 1 ;;
    *) return 0 ;;
  esac
}

normalize_env() {
  if ! path_ok "$APP_DIR"; then
    echo "[maint] ERROR: APP_DIR rejected (unsafe chars): $APP_DIR" >&2
    APP_DIR="/opt/ai/app"
  fi
  _raw_interval="${LOG_MAINTENANCE_INTERVAL:-60}"
  case "$_raw_interval" in
    ""|*[!0-9]*) LOG_MAINTENANCE_INTERVAL=60 ;;
    *)
      LOG_MAINTENANCE_INTERVAL="$_raw_interval"
      if [ "$LOG_MAINTENANCE_INTERVAL" -lt 1 ]; then
        LOG_MAINTENANCE_INTERVAL=60
      fi
      ;;
  esac
}

prepare_log_maintenance() {
  _src="$APP_DIR/deploy/logrotate"
  if [ ! -f "$_src/logrotate.conf" ]; then
    _src="$BIN_DIR/../deploy/logrotate"
  fi
  if [ ! -f "$_src/logrotate.conf" ] || [ ! -f "$_src/run-log-maintenance.sh" ]; then
    echo "[maint] WARNING: deploy/logrotate artifacts missing; logs will not be rotated" >&2
    MAINT_ENTRY=""
    return 0
  fi
  mkdir -p "$APP_DIR/conf" "$APP_DIR/logs"
  chmod 0755 "$_src/run-log-maintenance.sh" "$_src/cleanup-log-quota.sh" 2>/dev/null || true
  sed -e "s#/opt/ai/app#${APP_DIR}#g" \
    "$_src/logrotate.conf" > "$APP_DIR/conf/logrotate.conf"

  if [ -n "${AI_LOG_DIR:-}" ] && [ "$AI_LOG_DIR" != "$APP_DIR/logs" ]; then
    if ! path_ok "$AI_LOG_DIR"; then
      echo "[maint] WARNING: AI_LOG_DIR rejected (unsafe chars): $AI_LOG_DIR" >&2
      AI_LOG_DIR=""
    else
      mkdir -p "$AI_LOG_DIR"
      sed -i -e "s#^${APP_DIR}/logs/#${AI_LOG_DIR}/#" \
             -e "s# ${APP_DIR}/logs # ${AI_LOG_DIR} #" \
        "$APP_DIR/conf/logrotate.conf"
    fi
  fi
  chmod 0644 "$APP_DIR/conf/logrotate.conf"
  MAINT_ENTRY="$_src/run-log-maintenance.sh"
}

start_log_maintenance() {
  if [ "${LOG_MAINTENANCE:-1}" = "0" ]; then
    echo "[maint] LOG_MAINTENANCE=0: log rotation disabled" >&2
    return 0
  fi
  if [ -z "$MAINT_ENTRY" ] || [ ! -x "$MAINT_ENTRY" ]; then
    echo "[maint] WARNING: run-log-maintenance.sh unavailable" >&2
    return 0
  fi
  MAINT_LOG="${AI_LOG_DIR:-$APP_DIR/logs}/log-maintenance.txt"
  mkdir -p "$(dirname "$MAINT_LOG")"
  (
    while true; do
      if ! APP_DIR="$APP_DIR" "$MAINT_ENTRY" >>"$MAINT_LOG" 2>&1; then
        echo "[maint] run-log-maintenance failed, see $MAINT_LOG" >&2
      fi
      sleep "$LOG_MAINTENANCE_INTERVAL" &
      wait $! || true
    done
  ) &
  maint_pid=$!
  echo "[maint] log ticker pid=$maint_pid interval=${LOG_MAINTENANCE_INTERVAL}s" >&2
}

term_handler() {
  [ -n "$maint_pid" ] && kill -TERM "$maint_pid" 2>/dev/null || true
  [ -x "$BIN_DIR/stop.sh" ] && "$BIN_DIR/stop.sh" || true
  exit 0
}

run_idle() {
  while true; do
    sleep 60 &
    wait $! || true
  done
}

main() {
  normalize_env
  prepare_log_maintenance
  trap term_handler TERM INT
  start_log_maintenance
  "$BIN_DIR/start.sh"
  run_idle
}

main "$@"
