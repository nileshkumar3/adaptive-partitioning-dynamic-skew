#!/usr/bin/env bash
# Poll consumer group lag with local kafka-consumer-groups.sh; append TSV until Ctrl+C.
#
# Usage:
#   ./scripts/collect-lag.sh TOPIC GROUP_ID [INTERVAL_SECONDS] [OUTFILE]
# Default interval: 5 seconds
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

kafka_require

TOPIC="${1:?topic (for logging; describe uses group)}"
GROUP="${2:?consumer group id}"
INTERVAL="${3:-5}"
OUT="${4:-$ROOT/results/lag_timeseries.tsv}"

mkdir -p "$(dirname "$OUT")"

if [[ ! -s "$OUT" ]]; then
  printf 'unix_ts\tiso_utc\ttotal_lag\tgroup\ttopic\n' >>"$OUT"
fi

sum_lag_for_group() {
  local g="$1"
  kafka_groups_sh --describe --group "$g" 2>/dev/null \
    | awk '$2 ~ /^[0-9]+$/ && NF >= 5 && $5 ~ /^[0-9]+$/ { s += $5 } END { print s+0 }'
}

echo "Collecting lag for group=$GROUP topic=$TOPIC every ${INTERVAL}s → $OUT (Ctrl+C to stop)"
while true; do
  ts=$(date +%s)
  iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  lag=$(sum_lag_for_group "$GROUP")
  printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$iso" "$lag" "$GROUP" "$TOPIC" >>"$OUT"
  sleep "$INTERVAL"
done
