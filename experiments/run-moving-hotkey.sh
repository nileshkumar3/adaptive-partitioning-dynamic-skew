#!/usr/bin/env bash
#
# Moving hot-key experiment: one strategy (STRATEGY) or sweep default+adaptive (RUN_ALL_STRATEGIES=1).
# Output: results/moving-hotkey/<YYYYMMDD_HHMMSS>_<pid>_<strategy>/
#   metadata.txt, lag_timeseries.tsv
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

# =============================================================================
# Edit these parameters for paper runs
# =============================================================================

# --- Kafka / topic ---
BOOTSTRAP_SERVERS="${BOOTSTRAP_SERVERS:-localhost:9092}"
TOPIC="${TOPIC:-moving-hotkey}"
PARTITIONS="${PARTITIONS:-6}"
# Fresh consumer group per run avoids mixing lag across sequential strategies
CONSUMER_GROUP_BASE="${CONSUMER_GROUP_BASE:-moving-hotkey}"
LAG_INTERVAL_SEC="${LAG_INTERVAL_SEC:-2}"

# --- Workload (workload/dynamic-skew-generator.java) ---
MESSAGES="${MESSAGES:-500000}"
PHASE_MS="${PHASE_MS:-5000}"
HOT_FRACTION="${HOT_FRACTION:-0.5}"
KEY_SPACE="${KEY_SPACE:-10000}"

# --- Partitioner strategy ---
STRATEGY="${STRATEGY:-adaptive}"
RUN_ALL_STRATEGIES="${RUN_ALL_STRATEGIES:-0}"

# --- AdaptivePartitioner (-D passed to JVM; ignored for STRATEGY=default) ---
ADAPTIVE_ENABLE="${ADAPTIVE_ENABLE:-true}"
ADAPTIVE_WINDOW_MS="${ADAPTIVE_WINDOW_MS:-10000}"
ADAPTIVE_STICKY_TTL_MS="${ADAPTIVE_STICKY_TTL_MS:-30000}"
ADAPTIVE_IMBALANCE_FACTOR="${ADAPTIVE_IMBALANCE_FACTOR:-1.25}"
ADAPTIVE_LOG_ENABLE="${ADAPTIVE_LOG_ENABLE:-false}"
ADAPTIVE_LOG_SUMMARY_MS="${ADAPTIVE_LOG_SUMMARY_MS:-0}"

# --- Infrastructure ---
START_DOCKER="${START_DOCKER:-1}"

# =============================================================================
# Helpers
# =============================================================================

write_metadata() {
  local out_dir="$1"
  local strategy="$2"
  local meta="${out_dir}/metadata.txt"
  local git_commit
  git_commit="$(cd "$ROOT" && git rev-parse HEAD 2>/dev/null || echo "unknown")"
  {
    echo "git_commit=${git_commit}"
    echo "strategy=${strategy}"
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS}"
    echo "topic=${TOPIC}"
    echo "partitions=${PARTITIONS}"
    echo "messages=${MESSAGES}"
    echo "phase_ms=${PHASE_MS}"
    echo "hot_fraction=${HOT_FRACTION}"
    echo "key_space=${KEY_SPACE}"
    echo "adaptive.enable=${ADAPTIVE_ENABLE}"
    echo "adaptive.window.ms=${ADAPTIVE_WINDOW_MS}"
    echo "adaptive.sticky.ttl.ms=${ADAPTIVE_STICKY_TTL_MS}"
    echo "adaptive.imbalance.factor=${ADAPTIVE_IMBALANCE_FACTOR}"
    echo "adaptive.log.enable=${ADAPTIVE_LOG_ENABLE}"
    echo "adaptive.log.summary.ms=${ADAPTIVE_LOG_SUMMARY_MS}"
  } | tee "$meta"
}

build_and_run_producer() {
  local strategy="$1"
  java \
    -cp "${DEP_CP}:${CLASSES}" \
    -Dskew.partitioner="$strategy" \
    -Dadaptive.enable="$ADAPTIVE_ENABLE" \
    -Dadaptive.window.ms="$ADAPTIVE_WINDOW_MS" \
    -Dadaptive.sticky.ttl.ms="$ADAPTIVE_STICKY_TTL_MS" \
    -Dadaptive.imbalance.factor="$ADAPTIVE_IMBALANCE_FACTOR" \
    -Dadaptive.log.enable="$ADAPTIVE_LOG_ENABLE" \
    -Dadaptive.log.summary.ms="$ADAPTIVE_LOG_SUMMARY_MS" \
    workload.DynamicSkewGenerator \
    "$BOOTSTRAP_SERVERS" "$TOPIC" "$MESSAGES" "$PHASE_MS" "$HOT_FRACTION" "$KEY_SPACE"
}

run_one_strategy() {
  local strategy="$1"
  local stamp_base="${2:-$(date +%Y%m%d_%H%M%S)}"
  local STAMP="${stamp_base}_$$"
  local OUT="${ROOT}/results/moving-hotkey/${STAMP}_${strategy}"
  mkdir -p "$OUT"

  local CONSUMER_GROUP="${CONSUMER_GROUP_BASE}-${STAMP}_${strategy}"
  local LAG_FILE="${OUT}/lag_timeseries.tsv"
  local lag_pid="" cons_pid=""

  write_metadata "$OUT" "$strategy"

  cleanup() {
    [[ -n "${lag_pid:-}" ]] && kill "$lag_pid" 2>/dev/null || true
    [[ -n "${cons_pid:-}" ]] && kill "$cons_pid" 2>/dev/null || true
  }
  trap cleanup EXIT

  # Step A: background consumer + lag sampler (isolated group for this strategy)
  TOPIC="$TOPIC" CONSUMER_GROUP="$CONSUMER_GROUP" \
    "$ROOT/scripts/start-background-consumer.sh" &
  cons_pid=$!
  sleep 2
  "$ROOT/scripts/collect-lag.sh" "$CONSUMER_GROUP" "$LAG_INTERVAL_SEC" "$LAG_FILE" &
  lag_pid=$!

  # Step B: producer workload
  build_and_run_producer "$strategy"

  cleanup
  trap - EXIT

  echo ""
  echo "Run finished: ${OUT}"
  echo "  metadata.txt  lag_timeseries.tsv"
  echo "  python3 \"$ROOT/plots/generate_plots.py\" --lag-ts \"$LAG_FILE\" --lag-out \"$OUT/lag.png\""
}

prepare_build() {
  BUILD="$ROOT/build/moving-hotkey"
  CLASSES="$BUILD/classes"
  CP_TXT="$BUILD/cp.txt"
  mkdir -p "$CLASSES"
  (cd "$ROOT/loadgen" && mvn -q dependency:build-classpath -Dmdep.outputFile="$CP_TXT")
  DEP_CP="$(tr -d '\n\r' <"$CP_TXT")"
  javac -cp "$DEP_CP" -d "$CLASSES" \
    "$ROOT/producer/AdaptivePartitioner.java" \
    "$ROOT/workload/dynamic-skew-generator.java"
}

first_broker="${BOOTSTRAP_SERVERS%%,*}"
KAFKA_WAIT_HOST="${first_broker%%:*}"
KAFKA_WAIT_PORT="${first_broker##*:}"

# =============================================================================
# Main: broker + topic once, then one or two strategy runs
# =============================================================================

if [[ "$START_DOCKER" == 1 ]] && [[ -z "${KAFKA_HOME:-}" ]]; then
  "$ROOT/scripts/kafka-setup.sh"
else
  wait_for_kafka "$KAFKA_WAIT_HOST" "$KAFKA_WAIT_PORT" 60
fi

TOPIC="$TOPIC" PARTITIONS="$PARTITIONS" "$ROOT/scripts/create-topic.sh"

prepare_build

if [[ "$RUN_ALL_STRATEGIES" == 1 ]]; then
  run_one_strategy "default" "$(date +%Y%m%d_%H%M%S)"
  sleep 1
  run_one_strategy "adaptive" "$(date +%Y%m%d_%H%M%S)"
else
  run_one_strategy "$STRATEGY" "$(date +%Y%m%d_%H%M%S)"
fi
