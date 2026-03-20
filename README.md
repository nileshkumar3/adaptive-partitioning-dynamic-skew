# Adaptive Partitioning under Dynamic Workload Skew in Event-Driven Systems

**Summary:** Research artifact for studying a producer-side adaptive Kafka partitioner under **moving hot keys** and skewed workloads: Docker Kafka, workloads, lag collection, and plots.

## Quickstart

**Prerequisites:** Docker, Java **21+**, Maven, Python **3** + matplotlib.

From the repo root:

```bash
./scripts/kafka-setup.sh
export TOPIC=${TOPIC:-moving-hotkey} PARTITIONS=${PARTITIONS:-6}
./scripts/create-topic.sh
chmod +x experiments/run-moving-hotkey.sh    # once
./experiments/run-moving-hotkey.sh             # or RUN_ALL_STRATEGIES=1 for default + adaptive
```

Then plot using the path the script prints, e.g.:

```bash
python3 plots/generate_plots.py --lag-ts results/moving-hotkey/<run_dir>/lag_timeseries.tsv \
  --lag-out results/moving-hotkey/<run_dir>/lag.png
```

## Reproducible paper run

Run the full sequence in **one shell** (repo root). The broker image defaults to **`apache/kafka:4.0.1`** in `docker-compose.yml`; override with `KAFKA_IMAGE` only if you document it.

```bash
# 1) Broker
./scripts/kafka-setup.sh

# 2) Topic
export TOPIC=${TOPIC:-moving-hotkey} PARTITIONS=${PARTITIONS:-6}
./scripts/create-topic.sh

# 3–4) Moving hot key + consumer + lag (script starts consumer and sampler)
chmod +x experiments/run-moving-hotkey.sh   # once
RUN_ALL_STRATEGIES=1 ./experiments/run-moving-hotkey.sh    # default then adaptive; or STRATEGY=adaptive only

# 5) Plot
python3 plots/generate_plots.py --lag-ts results/moving-hotkey/<run_dir>/lag_timeseries.tsv \
  --lag-out results/moving-hotkey/<run_dir>/lag.png
```

Each run directory has **`metadata.txt`** (`git_commit`, strategy, topic, partitions, workload and adaptive settings) and **`lag_timeseries.tsv`**.

**Paper runs:** keep **`adaptive.log.enable=false`** (default). For aggregate routing lines without per-record spam, set **`adaptive.log.summary.ms`** (e.g. `10000`).

**GitHub:** set the repo **description** and **topics** in **Settings** (not stored in git).

## Repository layout

| Path | Role |
|------|------|
| `producer/AdaptivePartitioner.java` | Custom partitioner: hash when balanced, optional reroute vs window mean; sticky TTL; config window. |
| `workload/dynamic-skew-generator.java` | Moving hot key + skew (`SKEW_PARTITIONER=default\|adaptive`). |
| `loadgen/` | Maven load generator (static skew, throughput / latency stats). |
| `docker-compose.yml` | Single-node KRaft broker (pinned image). |
| `scripts/` | Setup, topic, background consumer, lag sampling. |
| `experiments/` | `run-moving-hotkey.sh`, `run_experiment.sh`, sweeps. |
| `results/` | Example / run outputs (may be committed as samples). |
| `plots/generate_plots.py` | Throughput bar chart; lag series (`--lag-ts` for per-run TSV). |
| `paper/` | LaTeX draft. |

## Reference

`run-moving-hotkey.sh` uses Docker when `START_DOCKER=1` (default) and `KAFKA_HOME` is unset; it compiles `producer/` + `workload/` and writes under **`results/moving-hotkey/<timestamp>_<pid>_<strategy>/`**.

Manual lag sampling:

```bash
./scripts/collect-lag.sh <group_id> 2 results/lag_timeseries.tsv
```

Default plots (throughput + default lag path):

```bash
python3 plots/generate_plots.py
```

## Adaptive partitioner (`adaptive.*`)

Values come from the partitioner **configure** map when present, else **`System.getProperty`** (e.g. `-Dadaptive.window.ms=…` in experiment scripts).

| Key | Meaning |
|-----|---------|
| `adaptive.enable` | `true` / `false` — if `false`, murmur2 (null keys: random). |
| `adaptive.sticky.ttl.ms` | Sticky routing TTL per key. |
| `adaptive.imbalance.factor` | Reroute when hash-partition load `> mean × factor`. |
| `adaptive.window.ms` | Load window length (`≤0` = no epoch reset). |
| `adaptive.log.enable` | Per-record stderr (heavy). |
| `adaptive.log.summary.ms` | If `> 0`, periodic summary line (routes + sticky map size). |

**Caveat:** rerouting weakens strict per-key single-partition ordering.

## License

Artifact code is for research reproduction; cite the paper when using these materials.
