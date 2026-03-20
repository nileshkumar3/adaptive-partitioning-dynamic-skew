#!/usr/bin/env bash
# Run a slow console consumer so consumer-group LAG is measurable under load.
# Runs in foreground by default; use nohup or run_experiment.sh for background.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

: "${TOPIC:=skew-topic}"
: "${CONSUMER_GROUP:=skew-consumer}"

exec kafka_console_consumer_sh \
  --topic "$TOPIC" \
  --group "$CONSUMER_GROUP" \
  --consumer-property fetch.max.wait.ms=500 \
  "$@"
