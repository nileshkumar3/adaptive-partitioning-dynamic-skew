# Load generator (Kafka producer)

This module supports experiments for **Adaptive Partitioning under Dynamic Workload Skew in Event-Driven Systems**. It is a **multi-threaded, rate-controlled** producer that reports **throughput and producer-side acknowledgment latencies** (p50 / p95 / p99).

## What it models

- **Dedicated mode (`mode=DEDICATED`)** — messages carry **synthetic keys**. With `hotRatio>0`, keys follow a **skewed distribution**: a fixed hot key (`HOT`) receives that fraction of traffic; the rest are spread across a large key space (`COLD-*`). This captures **static skew** (one persistent hot key).
- **Random mode (`mode=RANDOM`)** — uses `RandomPartitioner` with **null keys** so records spread randomly across partitions (useful as a spread baseline).

For **dynamic skew** where the hot key **moves over time** (the paper’s moving–hot-key scenario), use the standalone driver in the repo root: **`workload/dynamic-skew-generator.java`** with `SKEW_PARTITIONER=default|adaptive`, or `./experiments/run-moving-hotkey.sh`.

## Running

From `loadgen/`:

```bash
mvn -q exec:java -Dexec.args="bootstrap=localhost:9092 topic=skew-topic mode=DEDICATED threads=2 messagesPerSecond=50000 payloadSize=512 hotRatio=0.2 warmupSec=10 runSec=60"
```

Arguments are `key=value`: `bootstrap`, `topic`, `mode`, `threads`, `messagesPerSecond`, `payloadSize`, `hotRatio`, `warmupSec`, `runSec`.

For an end-to-end path (broker, topic, consumer, lag file, this loadgen), see **`experiments/run_experiment.sh`** at the repository root.
