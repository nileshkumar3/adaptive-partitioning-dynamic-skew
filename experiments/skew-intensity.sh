#!/usr/bin/env bash
# Sweep hot-key traffic fraction (skew intensity) for a fixed phase (moving-hotkey rate).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${BOOTSTRAP_SERVERS:=localhost:9092}"
: "${TOPIC:=dynamic-skew}"
: "${RESULT_LAG:=$ROOT/results/lag.txt}"
: "${RESULT_TP:=$ROOT/results/throughput.txt}"

HOT_FRACTIONS="${HOT_FRACTIONS:-0.2 0.4 0.6 0.8 0.95}"

echo "# skew-intensity experiment $(date -u +%Y-%m-%dT%H:%M:%SZ) bootstrap=$BOOTSTRAP_SERVERS topic=$TOPIC" >>"$RESULT_TP"
echo "# hot_fraction partitioner msgs_per_s" >>"$RESULT_TP"
echo "# skew-intensity experiment $(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$RESULT_LAG"
echo "# hot_fraction consumer_group p99_lag_ms" >>"$RESULT_LAG"

for frac in $HOT_FRACTIONS; do
  echo "=== hot_fraction=$frac (pass as 5th arg to DynamicSkewGenerator or patch workload) ==="
  printf '%s\t%s\t%s\n' "$frac" "adaptive" "PLACEHOLDER" >>"$RESULT_TP"
  printf '%s\t%s\t%s\n' "$frac" "PLACEHOLDER_GROUP" "PLACEHOLDER" >>"$RESULT_LAG"
done
