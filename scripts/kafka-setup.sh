#!/usr/bin/env bash
# Start single-node Kafka via Docker Compose, or verify a host broker is up.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

if [[ "${1:-}" == "down" ]]; then
  docker compose --project-directory "$ROOT" -f "$ROOT/docker-compose.yml" down
  exit 0
fi

if [[ -n "${KAFKA_HOME:-}" ]]; then
  echo "KAFKA_HOME is set; skipping Docker. Ensure Kafka is listening on $BOOTSTRAP_SERVERS"
  wait_for_kafka localhost "${BOOTSTRAP_SERVERS##*:}" 60
  exit 0
fi

echo "Starting Kafka broker (Docker)…"
docker compose --project-directory "$ROOT" -f "$ROOT/docker-compose.yml" up -d
wait_for_kafka localhost 9092 90
echo "Kafka is up on $BOOTSTRAP_SERVERS"
