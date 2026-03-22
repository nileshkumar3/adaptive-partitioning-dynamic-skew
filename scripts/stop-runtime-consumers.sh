#!/usr/bin/env bash
# Kill consumers started by start-background-consumer.sh (reads pids.txt).
# Usage: ./scripts/stop-runtime-consumers.sh results/runtime/<sanitized_group>
set -euo pipefail
DIR="${1:?path to results/runtime/<group> directory}"
PIDFILE="${DIR}/pids.txt"
if [[ ! -f "$PIDFILE" ]]; then
  echo "no pids file: $PIDFILE" >&2
  exit 1
fi
while read -r pid; do
  [[ -z "$pid" ]] && continue
  kill "$pid" 2>/dev/null || true
done <"$PIDFILE"
echo "Stopped consumers listed in $PIDFILE"
rm -f "$PIDFILE"
