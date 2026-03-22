#!/usr/bin/env bash
# End-to-end experiment: local Kafka → topic → background consumer + lag sampler → loadgen.
# Usage:
#   experiments/run_experiment.sh [--no-docker] [--no-consumer] loadgen_key=value ...
# (--no-docker is accepted for compatibility; Docker is not used.)
# Example:
#   experiments/run_experiment.sh bootstrap=localhost:9092 topic=skew-topic mode=DEDICATED threads=2 messagesPerSecond=50000 payloadSize=512 hotRatio=0.2 warmupSec=10 runSec=120
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

kafka_require

START_CONSUMER=1
LOADGEN_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-docker) shift ;;
    --no-consumer) START_CONSUMER=0; shift ;;
    *) LOADGEN_ARGS+=("$1"); shift ;;
  esac
done

: "${TOPIC:=skew-topic}"
: "${CONSUMER_GROUP:=skew-consumer}"
: "${PARTITIONS:=6}"
: "${LAG_INTERVAL:=2}"
: "${RESULT_LAG_TS:=$ROOT/results/lag_timeseries.tsv}"

if [[ ${#LOADGEN_ARGS[@]} -eq 0 ]]; then
  echo "usage: $0 [--no-docker] [--no-consumer] bootstrap=... topic=... mode=DEDICATED threads=... messagesPerSecond=... payloadSize=... hotRatio=... warmupSec=... runSec=..." >&2
  exit 2
fi

"$ROOT/scripts/kafka-setup.sh"

TOPIC="$TOPIC" PARTITIONS="$PARTITIONS" "$ROOT/scripts/create-topic.sh"

cleanup() {
  [[ -n "${lag_pid:-}" ]] && kill "$lag_pid" 2>/dev/null || true
  if [[ -n "${cons_runtime:-}" ]] && [[ -f "${cons_runtime}/pids.txt" ]]; then
    while read -r pid; do
      [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    done <"${cons_runtime}/pids.txt"
    rm -f "${cons_runtime}/pids.txt"
  fi
}
trap cleanup EXIT

if [[ "$START_CONSUMER" == 1 ]]; then
  safe_group="${CONSUMER_GROUP//\//_}"
  cons_runtime="${ROOT}/results/runtime/${safe_group}"
  "$ROOT/scripts/start-background-consumer.sh" "$TOPIC" "$CONSUMER_GROUP" 1
  sleep 2
  "$ROOT/scripts/collect-lag.sh" "$TOPIC" "$CONSUMER_GROUP" "$LAG_INTERVAL" "$RESULT_LAG_TS" &
  lag_pid=$!
fi

echo "Running loadgen (mvn exec:java)…"
ARGS_JOINED=$(printf '%s ' "${LOADGEN_ARGS[@]}")
(
  cd "$ROOT/loadgen" && mvn -q exec:java -Dexec.args="$ARGS_JOINED"
)

echo "Done. Lag samples: $RESULT_LAG_TS"
echo "Plot: python3 $ROOT/plots/generate_plots.py"
