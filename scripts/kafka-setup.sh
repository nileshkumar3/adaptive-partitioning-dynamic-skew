#!/usr/bin/env bash
# Wait until local Kafka accepts connections on BOOTSTRAP_SERVERS (no Docker).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

kafka_require

first="${BOOTSTRAP_SERVERS%%,*}"
host="${first%%:*}"
port="${first##*:}"

echo "Using KAFKA_HOME=$KAFKA_HOME"
echo "Waiting for broker $host:$port …"
wait_for_kafka "$host" "$port" 90
echo "Broker reachable at $BOOTSTRAP_SERVERS"
