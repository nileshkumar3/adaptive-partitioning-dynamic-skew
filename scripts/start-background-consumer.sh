#!/usr/bin/env bash
# Start one or more kafka-console-consumer.sh processes in the background (local Kafka).
#
# Usage:
#   ./scripts/start-background-consumer.sh TOPIC GROUP_ID [NUM_CONSUMERS]
# Env if args omitted: TOPIC, CONSUMER_GROUP or GROUP_ID
#
# PIDs and logs: results/runtime/<sanitized_group>/
# Stop: ./scripts/stop-runtime-consumers.sh results/runtime/<sanitized_group>
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

kafka_require

TOPIC="${1:-${TOPIC:-}}"
GROUP_ID="${2:-${GROUP_ID:-${CONSUMER_GROUP:-}}}"
NUM_CONSUMERS="${3:-1}"

if [[ -z "$TOPIC" || -z "$GROUP_ID" ]]; then
  echo "usage: $0 TOPIC GROUP_ID [NUM_CONSUMERS]" >&2
  echo "  or set TOPIC and CONSUMER_GROUP (or GROUP_ID)" >&2
  exit 2
fi

safe_group="${GROUP_ID//\//_}"
RUNTIME_DIR="${ROOT}/results/runtime/${safe_group}"
mkdir -p "$RUNTIME_DIR"

: >"${RUNTIME_DIR}/pids.txt"
for ((i = 1; i <= NUM_CONSUMERS; i++)); do
  log="${RUNTIME_DIR}/consumer-${i}.log"
  nohup kafka_console_consumer_sh \
    --topic "$TOPIC" \
    --group "$GROUP_ID" \
    --consumer-property fetch.max.wait.ms=500 \
    >"$log" 2>&1 &
  echo $! >>"${RUNTIME_DIR}/pids.txt"
done

echo "Started ${NUM_CONSUMERS} console consumer(s) for topic=$TOPIC group=$GROUP_ID"
echo "  PIDs: ${RUNTIME_DIR}/pids.txt"
echo "  Logs: ${RUNTIME_DIR}/consumer-*.log"
