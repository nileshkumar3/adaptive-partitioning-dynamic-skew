package producer;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicLongArray;
import org.apache.kafka.clients.producer.Partitioner;
import org.apache.kafka.common.Cluster;
import org.apache.kafka.common.PartitionInfo;
import org.apache.kafka.common.utils.Utils;

/**
 * Experimental producer partitioner for dynamic skew: within a sliding time window, approximate
 * per-partition load and optionally reroute keys away from the default murmur2 partition when that
 * partition is hotter than the cluster mean by an imbalance factor. Sticky routing (TTL) limits
 * flip-flopping per key. When adaptation is off, behavior matches default hash routing (plus a
 * simple random choice for null keys), without maintaining window counts.
 */
public class AdaptivePartitioner implements Partitioner {

    public static final String ADAPTIVE_ENABLE = "adaptive.enable";
    public static final String ADAPTIVE_STICKY_TTL_MS = "adaptive.sticky.ttl.ms";
    public static final String ADAPTIVE_IMBALANCE_FACTOR = "adaptive.imbalance.factor";
    public static final String ADAPTIVE_WINDOW_MS = "adaptive.window.ms";
    public static final String ADAPTIVE_LOG_ENABLE = "adaptive.log.enable";
    /** If {@code > 0}, one stderr summary line per interval (routes + map size); no per-record spam. */
    public static final String ADAPTIVE_LOG_SUMMARY_MS = "adaptive.log.summary.ms";

    private volatile boolean adaptiveEnabled = true;
    private volatile long stickyTtlMs = 30_000;
    private volatile double imbalanceFactor = 1.25;
    private volatile long windowMs = 10_000;
    private volatile boolean logEnabled;
    private volatile long logSummaryMs;

    private final ConcurrentHashMap<String, Sticky> stickyByKey = new ConcurrentHashMap<>();
    private final Object windowLock = new Object();
    private final Object summaryLock = new Object();
    private volatile AtomicLongArray windowCounts = new AtomicLongArray(0);
    private volatile int numPartitions = -1;
    /** Wall-clock start of the current load window; counts are reset when the window elapses. */
    private volatile long windowStartMs;

    private volatile long lastSummaryAtMs;
    private final AtomicLong routeSticky = new AtomicLong();
    private final AtomicLong routeHash = new AtomicLong();
    private final AtomicLong routeReroute = new AtomicLong();
    private final AtomicLong routeNullKey = new AtomicLong();
    private final AtomicLong routeDisabled = new AtomicLong();

    @Override
    public void configure(Map<String, ?> configs) {
        adaptiveEnabled = parseBool(cfg(configs, ADAPTIVE_ENABLE, "true"), true);
        stickyTtlMs = parseLong(cfg(configs, ADAPTIVE_STICKY_TTL_MS, "30000"), 30_000);
        imbalanceFactor = parseDouble(cfg(configs, ADAPTIVE_IMBALANCE_FACTOR, "1.25"), 1.25);
        windowMs = parseLong(cfg(configs, ADAPTIVE_WINDOW_MS, "10000"), 10_000);
        logEnabled = parseBool(cfg(configs, ADAPTIVE_LOG_ENABLE, "false"), false);
        logSummaryMs = parseLong(cfg(configs, ADAPTIVE_LOG_SUMMARY_MS, "0"), 0);
        lastSummaryAtMs = System.currentTimeMillis();
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
        final int n = parts.size();

        if (!adaptiveEnabled) {
            int p = keyedOrRandomPartition(keyBytes, n);
            trace("DISABLED_DEFAULT", p, "adaptive.enable=false", keyBytes);
            noteRoute("DISABLED_DEFAULT");
            maybeSummary();
            return p;
        }

        ensureCounters(n);
        final long now = System.currentTimeMillis();
        if (windowMs > 0) {
            maybeRotateWindow(now, n);
        }

        if (keyBytes == null) {
            int p = argminPartition(n);
            recordOnce(p, "NULL_KEY_LEAST_LOADED", "null key → argmin window load", keyBytes);
            maybeSummary();
            return p;
        }

        String keyStr = new String(keyBytes, StandardCharsets.UTF_8);
        Sticky sticky = stickyByKey.get(keyStr);
        if (sticky != null) {
            if (now - sticky.sinceMs < stickyTtlMs) {
                recordOnce(sticky.partition, "STICKY", "within sticky TTL", keyBytes);
                maybeSummary();
                return sticky.partition;
            }
            stickyByKey.remove(keyStr, sticky);
        }

        int hashPart = murmurPartition(keyBytes, n);
        double mean = meanWindowLoad(n);
        double threshold = mean * imbalanceFactor;
        long hashLoad = windowCounts.get(hashPart);

        if (hashLoad <= threshold) {
            stickyByKey.put(keyStr, new Sticky(hashPart, now));
            recordOnce(hashPart, "HASH", "hash partition within threshold (≤ mean×imbalance)", keyBytes);
            maybeSummary();
            return hashPart;
        }

        int alt = argminPartition(n);
        stickyByKey.put(keyStr, new Sticky(alt, now));
        recordOnce(
                alt,
                "REROUTE",
                String.format(
                        "hash p=%d load=%d > threshold=%.1f (mean=%.1f) → p=%d",
                        hashPart, hashLoad, threshold, mean, alt),
                keyBytes);
        maybeSummary();
        return alt;
    }

    private void noteRoute(String route) {
        if (logSummaryMs <= 0) {
            return;
        }
        if ("DISABLED_DEFAULT".equals(route)) {
            routeDisabled.incrementAndGet();
        }
    }

    /** Increments the chosen partition’s window counter exactly once and optionally logs. */
    private void recordOnce(int partition, String route, String detail, byte[] keyBytes) {
        windowCounts.incrementAndGet(partition);
        trace(route, partition, detail, keyBytes);
        bumpRouteCounter(route);
    }

    private void bumpRouteCounter(String route) {
        if (logSummaryMs <= 0) {
            return;
        }
        switch (route) {
            case "STICKY" -> routeSticky.incrementAndGet();
            case "HASH" -> routeHash.incrementAndGet();
            case "REROUTE" -> routeReroute.incrementAndGet();
            case "NULL_KEY_LEAST_LOADED" -> routeNullKey.incrementAndGet();
            default -> {
                /* DISABLED counted in noteRoute */
            }
        }
    }

    private void maybeSummary() {
        if (logSummaryMs <= 0) {
            return;
        }
        long now = System.currentTimeMillis();
        if (now - lastSummaryAtMs < logSummaryMs) {
            return;
        }
        synchronized (summaryLock) {
            if (now - lastSummaryAtMs < logSummaryMs) {
                return;
            }
            lastSummaryAtMs = now;
            long s = routeSticky.getAndSet(0);
            long h = routeHash.getAndSet(0);
            long r = routeReroute.getAndSet(0);
            long n = routeNullKey.getAndSet(0);
            long d = routeDisabled.getAndSet(0);
            System.err.printf(
                    "AdaptivePartitioner summary intervalMs=%d sticky=%d hash=%d reroute=%d nullKey=%d disabled=%d stickyMapSize=%d%n",
                    logSummaryMs, s, h, r, n, d, stickyByKey.size());
        }
    }

    /** stderr trace line; off unless adaptive.log.enable. */
    private void trace(String route, int partition, String detail, byte[] keyBytes) {
        if (!logEnabled) {
            return;
        }
        String keyHint = keyBytes == null ? "null" : ("bytes=" + keyBytes.length);
        System.err.println(
                String.format(
                        "AdaptivePartitioner partition=%d route=%s key=%s detail=%s",
                        partition, route, keyHint, detail));
    }

    private int keyedOrRandomPartition(byte[] keyBytes, int n) {
        if (keyBytes == null) {
            return ThreadLocalRandom.current().nextInt(n);
        }
        return murmurPartition(keyBytes, n);
    }

    private int murmurPartition(byte[] keyBytes, int n) {
        return Utils.toPositive(Utils.murmur2(keyBytes)) % n;
    }

    private void maybeRotateWindow(long now, int n) {
        if (now - windowStartMs < windowMs) {
            return;
        }
        synchronized (windowLock) {
            if (now - windowStartMs < windowMs) {
                return;
            }
            for (int i = 0; i < n; i++) {
                windowCounts.set(i, 0);
            }
            windowStartMs = now;
            pruneExpiredStickies(now);
        }
    }

    /** Drop expired stickies when the load window rolls (keeps map from growing without a full scan per record). */
    private void pruneExpiredStickies(long now) {
        stickyByKey.entrySet().removeIf(e -> now - e.getValue().sinceMs >= stickyTtlMs);
    }

    private void ensureCounters(int n) {
        if (numPartitions == n) {
            return;
        }
        synchronized (windowLock) {
            if (numPartitions == n) {
                return;
            }
            windowCounts = new AtomicLongArray(n);
            numPartitions = n;
            windowStartMs = System.currentTimeMillis();
        }
    }

    private double meanWindowLoad(int n) {
        if (n == 0) {
            return 0;
        }
        long sum = 0;
        for (int i = 0; i < n; i++) {
            sum += windowCounts.get(i);
        }
        return (double) sum / n;
    }

    /**
     * Argmin over window load; ties among minimal-load partitions resolved uniformly at random (no
     * partition-0 bias).
     */
    private int argminPartition(int n) {
        long bestVal = Long.MAX_VALUE;
        for (int i = 0; i < n; i++) {
            long v = windowCounts.get(i);
            if (v < bestVal) {
                bestVal = v;
            }
        }
        int ties = 0;
        for (int i = 0; i < n; i++) {
            if (windowCounts.get(i) == bestVal) {
                ties++;
            }
        }
        if (ties == 0) {
            return 0;
        }
        int pick = ThreadLocalRandom.current().nextInt(ties);
        for (int i = 0; i < n; i++) {
            if (windowCounts.get(i) == bestVal) {
                if (pick-- == 0) {
                    return i;
                }
            }
        }
        return 0;
    }

    private static String cfg(Map<String, ?> configs, String key, String defaultVal) {
        Object v = configs.get(key);
        if (v != null) {
            return v.toString();
        }
        String s = System.getProperty(key);
        return s != null ? s : defaultVal;
    }

    private static boolean parseBool(String s, boolean def) {
        if (s == null || s.isBlank()) {
            return def;
        }
        return Boolean.parseBoolean(s);
    }

    private static long parseLong(String s, long def) {
        try {
            return Long.parseLong(s.trim());
        } catch (NumberFormatException e) {
            return def;
        }
    }

    private static double parseDouble(String s, double def) {
        try {
            return Double.parseDouble(s.trim());
        } catch (NumberFormatException e) {
            return def;
        }
    }

    @Override
    public void close() {
        stickyByKey.clear();
    }

    private static final class Sticky {
        final int partition;
        final long sinceMs;

        Sticky(int partition, long sinceMs) {
            this.partition = partition;
            this.sinceMs = sinceMs;
        }
    }
}
