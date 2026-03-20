#!/usr/bin/env bash
#
# Main “moving hot key” experiment: rotating hot key every PHASE_MS, optional adaptive partitioner.
# Edit the variables in the next section, then run from anywhere:
#   ./experiments/run-moving-hotkey.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

# --------------------------- edit experiment parameters ---------------------------
BOOTSTRAP_SERVERS="${BOOTSTRAP_SERVERS:-localhost:9092}"
TOPIC="${TOPIC:-moving-hotkey}"
PARTITIONS="${PARTITIONS:-6}"
CONSUMER_GROUP="${CONSUMER_GROUP:-moving-hotkey-consumer}"
LAG_INTERVAL_SEC="${LAG_INTERVAL_SEC:-2}"

# Total produced messages and workload skew (see workload/dynamic-skew-generator.java)
MESSAGES="${MESSAGES:-500000}"
PHASE_MS="${PHASE_MS:-5000}"
HOT_FRACTION="${HOT_FRACTION:-0.5}"
KEY_SPACE="${KEY_SPACE:-10000}"

# default = Kafka built-in partitioner; adaptive = producer.AdaptivePartitioner
STRATEGY="${STRATEGY:-adaptive}"

# JVM flags for AdaptivePartitioner (ignored when STRATEGY=default)
ADAPTIVE_ENABLE="${ADAPTIVE_ENABLE:-true}"
ADAPTIVE_WINDOW_MS="${ADAPTIVE_WINDOW_MS:-10000}"
ADAPTIVE_STICKY_TTL_MS="${ADAPTIVE_STICKY_TTL_MS:-30000}"
ADAPTIVE_IMBALANCE_FACTOR="${ADAPTIVE_IMBALANCE_FACTOR:-1.25}"
# Per-record stderr traces (very verbose); keep false for long runs
ADAPTIVE_LOG_ENABLE="${ADAPTIVE_LOG_ENABLE:-false}"

START_DOCKER="${START_DOCKER:-1}"
# ---------------------------------------------------------------------------------

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="${ROOT}/results/moving-hotkey/${STAMP}_${STRATEGY}"
mkdir -p "$OUT"

META="$OUT/run_config.txt"
{
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "BOOTSTRAP_SERVERS=$BOOTSTRAP_SERVERS"
  echo "TOPIC=$TOPIC PARTITIONS=$PARTITIONS CONSUMER_GROUP=$CONSUMER_GROUP"
  echo "MESSAGES=$MESSAGES PHASE_MS=$PHASE_MS HOT_FRACTION=$HOT_FRACTION KEY_SPACE=$KEY_SPACE"
  echo "STRATEGY=$STRATEGY"
  echo "ADAPTIVE_ENABLE=$ADAPTIVE_ENABLE ADAPTIVE_WINDOW_MS=$ADAPTIVE_WINDOW_MS"
  echo "ADAPTIVE_STICKY_TTL_MS=$ADAPTIVE_STICKY_TTL_MS ADAPTIVE_IMBALANCE_FACTOR=$ADAPTIVE_IMBALANCE_FACTOR"
  echo "ADAPTIVE_LOG_ENABLE=$ADAPTIVE_LOG_ENABLE"
} | tee "$META"

first_broker="${BOOTSTRAP_SERVERS%%,*}"
KAFKA_WAIT_HOST="${first_broker%%:*}"
KAFKA_WAIT_PORT="${first_broker##*:}"

# Step 1: Kafka broker (Docker Compose unless KAFKA_HOME is set)
if [[ "$START_DOCKER" == 1 ]] && [[ -z "${KAFKA_HOME:-}" ]]; then
  "$ROOT/scripts/kafka-setup.sh"
else
  wait_for_kafka "$KAFKA_WAIT_HOST" "$KAFKA_WAIT_PORT" 60
fi

# Step 2: Topic
TOPIC="$TOPIC" PARTITIONS="$PARTITIONS" "$ROOT/scripts/create-topic.sh"

LAG_FILE="$OUT/lag_timeseries.tsv"

cleanup() {
  [[ -n "${lag_pid:-}" ]] && kill "$lag_pid" 2>/dev/null || true
  [[ -n "${cons_pid:-}" ]] && kill "$cons_pid" 2>/dev/null || true
}
trap cleanup EXIT

# Step 3: Background consumer (enables meaningful group lag under load)
TOPIC="$TOPIC" CONSUMER_GROUP="$CONSUMER_GROUP" \
  "$ROOT/scripts/start-background-consumer.sh" &
cons_pid=$!
sleep 2

# Step 4: Lag sampler → results subdirectory
"$ROOT/scripts/collect-lag.sh" "$CONSUMER_GROUP" "$LAG_INTERVAL_SEC" "$LAG_FILE" &
lag_pid=$!

# Step 5: Build classpath (kafka-clients from loadgen POM) and compile producer + workload
BUILD="$ROOT/build/moving-hotkey"
CLASSES="$BUILD/classes"
CP_TXT="$BUILD/cp.txt"
mkdir -p "$CLASSES"
(
  cd "$ROOT/loadgen"
  mvn -q dependency:build-classpath -Dmdep.outputFile="$CP_TXT"
)
DEP_CP="$(tr -d '\n\r' <"$CP_TXT")"
javac -cp "$DEP_CP" -d "$CLASSES" \
  "$ROOT/producer/AdaptivePartitioner.java" \
  "$ROOT/workload/dynamic-skew-generator.java"

# Step 6: Run moving-hot-key producer
java \
  -cp "${DEP_CP}:${CLASSES}" \
  -Dskew.partitioner="$STRATEGY" \
  -Dadaptive.enable="$ADAPTIVE_ENABLE" \
  -Dadaptive.window.ms="$ADAPTIVE_WINDOW_MS" \
  -Dadaptive.sticky.ttl.ms="$ADAPTIVE_STICKY_TTL_MS" \
  -Dadaptive.imbalance.factor="$ADAPTIVE_IMBALANCE_FACTOR" \
  -Dadaptive.log.enable="$ADAPTIVE_LOG_ENABLE" \
  workload.DynamicSkewGenerator \
  "$BOOTSTRAP_SERVERS" "$TOPIC" "$MESSAGES" "$PHASE_MS" "$HOT_FRACTION" "$KEY_SPACE"

# Step 7: tear down background jobs
cleanup
trap - EXIT

echo ""
echo "Artifacts:"
echo "  $META"
echo "  $LAG_FILE"
echo ""
echo "Plot lag (PNG next to run):"
echo "  python3 $ROOT/plots/generate_plots.py --lag-ts \"$LAG_FILE\" --lag-out \"$OUT/lag.png\""
echo "(Throughput plot still uses results/throughput.txt if present.)"
