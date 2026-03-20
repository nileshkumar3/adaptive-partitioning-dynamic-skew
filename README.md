# Adaptive Partitioning under Dynamic Workload Skew in Event-Driven Systems

Research artifact for the paper **“Adaptive Partitioning under Dynamic Workload Skew in Event-Driven Systems”**: a minimal Kafka producer partitioner that reacts to **short-window** load imbalance, a moving–hot-key workload, scripts to run Kafka locally, collect consumer-group lag, and plot results.

## Repository layout

| Path | Role |
|------|------|
| `producer/AdaptivePartitioner.java` | Custom `Partitioner`: hash routing when balanced, optional reroute when the hash partition is hot vs. recent mean; sticky TTL; configurable window. |
| `workload/dynamic-skew-generator.java` | Moving hot key + configurable skew (phase length, hot fraction); `SKEW_PARTITIONER=default\|adaptive`. |
| `loadgen/` | Maven throughput/latency load generator (skewed keys, dedicated vs random mode) for additional baselines. |
| `docker-compose.yml` | Single-node KRaft broker (image version pinned). |
| `scripts/` | Kafka setup, topic creation, background consumer, lag sampling. |
| `experiments/` | `run-moving-hotkey.sh`, `run_experiment.sh`, sweeps. |
| `results/` | Example / run outputs (lag TSV, throughput tables). |
| `plots/generate_plots.py` | Bar chart for `throughput.txt`; time series for `lag_timeseries.tsv` (use `--lag-ts` for per-run files). |
| `paper/` | LaTeX draft. |

## Reproducible paper run

Use the **same** shell for the sequence below (from the repository root). The broker image is **pinned** in `docker-compose.yml`; override only if you document the alternative.

```bash
# 1) Broker
./scripts/kafka-setup.sh

# 2) Topic
export TOPIC=${TOPIC:-moving-hotkey} PARTITIONS=${PARTITIONS:-6}
./scripts/create-topic.sh

# 3–4) Moving–hot-key load + consumer + lag (script starts consumer and sampler)
chmod +x experiments/run-moving-hotkey.sh   # once
RUN_ALL_STRATEGIES=1 ./experiments/run-moving-hotkey.sh   # default then adaptive; or STRATEGY=adaptive only

# 5) Plot (use the path printed at end of the run, or list results/moving-hotkey/)
python3 plots/generate_plots.py --lag-ts results/moving-hotkey/<run_dir>/lag_timeseries.tsv \
  --lag-out results/moving-hotkey/<run_dir>/lag.png
```

Each run directory includes **`metadata.txt`** (`git_commit`, strategy, topic, partitions, workload and adaptive settings) and **`lag_timeseries.tsv`**.

**GitHub:** set the repository **description** and **topics** in the GitHub UI (not stored in git).

## Quickstart (reference)

**Prerequisites:** Docker (for broker), Java 21+ and Maven (for classpath + `loadgen`), Python 3 + matplotlib for plots.

`run-moving-hotkey.sh` starts Kafka only if `START_DOCKER=1` (default) and `KAFKA_HOME` is unset; it creates the topic, compiles `producer/` + `workload/`, runs the moving-hot-key driver, and writes under `results/moving-hotkey/`.

Manual lag sampling if needed:

```bash
./scripts/collect-lag.sh <group_id> 2 results/lag_timeseries.tsv
```

Default throughput + lag overview:

```bash
python3 plots/generate_plots.py
```

## Adaptive partitioner configuration

`AdaptivePartitioner` reads **`adaptive.*` from the partitioner `configure` map when Kafka forwards those entries, and otherwise from Java system properties** (recommended for runs: `-Dadaptive.window.ms=…`).

| Key | Meaning |
|-----|---------|
| `adaptive.enable` | `true` / `false` — if `false`, murmur2 routing (null keys: random). |
| `adaptive.sticky.ttl.ms` | How long a key stays pinned to a chosen partition. |
| `adaptive.imbalance.factor` | Reroute if hash-partition window load `> mean × factor`. |
| `adaptive.window.ms` | Sliding window length for load counters (`≤0` = never reset). |
| `adaptive.log.enable` | `true` prints one stderr line per record (heavy); use short runs only. |
| `adaptive.log.summary.ms` | If `> 0`, one stderr **summary** line per interval (route counts + sticky map size); use instead of per-record logs for long runs. |

**Paper caveat:** rerouting breaks strict single-partition ordering per key; sticky TTL trades skew vs. ordering.

## License

Artifact code is for research reproduction; cite the paper when using these materials.
