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

## Quickstart

**Prerequisites:** Docker (for broker), Java 21+ and Maven (for classpath + `loadgen`), Python 3 + matplotlib for plots.

### 1. Start Kafka

```bash
./scripts/kafka-setup.sh
```

Uses `docker-compose.yml` (override with `KAFKA_HOME` and existing broker if you prefer).

### 2. Create a topic

```bash
export TOPIC=skew-topic PARTITIONS=6
./scripts/create-topic.sh
```

### 3. Background consumer (for lag)

In one terminal (or let `run-moving-hotkey` start it):

```bash
export TOPIC=skew-topic CONSUMER_GROUP=skew-consumer
./scripts/start-background-consumer.sh
```

### 4. Moving hot key experiment

```bash
chmod +x experiments/run-moving-hotkey.sh   # once
./experiments/run-moving-hotkey.sh
```

Tune parameters at the top of `experiments/run-moving-hotkey.sh` (message count, phase, hot fraction, `STRATEGY=default|adaptive`, adaptive `-D` flags). Each run writes under `results/moving-hotkey/<timestamp>_<strategy>/`.

### 5. Collect results

`run-moving-hotkey.sh` records `run_config.txt` and `lag_timeseries.tsv` in that directory. For manual lag sampling:

```bash
./scripts/collect-lag.sh <group_id> 2 results/lag_timeseries.tsv
```

### 6. Plots

```bash
python3 plots/generate_plots.py
# Or for one experiment run:
python3 plots/generate_plots.py --lag-ts results/moving-hotkey/<run>/lag_timeseries.tsv --lag-out results/moving-hotkey/<run>/lag.png
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

**Paper caveat:** rerouting breaks strict single-partition ordering per key; sticky TTL trades skew vs. ordering.

## License

Artifact code is for research reproduction; cite the paper when using these materials.
