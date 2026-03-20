package workload;

import java.util.Properties;
import java.util.Random;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;

/**
 * Synthetic producer that changes skew over time: hot-key fraction and which key is hot
 * can move on a schedule. Use with {@code partitioner.class} set to your adaptive
 * partitioner for experiments.
 *
 * Build (example): compile with kafka-clients on the classpath, then run {@code workload.DynamicSkewGenerator}.
 */
class DynamicSkewGenerator {

    /** Entry point; class is package-private so this file can use a hyphenated name. */
    public static void main(String[] args) throws InterruptedException {
        String bootstrap = prop(args, 0, "bootstrap.servers", "localhost:9092");
        String topic = prop(args, 1, "topic", "dynamic-skew");
        int totalMessages = intProp(args, 2, 1_000_000);
        int phaseMs = intProp(args, 3, 10_000);
        double hotFraction = doubleProp(args, 4, 0.5);
        int keySpace = intProp(args, 5, 10_000);

        Properties p = new Properties();
        p.put("bootstrap.servers", bootstrap);
        p.put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        p.put("value.serializer", "org.apache.kafka.common.serialization.StringSerializer");
        // skew.partitioner=adaptive | default (system property or env SKEW_PARTITIONER); tuning via -Dadaptive.*
        applyPartitionerStrategy(p);
        p.put("linger.ms", "5");
        p.put("batch.size", "65536");
        p.put("acks", "1");

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(p)) {
            Random rng = new Random(42);
            long start = System.currentTimeMillis();
            int hotIndex = 0;
            for (int i = 0; i < totalMessages; i++) {
                long elapsed = System.currentTimeMillis() - start;
                int newHot = (int) (elapsed / phaseMs) % Math.max(1, keySpace / 100);
                if (newHot != hotIndex) {
                    hotIndex = newHot;
                }
                String key = nextKey(rng, keySpace, hotIndex, hotFraction);
                String value = String.valueOf(i);
                producer.send(new ProducerRecord<>(topic, key, value), (meta, err) -> {
                    if (err != null) {
                        err.printStackTrace();
                    }
                });
                if ((i & 0xFFFF) == 0) {
                    Thread.sleep(0); // yield occasionally for cleaner Ctrl+C
                }
            }
            producer.flush();
        }
    }

    private static String nextKey(Random rng, int keySpace, int hotIndex, double hotFraction) {
        if (rng.nextDouble() < hotFraction) {
            return "k-" + hotIndex;
        }
        return "k-" + rng.nextInt(keySpace);
    }

    private static void applyPartitionerStrategy(Properties p) {
        String mode = System.getProperty("skew.partitioner");
        if (mode == null || mode.isBlank()) {
            mode = System.getenv().getOrDefault("SKEW_PARTITIONER", "default");
        }
        if ("adaptive".equalsIgnoreCase(mode.trim())) {
            p.put("partitioner.class", "producer.AdaptivePartitioner");
            // Tuning: pass JVM flags -Dadaptive.* (Producer may reject unknown property keys).
        }
    }

    private static String prop(String[] args, int idx, String key, String def) {
        if (args.length > idx && args[idx] != null && !args[idx].isEmpty()) {
            return args[idx];
        }
        return System.getProperty(key.replace('.', '_'), def);
    }

    private static int intProp(String[] args, int idx, int def) {
        if (args.length > idx) {
            try {
                return Integer.parseInt(args[idx]);
            } catch (NumberFormatException ignored) {
            }
        }
        return def;
    }

    private static double doubleProp(String[] args, int idx, double def) {
        if (args.length > idx) {
            try {
                return Double.parseDouble(args[idx]);
            } catch (NumberFormatException ignored) {
            }
        }
        return def;
    }
}
