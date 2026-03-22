#!/usr/bin/env bash
#
# Moving hot-key experiment.
#
# - One strategy: set STRATEGY (default | adaptive).
# - Sweep: RUN_ALL_STRATEGIES=1 runs default then adaptive (separate result dirs).
#
# Results (per run):
#   results/moving-hotkey/<YYYYMMDD_HHMMSS>_<pid>_<strategy>/
#     metadata.txt
#     lag_timeseries.tsv
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"

kafka_require

# =============================================================================
# Settings (one assignment per line; edit for paper runs)
# =============================================================================

# --- Kafka / topic (BOOTSTRAP_* defaults live in scripts/lib.sh) ---
TOPIC="${TOPIC:-moving-hotkey}"
PARTITIONS="${PARTITIONS:-6}"
CONSUMER_GROUP_BASE="${CONSUMER_GROUP_BASE:-${GROUP_ID:-moving-hotkey}}"
LAG_INTERVAL_SEC="${LAG_INTERVAL_SEC:-2}"

# --- Workload (workload/dynamic-skew-generator.java) ---
MESSAGES="${MESSAGES:-${MSG_RATE:-500000}}"
PHASE_MS="${PHASE_MS:-5000}"
HOT_FRACTION="${HOT_FRACTION:-0.5}"
KEY_SPACE="${KEY_SPACE:-10000}"

# --- Partitioner strategy ---
STRATEGY="${STRATEGY:-adaptive}"
RUN_ALL_STRATEGIES="${RUN_ALL_STRATEGIES:-0}"

# --- AdaptivePartitioner (JVM -D; ignored when STRATEGY=default) ---
ADAPTIVE_ENABLE="${ADAPTIVE_ENABLE:-true}"
ADAPTIVE_WINDOW_MS="${ADAPTIVE_WINDOW_MS:-10000}"
ADAPTIVE_STICKY_TTL_MS="${ADAPTIVE_STICKY_TTL_MS:-30000}"
ADAPTIVE_IMBALANCE_FACTOR="${ADAPTIVE_IMBALANCE_FACTOR:-1.25}"
ADAPTIVE_LOG_ENABLE="${ADAPTIVE_LOG_ENABLE:-false}"
ADAPTIVE_LOG_SUMMARY_MS="${ADAPTIVE_LOG_SUMMARY_MS:-0}"

# --- Output root (optional) ---
RESULTS_PARENT="${OUT_DIR:-$ROOT/results/moving-hotkey}"

# =============================================================================
# Metadata (writes metadata.txt)
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
    echo "KAFKA_HOME=${KAFKA_HOME}"
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

# =============================================================================
# Build and producer execution
# =============================================================================

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

# =============================================================================
# One strategy: consumer + lag file + producer + teardown (results on disk)
# =============================================================================

run_one_strategy() {
  local strategy="$1"
  local stamp_base="${2:-$(date +%Y%m%d_%H%M%S)}"
  local STAMP="${stamp_base}_$$"
  local OUT="${RESULTS_PARENT}/${STAMP}_${strategy}"
  mkdir -p "$OUT"

  local CONSUMER_GROUP="${CONSUMER_GROUP_BASE}-${STAMP}_${strategy}"
  local LAG_FILE="${OUT}/lag_timeseries.tsv"
  local lag_pid=""
  local safe_group="${CONSUMER_GROUP//\//_}"
  local cons_runtime="${ROOT}/results/runtime/${safe_group}"

  write_metadata "$OUT" "$strategy"

  cleanup() {
    [[ -n "${lag_pid:-}" ]] && kill "$lag_pid" 2>/dev/null || true
    if [[ -f "${cons_runtime}/pids.txt" ]]; then
      while read -r pid; do
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
      done <"${cons_runtime}/pids.txt"
      rm -f "${cons_runtime}/pids.txt"
    fi
  }
  trap cleanup EXIT

  "$ROOT/scripts/start-background-consumer.sh" "$TOPIC" "$CONSUMER_GROUP" 1
  sleep 2
  "$ROOT/scripts/collect-lag.sh" "$TOPIC" "$CONSUMER_GROUP" "$LAG_INTERVAL_SEC" "$LAG_FILE" &
  lag_pid=$!

  build_and_run_producer "$strategy"

  cleanup
  trap - EXIT

  echo ""
  echo "Run finished: ${OUT}"
  echo "  metadata.txt"
  echo "  lag_timeseries.tsv"
  echo "  python3 \"$ROOT/plots/generate_plots.py\" --lag-ts \"$LAG_FILE\" --lag-out \"$OUT/lag.png\""
}

# =============================================================================
# Setup: broker, topic, compile — then run experiment(s)
# =============================================================================

"$ROOT/scripts/kafka-setup.sh"

TOPIC="$TOPIC" PARTITIONS="$PARTITIONS" "$ROOT/scripts/create-topic.sh"

prepare_build

if [[ "$RUN_ALL_STRATEGIES" == 1 ]]; then
  run_one_strategy "default" "$(date +%Y%m%d_%H%M%S)"
  sleep 1
  run_one_strategy "adaptive" "$(date +%Y%m%d_%H%M%S)"
else
  run_one_strategy "$STRATEGY" "$(date +%Y%m%d_%H%M%S)"
fi
