# Shared helpers for local Kafka CLI ($KAFKA_HOME/bin/*).
# shellcheck shell=bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Defaults (override with export before sourcing or running scripts)
: "${KAFKA_HOME:=/Users/nilesh/kafka-lab/kafka_2.13-4.0.1}"
: "${BOOTSTRAP_SERVERS:=localhost:9092}"

# Optional alias used in docs
if [[ -n "${BOOTSTRAP_SERVER:-}" ]]; then
  BOOTSTRAP_SERVERS="$BOOTSTRAP_SERVER"
fi

kafka_require() {
  local topics_bin="${KAFKA_HOME}/bin/kafka-topics.sh"
  if [[ ! -f "$topics_bin" ]]; then
    echo "error: Kafka CLI not found at $topics_bin" >&2
    echo "  Set KAFKA_HOME to your Kafka install (e.g. export KAFKA_HOME=/path/to/kafka_2.13-4.0.1)" >&2
    exit 1
  fi
}

kafka_topics_sh() {
  kafka_require
  "${KAFKA_HOME}/bin/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP_SERVERS" "$@"
}

kafka_groups_sh() {
  kafka_require
  "${KAFKA_HOME}/bin/kafka-consumer-groups.sh" --bootstrap-server "$BOOTSTRAP_SERVERS" "$@"
}

kafka_console_consumer_sh() {
  kafka_require
  "${KAFKA_HOME}/bin/kafka-console-consumer.sh" --bootstrap-server "$BOOTSTRAP_SERVERS" "$@"
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
  echo "error: timeout waiting for broker $host:$port (is Kafka running?)" >&2
  return 1
}
