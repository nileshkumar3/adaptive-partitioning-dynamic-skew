# Load generator (`loadgen/`)

Maven module for the paper artifact **Adaptive Partitioning under Dynamic Workload Skew in Event-Driven Systems**.

**`KafkaLoadGen`** is a **multi-threaded, rate-controlled** Kafka producer. After warmup it prints **throughput** and **ack latency** percentiles (p50 / p95 / p99) each second.

## What it does

- Sends fixed-size payloads at a target **messages-per-second** using **worker threads**.
- **`mode=DEDICATED`:** string keys on every record (broker partitioner chooses routing).
- **`mode=RANDOM`:** **null** keys and **`RandomPartitioner`** to spread across partitions.

## Skew vs moving hot keys

- **Static skew (this module):** `mode=DEDICATED` and `hotRatio > 0` send a fixed fraction to one **hot** key (`HOT`); the rest use **`COLD-*`** over a large space. Good for **steady** hot-spot baselines vs `producer/AdaptivePartitioner.java`.
- **Moving hot key (paper):** use **`../workload/dynamic-skew-generator.java`** or **`../experiments/run-moving-hotkey.sh`** from the repo root so the **hot key shifts over time**.

## Run (from this repo)

```bash
cd loadgen
mvn -q exec:java \
  -Dexec.args="bootstrap=localhost:9092 topic=skew-topic mode=DEDICATED threads=2 messagesPerSecond=50000 payloadSize=512 hotRatio=0.2 warmupSec=10 runSec=60"
```

Arguments: **`key=value`** — `bootstrap`, `topic`, `mode` (`DEDICATED` | `RANDOM`), `threads`, `messagesPerSecond`, `payloadSize`, `hotRatio`, `warmupSec`, `runSec`.

**Broker + topic + consumer + lag + this loadgen:** **`experiments/run_experiment.sh`** at the repository root.
