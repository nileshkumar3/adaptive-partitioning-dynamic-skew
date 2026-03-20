# Load generator (`loadgen/`)

Maven module for the paper **Adaptive Partitioning under Dynamic Workload Skew in Event-Driven Systems**.

`KafkaLoadGen` is a **multi-threaded, rate-controlled** Kafka producer. After warmup it prints **throughput** and **ack latency** (p50, p95, p99) about once per second.

## What it does

- Sends fixed-size payloads at a target **messages-per-second** using worker threads.
- **`mode=DEDICATED`** — String keys on every record; the broker partitioner picks partitions.
- **`mode=RANDOM`** — **Null** keys and `RandomPartitioner` to spread traffic across partitions.

## Skew vs moving hot keys

- **Static skew (this JAR):** With `mode=DEDICATED` and `hotRatio > 0`, one **hot** key (`HOT`) gets that traffic share; the rest use **`COLD-*`** over a large key space. Use for **steady** hot-spot baselines vs `producer/AdaptivePartitioner.java`.

- **Moving hot key (paper):** Use `../workload/dynamic-skew-generator.java` or `../experiments/run-moving-hotkey.sh` from the repo root so the **hot key shifts over time**.

## Run from this repository

```bash
cd loadgen

mvn -q exec:java \
  -Dexec.args="bootstrap=localhost:9092 topic=skew-topic mode=DEDICATED threads=2 messagesPerSecond=50000 payloadSize=512 hotRatio=0.2 warmupSec=10 runSec=60"
```

Arguments are **`key=value`:**

`bootstrap`, `topic`, `mode` (`DEDICATED` | `RANDOM`), `threads`, `messagesPerSecond`, `payloadSize`, `hotRatio`, `warmupSec`, `runSec`.

End-to-end (broker, topic, consumer, lag, this loadgen): **`experiments/run_experiment.sh`** at the repository root.
