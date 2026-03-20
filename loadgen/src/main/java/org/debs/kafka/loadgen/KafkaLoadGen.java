package org.debs.kafka.loadgen;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.Random;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

import org.apache.kafka.clients.producer.Callback;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.serialization.ByteArraySerializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.debs.kafka.loadgen.config.LoadGenConfig;
import org.debs.kafka.loadgen.metrics.LatencyStats;
import org.debs.kafka.loadgen.workload.HotKeyGenerator;
import org.debs.kafka.loadgen.workload.KeyGenerator;
import org.debs.kafka.loadgen.workload.UniformKeyGenerator;

public class KafkaLoadGen {
    private static final int DEFAULT_KEY_SPACE = 1_000_000;

    public static void main(String[] args) throws Exception {
        LoadGenConfig config = LoadGenConfig.fromArgs(args);
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, config.bootstrap());
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, ByteArraySerializer.class.getName());
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.LINGER_MS_CONFIG, "0");

        if (config.mode() == LoadGenConfig.Mode.RANDOM) {
            props.put(ProducerConfig.PARTITIONER_CLASS_CONFIG, RandomPartitioner.class.getName());
        }

        try (KafkaProducer<String, byte[]> producer = new KafkaProducer<>(props)) {
            ExecutorService executor = Executors.newFixedThreadPool(config.threads());
            CountDownLatch done = new CountDownLatch(config.threads());

            long warmupEndNanos = System.nanoTime() + TimeUnit.SECONDS.toNanos(config.warmupSec());
            long endNanos = warmupEndNanos + TimeUnit.SECONDS.toNanos(config.runSec());

            AtomicLong intervalCount = new AtomicLong();
            LatencyStats intervalLatencies = new LatencyStats();

            List<Runnable> tasks = new ArrayList<>();
            int baseRate = config.messagesPerSecond() / config.threads();
            int remainder = config.messagesPerSecond() % config.threads();

            for (int i = 0; i < config.threads(); i++) {
                int threadRate = baseRate + (i < remainder ? 1 : 0);
                int threadId = i;
                tasks.add(() -> {
                    if (threadRate == 0) {
                        done.countDown();
                        return;
                    }
                    KeyGenerator keyGenerator = createKeyGenerator(config, threadId);
                    Random payloadRandom = new Random(1234L + threadId);
                    byte[] payload = new byte[config.payloadSize()];
                    payloadRandom.nextBytes(payload);
                    long intervalNanos = TimeUnit.SECONDS.toNanos(1) / threadRate;
                    long nextSendNanos = System.nanoTime();

                    while (true) {
                        long now = System.nanoTime();
                        if (now >= endNanos) {
                            break;
                        }
                        if (now < nextSendNanos) {
                            long sleepNanos = nextSendNanos - now;
                            if (sleepNanos > 0) {
                                try {
                                    TimeUnit.NANOSECONDS.sleep(sleepNanos);
                                } catch (InterruptedException e) {
                                    Thread.currentThread().interrupt();
                                    break;
                                }
                            }
                        }

                        String key = null;
                        if (config.mode() == LoadGenConfig.Mode.DEDICATED) {
                            key = keyGenerator.nextKey();
                        }
                        long sendStart = System.nanoTime();
                        boolean record = sendStart >= warmupEndNanos;
                        ProducerRecord<String, byte[]> recordMsg =
                                new ProducerRecord<>(config.topic(), key, payload);
                        Callback callback = (RecordMetadata metadata, Exception exception) -> {
                            if (exception == null && record) {
                                long latencyUs = TimeUnit.NANOSECONDS.toMicros(System.nanoTime() - sendStart);
                                intervalLatencies.record(latencyUs);
                                intervalCount.incrementAndGet();
                            }
                        };
                        producer.send(recordMsg, callback);
                        nextSendNanos += intervalNanos;
                    }
                    done.countDown();
                });
            }

            Thread statsThread = new Thread(() -> {
                long start = System.nanoTime();
                while (System.nanoTime() < endNanos) {
                    try {
                        TimeUnit.SECONDS.sleep(1);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                    long now = System.nanoTime();
                    if (now < warmupEndNanos) {
                        continue;
                    }
                    long count = intervalCount.getAndSet(0);
                    LatencyStats.Snapshot snapshot = intervalLatencies.snapshotAndReset();
                    long elapsedSec = TimeUnit.NANOSECONDS.toSeconds(now - start);
                    System.out.println(
                            "t=" + elapsedSec + "s " +
                            "throughput=" + count + " msg/s " +
                            "p50=" + snapshot.p50() + "us " +
                            "p95=" + snapshot.p95() + "us " +
                            "p99=" + snapshot.p99() + "us");
                }
            });
            statsThread.setDaemon(true);
            statsThread.start();

            for (Runnable task : tasks) {
                executor.submit(task);
            }

            done.await();
            executor.shutdown();
            executor.awaitTermination(30, TimeUnit.SECONDS);
            producer.flush();
            producer.close(Duration.ofSeconds(5));
        }
    }

    private static KeyGenerator createKeyGenerator(LoadGenConfig config, int threadId) {
        long seed = 42L + threadId;
        if (config.hotRatio() > 0.0) {
            return new HotKeyGenerator(config.hotRatio(), DEFAULT_KEY_SPACE, seed);
        }
        return new UniformKeyGenerator(DEFAULT_KEY_SPACE, seed);
    }
}
