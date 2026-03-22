# Adaptive Partitioning under Dynamic Workload Skew in Event-Driven Systems

**Summary:** Research artifact for a producer-side adaptive Kafka partitioner under **moving hot keys** and skewed workloads: local (or Docker) broker, workloads, consumer lag samples, and plots.

---

## Local Kafka setup

Experiments use the **Kafka command-line tools** from a normal binary install (no Docker required).

| Variable | Default | Purpose |
|----------|---------|---------|
| `KAFKA_HOME` | `/Users/nilesh/kafka-lab/kafka_2.13-4.0.1` | Root of your Kafka tarball (must contain `bin/kafka-topics.sh`, etc.) |
| `BOOTSTRAP_SERVERS` | `localhost:9092` | Broker list for CLI and clients |
| `BOOTSTRAP_SERVER` | _(unset)_ | Optional single-broker alias; if set, overrides `BOOTSTRAP_SERVERS` |

Start your broker (e.g. KRaft) so it listens on the bootstrap you configure, then:

```bash
export KAFKA_HOME=/path/to/kafka_2.13-4.0.1   # optional if default matches your machine
export BOOTSTRAP_SERVERS=localhost:9092      # optional
./scripts/kafka-setup.sh                     # waits until the port is open
```

Scripts validate that `$KAFKA_HOME/bin/kafka-topics.sh` exists before running CLI commands.

---

## Quickstart (local broker)

**Prerequisites:** Java **21+**, Maven, Python **3**, matplotlib; **nc** (netcat) for `kafka-setup.sh`; a running Kafka on your bootstrap.

From the repository root:

```bash
./scripts/kafka-setup.sh

./scripts/create-topic.sh moving-hotkey 6

chmod +x experiments/run-moving-hotkey.sh   # once
./experiments/run-moving-hotkey.sh

# Optional: default partitioner, then adaptive (separate result dirs)
# RUN_ALL_STRATEGIES=1 ./experiments/run-moving-hotkey.sh
```

Replace `<run_dir>` with the path the script prints:

```bash
python3 plots/generate_plots.py \
  --lag-ts results/moving-hotkey/<run_dir>/lag_timeseries.tsv \
  --lag-out results/moving-hotkey/<run_dir>/lag.png
```

---

## Helper scripts

| Script | Usage |
|--------|--------|
| Create topic | `./scripts/create-topic.sh [TOPIC] [PARTITIONS]` — env: `TOPIC`, `PARTITIONS`, `REPLICATION_FACTOR` (default 1). Idempotent if the topic exists. |
| Background consumers | `./scripts/start-background-consumer.sh TOPIC GROUP_ID [NUM_CONSUMERS]` — logs and PIDs under `results/runtime/<group>/`. |
| Stop consumers | `./scripts/stop-runtime-consumers.sh results/runtime/<group>` |
| Lag samples | `./scripts/collect-lag.sh TOPIC GROUP_ID [INTERVAL_SECONDS] [OUTFILE]` — default interval 5s; TSV with `unix_ts`, `iso_utc`, `total_lag`, … until Ctrl+C. |

---

## Reproducible paper run

Run **in order** in **one shell** from the repo root.

### 1. Broker

Ensure Kafka is up on `BOOTSTRAP_SERVERS`, then:

```bash
./scripts/kafka-setup.sh
```

*(Optional Docker workflow: `docker-compose` is still in the repo if you prefer a containerized broker; scripts do **not** invoke Docker.)*

### 2. Topic

```bash
./scripts/create-topic.sh "${TOPIC:-moving-hotkey}" "${PARTITIONS:-6}"
```

### 3. Experiment

Starts background consumer, lag sampler, and producer. Writes under `results/moving-hotkey/` (or `OUT_DIR` if set).

```bash
chmod +x experiments/run-moving-hotkey.sh   # once

# Single strategy (see STRATEGY in script)
./experiments/run-moving-hotkey.sh

# Or: default then adaptive, separate result dirs
RUN_ALL_STRATEGIES=1 ./experiments/run-moving-hotkey.sh
```

Useful environment overrides include: `STRATEGY`, `TOPIC`, `GROUP_ID` / `CONSUMER_GROUP_BASE`, `MESSAGES` (or `MSG_RATE` as an alias for the same total-count knob), `HOT_FRACTION`, `PHASE_MS`, `OUT_DIR`, `ADAPTIVE_ENABLE`, `ADAPTIVE_LOG_ENABLE`, `LAG_INTERVAL_SEC`.

### 4. Plots

```bash
python3 plots/generate_plots.py \
  --lag-ts results/moving-hotkey/<run_dir>/lag_timeseries.tsv \
  --lag-out results/moving-hotkey/<run_dir>/lag.png
```

**Outputs:** Each run directory has `metadata.txt` (e.g. `git_commit`, strategy, topic, workload and adaptive settings) and `lag_timeseries.tsv`.

**Paper runs:** Keep `adaptive.log.enable=false` (default). For periodic routing aggregates without per-record stderr, set `adaptive.log.summary.ms` (e.g. `10000`).

**GitHub:** Set repository description and topics in the web UI (not stored in git).

---

## Repository layout

| Path | Role |
|------|------|
| `producer/AdaptivePartitioner.java` | Custom partitioner: hash when balanced; optional reroute; sticky TTL; windowed load. |
| `workload/dynamic-skew-generator.java` | Moving hot key workload (`SKEW_PARTITIONER=default\|adaptive`). |
| `loadgen/` | Maven load generator (static skew; throughput / latency stats). |
| `docker-compose.yml` | Optional single-node KRaft broker (pinned image). |
| `scripts/` | Broker wait, topic, background consumer, lag sampling. |
| `experiments/` | `run-moving-hotkey.sh`, `run_experiment.sh`, sweeps. |
| `results/` | Example or run outputs (sample files may be committed). |
| `plots/generate_plots.py` | Throughput chart; lag series (`--lag-ts` for a specific TSV). |
| `paper/` | LaTeX draft. |

---

## Reference

`experiments/run-moving-hotkey.sh` runs `kafka-setup.sh`, creates the topic, compiles `producer/` and `workload/`, and writes to `results/moving-hotkey/<timestamp>_<pid>_<strategy>/` (unless `OUT_DIR` is set).

**Loadgen + lag (`run_experiment.sh`):**

```bash
experiments/run_experiment.sh bootstrap=localhost:9092 topic=skew-topic mode=DEDICATED threads=2 messagesPerSecond=50000 payloadSize=512 hotRatio=0.2 warmupSec=10 runSec=120
```

**Default plot inputs:**

```bash
python3 plots/generate_plots.py
```

---

## Adaptive partitioner (`adaptive.*`)

Values come from the partitioner `configure` map when Kafka forwards them, else `System.getProperty` (e.g. `-Dadaptive.window.ms=…` in experiment scripts).

| Key | Meaning |
|-----|---------|
| `adaptive.enable` | `true` / `false`. If `false`, murmur2 (null keys: random). |
| `adaptive.sticky.ttl.ms` | Sticky routing TTL per key. |
| `adaptive.imbalance.factor` | Reroute when hash-partition load `> mean × factor`. |
| `adaptive.window.ms` | Load window length (`≤0` = no epoch reset). |
| `adaptive.log.enable` | Per-record stderr (heavy). |
| `adaptive.log.summary.ms` | If `> 0`, periodic summary line (routes + sticky map size). |

**Caveat:** Rerouting weakens strict per-key single-partition ordering.

---

## License

Artifact code is for research reproduction; cite the paper when using these materials.
