# Experimental Artifacts for DEBS Submission

This repository will host the experimental artifacts for the paper:

"Dedicated vs. Random Partitioning in Event-Driven Systems under Skewed Workloads"

Planned artifacts include:
- Kafka producer load generator (Java)
- Custom random partitioner
- Experiment configuration files
- Scripts for running benchmarks
- Instructions for reproducing results

Artifacts will be added incrementally as experiments are finalized.

---

## In `adaptive-partitioning-dynamic-skew`

This tree is copied from `kafka-partitioning-skew-experiments`. The POM adds `exec-maven-plugin` so you can run:

```bash
cd loadgen
mvn -q exec:java -Dexec.args="bootstrap=localhost:9092 topic=skew-topic mode=DEDICATED threads=2 messagesPerSecond=50000 payloadSize=512 hotRatio=0.2 warmupSec=10 runSec=60"
```

Or use `experiments/run_experiment.sh` from the repo root.
