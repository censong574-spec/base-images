#!/bin/sh
set -eu
PID_FILE="${APP_PID_FILE:-/var/run/app.pid}"

stop_pid() {
  pid="$1"
  kill "$pid" 2>/dev/null || true
  i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 15 ]; do
    sleep 1
    i=$((i + 1))
  done
  kill -9 "$pid" 2>/dev/null || true
}

if [ -f "$PID_FILE" ]; then
  pid=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    echo "[stop] stopping pid=$pid"
    stop_pid "$pid"
  fi
  rm -f "$PID_FILE"
fi
echo "[stop] done"
