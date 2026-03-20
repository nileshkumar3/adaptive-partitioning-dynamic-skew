#!/usr/bin/env bash
# Sample consumer group LAG on an interval and append TSV: unix_ts  total_lag  group
# Usage: collect-lag.sh <group_id> [interval_sec] [outfile]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

GROUP="${1:?consumer group id}"
INTERVAL="${2:-2}"
OUT="${3:-$ROOT/results/lag_timeseries.tsv}"
mkdir -p "$(dirname "$OUT")"

if [[ ! -s "$OUT" ]]; then
  printf 'unix_ts\ttotal_lag\tgroup\n' >>"$OUT"
fi

sum_lag_for_group() {
  local g="$1"
  kafka_groups_sh --describe --group "$g" 2>/dev/null \
    | awk '$2 ~ /^[0-9]+$/ && NF >= 5 && $5 ~ /^[0-9]+$/ { s += $5 } END { print s+0 }'
}

echo "Collecting lag for group=$GROUP every ${INTERVAL}s → $OUT (Ctrl+C to stop)"
while true; do
  ts=$(date +%s)
  lag=$(sum_lag_for_group "$GROUP")
  printf '%s\t%s\t%s\n' "$ts" "$lag" "$GROUP" >>"$OUT"
  sleep "$INTERVAL"
done
