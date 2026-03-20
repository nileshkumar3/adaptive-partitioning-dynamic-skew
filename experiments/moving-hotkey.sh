#!/usr/bin/env bash
# Sweep phase duration so the hot key moves faster or slower (dynamic skew / churn).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${BOOTSTRAP_SERVERS:=localhost:9092}"
: "${TOPIC:=dynamic-skew}"
: "${KAFKA_HOME:=${KAFKA_HOME:-}}"
: "${RESULT_LAG:=$ROOT/results/lag.txt}"
: "${RESULT_TP:=$ROOT/results/throughput.txt}"

PHASE_MS_LIST="${PHASE_MS_LIST:-2000 5000 10000 20000}"

echo "# moving-hotkey experiment $(date -u +%Y-%m-%dT%H:%M:%SZ) bootstrap=$BOOTSTRAP_SERVERS topic=$TOPIC" >>"$RESULT_LAG"
echo "# moving-hotpack phase_ms consumer_group p99_lag_ms" >>"$RESULT_LAG"
echo "# moving-hotkey experiment $(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$RESULT_TP"
echo "# phase_ms partitioner msgs_per_s" >>"$RESULT_TP"

for phase in $PHASE_MS_LIST; do
  echo "=== phase_ms=$phase (set PHASE_MS for workload generator) ==="
  echo "Export PHASE_MS=$phase when running the workload and record lag/throughput below."
  printf '%s\t%s\t%s\n' "$phase" "adaptive" "PLACEHOLDER" >>"$RESULT_TP"
  printf '%s\t%s\t%s\n' "$phase" "PLACEHOLDER_GROUP" "PLACEHOLDER" >>"$RESULT_LAG"
done

if [[ -n "$KAFKA_HOME" ]] && [[ -x "$KAFKA_HOME/bin/kafka-consumer-groups.sh" ]]; then
  echo "Kafka tools found; example lag check:"
  echo "  $KAFKA_HOME/bin/kafka-consumer-groups.sh --bootstrap-server $BOOTSTRAP_SERVERS --describe --all-groups"
else
  echo "Set KAFKA_HOME to use bundled kafka-consumer-groups.sh for live lag samples."
fi
