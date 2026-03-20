package producer;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLongArray;
import org.apache.kafka.clients.producer.Partitioner;
import org.apache.kafka.common.Cluster;
import org.apache.kafka.common.PartitionInfo;
import org.apache.kafka.common.utils.Utils;

/**
 * Producer-side partitioner that steers traffic away from overheated partitions while
 * preserving sticky routing for keys that have recently been assigned, so ordering
 * per key is not shredded on every send.
 *
 * Intended for evaluation under workloads whose skew moves over time (shifting hot keys).
 */
public class AdaptivePartitioner implements Partitioner {

    private static final int STICKY_TTL_MS = 30_000;
    /** murmur2-based hash for key → preferred partition when not adapting */
    private final ConcurrentHashMap<String, StickyRoute> stickyByKey = new ConcurrentHashMap<>();
    private volatile AtomicLongArray partitionCounts;
    private volatile int numPartitions = -1;

    @Override
    public void configure(Map<String, ?> configs) {
        // optional: read rebalance aggressiveness from configs later
    }

    @Override
    public int partition(
            String topic,
            Object key,
            byte[] keyBytes,
            Object value,
            byte[] valueBytes,
            Cluster cluster) {
        List<PartitionInfo> parts = cluster.partitionsForTopic(topic);
        if (parts == null || parts.isEmpty()) {
            return 0;
        }
        int n = parts.size();
        ensureCounters(n);

        if (keyBytes == null) {
            return leastLoadedPartition(n);
        }

        String keyStr = new String(keyBytes, StandardCharsets.UTF_8);
        long now = System.currentTimeMillis();
        StickyRoute sticky = stickyByKey.get(keyStr);
        if (sticky != null && now - sticky.sinceMs < STICKY_TTL_MS) {
            partitionCounts.incrementAndGet(sticky.partition);
            return sticky.partition;
        }

        double mean = meanLoad(n);
        int candidate = defaultPartition(topic, keyBytes, n, cluster);
        if (partitionCounts.get(candidate) <= mean * 1.25) {
            stickyByKey.put(keyStr, new StickyRoute(candidate, now));
            partitionCounts.incrementAndGet(candidate);
            return candidate;
        }

        int alt = leastLoadedPartition(n);
        stickyByKey.put(keyStr, new StickyRoute(alt, now));
        partitionCounts.incrementAndGet(alt);
        return alt;
    }

    private void ensureCounters(int n) {
        if (numPartitions == n && partitionCounts != null) {
            return;
        }
        synchronized (this) {
            if (numPartitions == n && partitionCounts != null) {
                return;
            }
            partitionCounts = new AtomicLongArray(n);
            numPartitions = n;
        }
    }

    private double meanLoad(int n) {
        long sum = 0;
        for (int i = 0; i < n; i++) {
            sum += partitionCounts.get(i);
        }
        return n == 0 ? 0 : (double) sum / n;
    }

    private int leastLoadedPartition(int n) {
        int best = 0;
        long bestVal = Long.MAX_VALUE;
        for (int i = 0; i < n; i++) {
            long v = partitionCounts.get(i);
            if (v < bestVal) {
                bestVal = v;
                best = i;
            }
        }
        partitionCounts.incrementAndGet(best);
        return best;
    }

    private static int defaultPartition(String topic, byte[] keyBytes, int numPartitions, Cluster cluster) {
        return Utils.toPositive(Utils.murmur2(keyBytes)) % numPartitions;
    }

    @Override
    public void close() {
        stickyByKey.clear();
    }

    private static final class StickyRoute {
        final int partition;
        final long sinceMs;

        StickyRoute(int partition, long sinceMs) {
            this.partition = partition;
            this.sinceMs = sinceMs;
        }
    }
}
