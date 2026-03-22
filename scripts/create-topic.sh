#!/usr/bin/env bash
# Create a topic with local Kafka CLI (replication factor 1 by default).
#
# Usage:
#   ./scripts/create-topic.sh [TOPIC] [PARTITIONS]
# Env (used if args omitted): TOPIC, PARTITIONS, REPLICATION_FACTOR, BOOTSTRAP_SERVERS, KAFKA_HOME
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

kafka_require

TOPIC="${1:-${TOPIC:-moving-hotkey}}"
PARTITIONS="${2:-${PARTITIONS:-6}}"
: "${REPLICATION_FACTOR:=1}"

if kafka_topics_sh --describe --topic "$TOPIC" &>/dev/null; then
  echo "Topic '$TOPIC' already exists — skipping create."
  exit 0
fi

kafka_topics_sh \
  --create \
  --topic "$TOPIC" \
  --partitions "$PARTITIONS" \
  --replication-factor "$REPLICATION_FACTOR"

echo "Created topic '$TOPIC' ($PARTITIONS partitions, replication=$REPLICATION_FACTOR) on $BOOTSTRAP_SERVERS"
