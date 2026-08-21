#!/usr/bin/env bash
# Purge oldest log archives when a log directory exceeds 80% of its quota.
# Usage: cleanup-log-quota.sh <log_dir> [quota_gib]
set -euo pipefail

DIR="${1:-}"
QUOTA_GIB="${2:-5}"

if [[ -z "$DIR" || ! -d "$DIR" ]]; then
  echo "cleanup-log-quota: skip (missing dir: ${DIR:-})" >&2
  exit 0
fi

if ! [[ "$QUOTA_GIB" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "cleanup-log-quota: invalid quota_gib='$QUOTA_GIB'" >&2
  exit 1
fi

QUOTA_BYTES=$(awk -v g="$QUOTA_GIB" 'BEGIN { printf "%.0f", g * 1024 * 1024 * 1024 }')
TRIGGER=$(awk -v q="$QUOTA_BYTES" 'BEGIN { printf "%.0f", q * 0.80 }')
TARGET=$(awk -v q="$QUOTA_BYTES" 'BEGIN { printf "%.0f", q * 0.70 }')

usage_bytes() {
  du -sb "$DIR" 2>/dev/null | awk '{print $1}'
}

USED=$(usage_bytes)
if [[ "$USED" -lt "$TRIGGER" ]]; then
  exit 0
fi

echo "cleanup-log-quota: $DIR used=${USED}B trigger=${TRIGGER}B quota=${QUOTA_BYTES}B; purging oldest archives"

mapfile -t ARCHIVES < <(
  {
    find "$DIR" -maxdepth 1 -type f \( \
      -name '*.gz' -o \
      -name '*.log-*' -o \
      -name '*.jsonl-*' \
    \) ! -name '*.log' ! -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null
    find "$DIR" -mindepth 2 -type f -printf '%T@ %p\n' 2>/dev/null
  } \
    | sort -n \
    | awk '{ $1=""; sub(/^ /,""); print }'
)

for f in "${ARCHIVES[@]:-}"; do
  [[ -z "$f" || ! -f "$f" ]] && continue
  USED=$(usage_bytes)
  if [[ "$USED" -le "$TARGET" ]]; then
    break
  fi
  rm -f -- "$f"
  echo "cleanup-log-quota: removed $f"
done

USED=$(usage_bytes)
echo "cleanup-log-quota: $DIR done used=${USED}B target=${TARGET}B"
