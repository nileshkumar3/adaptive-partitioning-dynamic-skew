#!/usr/bin/env bash
# End-to-end experiment: optional Docker Kafka → topic → background consumer + lag sampler → loadgen.
# Usage:
#   experiments/run_experiment.sh [--no-docker] [--no-consumer] loadgen_key=value ...
# Example:
#   experiments/run_experiment.sh bootstrap=localhost:9092 topic=skew-topic mode=DEDICATED threads=2 messagesPerSecond=50000 payloadSize=512 hotRatio=0.2 warmupSec=10 runSec=120
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

START_DOCKER=1
START_CONSUMER=1
LOADGEN_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-docker) START_DOCKER=0; shift ;;
    --no-consumer) START_CONSUMER=0; shift ;;
    *) LOADGEN_ARGS+=("$1"); shift ;;
  esac
done

: "${TOPIC:=skew-topic}"
: "${CONSUMER_GROUP:=skew-consumer}"
: "${LAG_INTERVAL:=2}"
: "${RESULT_LAG_TS:=$ROOT/results/lag_timeseries.tsv}"

first_broker="${BOOTSTRAP_SERVERS%%,*}"
KAFKA_WAIT_HOST="${first_broker%%:*}"
KAFKA_WAIT_PORT="${first_broker##*:}"

if [[ ${#LOADGEN_ARGS[@]} -eq 0 ]]; then
  echo "usage: $0 [--no-docker] [--no-consumer] bootstrap=... topic=... mode=DEDICATED threads=... messagesPerSecond=... payloadSize=... hotRatio=... warmupSec=... runSec=..." >&2
  exit 2
fi

if [[ "$START_DOCKER" == 1 ]] && [[ -z "${KAFKA_HOME:-}" ]]; then
  "$ROOT/scripts/kafka-setup.sh"
else
  wait_for_kafka "$KAFKA_WAIT_HOST" "$KAFKA_WAIT_PORT" 60
fi

TOPIC="$TOPIC" "$ROOT/scripts/create-topic.sh"

cleanup() {
  [[ -n "${lag_pid:-}" ]] && kill "$lag_pid" 2>/dev/null || true
  [[ -n "${cons_pid:-}" ]] && kill "$cons_pid" 2>/dev/null || true
}
trap cleanup EXIT

if [[ "$START_CONSUMER" == 1 ]]; then
  # Consumer runs inside/host via lib; background to let lag build under producer rate.
  TOPIC="$TOPIC" CONSUMER_GROUP="$CONSUMER_GROUP" \
    "$ROOT/scripts/start-background-consumer.sh" &
  cons_pid=$!
  sleep 2
  "$ROOT/scripts/collect-lag.sh" "$CONSUMER_GROUP" "$LAG_INTERVAL" "$RESULT_LAG_TS" &
  lag_pid=$!
fi

echo "Running loadgen (mvn exec:java)…"
ARGS_JOINED=$(printf '%s ' "${LOADGEN_ARGS[@]}")
(
  cd "$ROOT/loadgen" && mvn -q exec:java -Dexec.args="$ARGS_JOINED"
)

echo "Done. Lag samples: $RESULT_LAG_TS"
echo "Plot: python3 $ROOT/plots/generate_plots.py"
