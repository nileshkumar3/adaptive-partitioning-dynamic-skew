# Load generator (`loadgen/`)

Maven module for the artifact **“Adaptive Partitioning under Dynamic Workload Skew in Event-Driven Systems.”** It provides **`KafkaLoadGen`**: a **multi-threaded, rate-controlled** Kafka producer that prints **throughput** and **producer acknowledgment latencies** (p50 / p95 / p99) each second after warmup.

## What it does

- Sends fixed-size payloads to a topic at a target **messages-per-second** across **worker threads**.
- In **dedicated** mode, every message has a **string key** so the broker’s partitioner decides routing.
- In **random** mode, keys are **null** and **`RandomPartitioner`** spreads records across partitions.

## Skew and moving hot keys

- **Static skew (this module):** With **`mode=DEDICATED`** and **`hotRatio > 0`**, a **single persistent hot key** (`HOT`) receives that fraction of traffic; the rest use **`COLD-*`** keys over a large space. Use this for **steady hot-spot** baselines (e.g. default hash vs **adaptive** in `producer/AdaptivePartitioner.java`).
- **Dynamic / moving hot key (paper scenario):** The hot key **changes over time** in **`../workload/dynamic-skew-generator.java`**, or run **`../experiments/run-moving-hotkey.sh`** from the repo root. That path is what you want for **shifting skew** experiments.

## How to run (from this repo)

```bash
cd loadgen
mvn -q exec:java -Dexec.args="bootstrap=localhost:9092 topic=skew-topic mode=DEDICATED threads=2 messagesPerSecond=50000 payloadSize=512 hotRatio=0.2 warmupSec=10 runSec=60"
```

Arguments are **`key=value`**: `bootstrap`, `topic`, `mode` (`DEDICATED` | `RANDOM`), `threads`, `messagesPerSecond`, `payloadSize`, `hotRatio`, `warmupSec`, `runSec`.

For broker + topic + background consumer + lag sampling + this loadgen, use **`experiments/run_experiment.sh`** at the repository root.
