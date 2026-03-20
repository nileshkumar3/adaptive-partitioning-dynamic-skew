#!/usr/bin/env bash
# Create (or reassign) a topic for experiments.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

: "${TOPIC:=skew-topic}"
: "${PARTITIONS:=6}"
: "${REPLICATION_FACTOR:=1}"

kafka_topics_sh \
  --create \
  --if-not-exists \
  --topic "$TOPIC" \
  --partitions "$PARTITIONS" \
  --replication-factor "$REPLICATION_FACTOR"
echo "Topic $TOPIC ready ($PARTITIONS partitions, RF=$REPLICATION_FACTOR)"
