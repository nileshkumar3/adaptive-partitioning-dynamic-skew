# Shared helpers for Kafka CLI (host install vs Docker broker container).
# shellcheck shell=bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${BOOTSTRAP_SERVERS:=localhost:9092}"
: "${KAFKA_CONTAINER:=${KAFKA_CONTAINER_NAME:-apskew-broker}}"

kafka_bootstrap_for_cli() {
  if [[ -n "${KAFKA_HOME:-}" ]]; then
    echo "$BOOTSTRAP_SERVERS"
  else
    echo "broker:19092"
  fi
}

kafka_topics_sh() {
  local bs
  bs="$(kafka_bootstrap_for_cli)"
  if [[ -n "${KAFKA_HOME:-}" ]]; then
    "$KAFKA_HOME/bin/kafka-topics.sh" --bootstrap-server "$bs" "$@"
  else
    docker exec "$KAFKA_CONTAINER" /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$bs" "$@"
  fi
}

kafka_groups_sh() {
  local bs
  bs="$(kafka_bootstrap_for_cli)"
  if [[ -n "${KAFKA_HOME:-}" ]]; then
    "$KAFKA_HOME/bin/kafka-consumer-groups.sh" --bootstrap-server "$bs" "$@"
  else
    docker exec "$KAFKA_CONTAINER" /opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server "$bs" "$@"
  fi
}

kafka_console_consumer_sh() {
  local bs
  bs="$(kafka_bootstrap_for_cli)"
  if [[ -n "${KAFKA_HOME:-}" ]]; then
    "$KAFKA_HOME/bin/kafka-console-consumer.sh" --bootstrap-server "$bs" "$@"
  else
    docker exec "$KAFKA_CONTAINER" /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server "$bs" "$@"
  fi
}

wait_for_kafka() {
  local host="${1:-localhost}"
  local port="${2:-9092}"
  local tries="${3:-60}"
  local i=0
  while [[ $i -lt $tries ]]; do
    if command -v nc >/dev/null 2>&1 && nc -z "$host" "$port" 2>/dev/null; then
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  echo "timeout waiting for $host:$port" >&2
  return 1
}
