package org.debs.kafka.loadgen.metrics;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class LatencyStats {
    private final List<Long> samples = new ArrayList<>();

    public void record(long latencyUs) {
        synchronized (samples) {
            samples.add(latencyUs);
        }
    }

    public Snapshot snapshotAndReset() {
        List<Long> copy;
        synchronized (samples) {
            if (samples.isEmpty()) {
                return new Snapshot(0, 0, 0);
            }
            copy = new ArrayList<>(samples);
            samples.clear();
        }
        Collections.sort(copy);
        return new Snapshot(
                percentile(copy, 50),
                percentile(copy, 95),
                percentile(copy, 99));
    }

    private static long percentile(List<Long> values, int pct) {
        if (values.isEmpty()) {
            return 0;
        }
        int idx = (int) Math.ceil((pct / 100.0) * values.size()) - 1;
        idx = Math.max(0, Math.min(idx, values.size() - 1));
        return values.get(idx);
    }

    public record Snapshot(long p50, long p95, long p99) {
    }
}
