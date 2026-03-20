# Adaptive Partitioning under Dynamic Workload Skew in Event-Driven Systems

**Summary:** Research artifact for a producer-side adaptive Kafka partitioner under **moving hot keys** and skewed workloads—Docker broker, workloads, consumer lag samples, and plots.

## Quickstart

**Prerequisites:** Docker, Java **21+**, Maven, Python **3**, matplotlib.

From the repository root:

```bash
./scripts/kafka-setup.sh

export TOPIC=${TOPIC:-moving-hotkey}
export PARTITIONS=${PARTITIONS:-6}
./scripts/create-topic.sh

chmod +x experiments/run-moving-hotkey.sh   # once
./experiments/run-moving-hotkey.sh
# Optional sweep (default partitioner, then adaptive):
# RUN_ALL_STRATEGIES=1 ./experiments/run-moving-hotkey.sh
```

Plot using the path the script prints (replace `<run_dir>`):

```bash
python3 plots/generate_plots.py \
  --lag-ts results/moving-hotkey/<run_dir>/lag_timeseries.tsv \
  --lag-out results/moving-hotkey/<run_dir>/lag.png
```

## Reproducible paper run

Run these steps **in order** in **one shell** from the repo root.

1. **Broker** — Image is pinned in `docker-compose.yml` (`apache/kafka:4.0.1` by default). Override with `KAFKA_IMAGE` only if you document it.

   ```bash
   ./scripts/kafka-setup.sh
   ```

2. **Topic**

   ```bash
   export TOPIC=${TOPIC:-moving-hotkey}
   export PARTITIONS=${PARTITIONS:-6}
   ./scripts/create-topic.sh
   ```

3. **Experiment** — Starts background consumer, lag sampler, and producer (writes under `results/moving-hotkey/`).

   ```bash
   chmod +x experiments/run-moving-hotkey.sh   # once

   # Single strategy (see STRATEGY in the script):
   ./experiments/run-moving-hotkey.sh

   # Or both default and adaptive, separate result dirs:
   RUN_ALL_STRATEGIES=1 ./experiments/run-moving-hotkey.sh
   ```

4. **Plots**

   ```bash
   python3 plots/generate_plots.py \
     --lag-ts results/moving-hotkey/<run_dir>/lag_timeseries.tsv \
     --lag-out results/moving-hotkey/<run_dir>/lag.png
   ```

**Outputs:** Each run directory contains `metadata.txt` (e.g. `git_commit`, strategy, topic, workload and adaptive settings) and `lag_timeseries.tsv`.

**Paper runs:** Keep `adaptive.log.enable=false` (default). For periodic routing aggregates without per-record stderr, set `adaptive.log.summary.ms` (e.g. `10000`).

**GitHub:** Set the repository description and topics in the web UI (not stored in git).

## Repository layout

| Path | Role |
|------|------|
| `producer/AdaptivePartitioner.java` | Custom partitioner: hash when balanced; optional reroute; sticky TTL; windowed load. |
| `workload/dynamic-skew-generator.java` | Moving hot key workload (`SKEW_PARTITIONER=default\|adaptive`). |
| `loadgen/` | Maven load generator (static skew; throughput / latency stats). |
| `docker-compose.yml` | Single-node KRaft broker (pinned image). |
| `scripts/` | Broker setup, topic, background consumer, lag sampling. |
| `experiments/` | `run-moving-hotkey.sh`, `run_experiment.sh`, sweeps. |
| `results/` | Example or run outputs (sample files may be committed). |
| `plots/generate_plots.py` | Throughput chart; lag series (`--lag-ts` for a specific TSV). |
| `paper/` | LaTeX draft. |

## Reference

- `experiments/run-moving-hotkey.sh` uses Docker when `START_DOCKER=1` (default) and `KAFKA_HOME` is unset; compiles `producer/` and `workload/`; writes to `results/moving-hotkey/<timestamp>_<pid>_<strategy>/`.

Manual lag sampling:

```bash
./scripts/collect-lag.sh <group_id> 2 results/lag_timeseries.tsv
```

All default plot inputs:

```bash
python3 plots/generate_plots.py
```

## Adaptive partitioner (`adaptive.*`)

Values: partitioner `configure` map when Kafka forwards them, else `System.getProperty` (e.g. `-Dadaptive.window.ms=…` from experiment scripts).

| Key | Meaning |
|-----|---------|
| `adaptive.enable` | `true` / `false`. If `false`, murmur2 (null keys: random). |
| `adaptive.sticky.ttl.ms` | Sticky routing TTL per key. |
| `adaptive.imbalance.factor` | Reroute when hash-partition load `> mean × factor`. |
| `adaptive.window.ms` | Load window length (`≤0` = no epoch reset). |
| `adaptive.log.enable` | Per-record stderr (heavy). |
| `adaptive.log.summary.ms` | If `> 0`, periodic summary line (routes + sticky map size). |

**Caveat:** Rerouting weakens strict per-key single-partition ordering.

## License

Artifact code is for research reproduction; cite the paper when using these materials.
