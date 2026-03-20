package org.debs.kafka.loadgen.config;

import java.util.HashMap;
import java.util.Map;

public record LoadGenConfig(
        String bootstrap,
        String topic,
        Mode mode,
        int threads,
        int messagesPerSecond,
        int payloadSize,
        double hotRatio,
        int warmupSec,
        int runSec) {

    public enum Mode {
        DEDICATED,
        RANDOM
    }

    public static LoadGenConfig fromArgs(String[] args) {
        Map<String, String> values = new HashMap<>();
        for (String arg : args) {
            int idx = arg.indexOf('=');
            if (idx <= 0 || idx == arg.length() - 1) {
                throw new IllegalArgumentException("Invalid argument: " + arg);
            }
            values.put(arg.substring(0, idx), arg.substring(idx + 1));
        }

        String bootstrap = required(values, "bootstrap");
        String topic = required(values, "topic");
        Mode mode = Mode.valueOf(required(values, "mode"));
        int threads = parseInt(values, "threads");
        int messagesPerSecond = parseInt(values, "messagesPerSecond");
        int payloadSize = parseInt(values, "payloadSize");
        double hotRatio = parseDouble(values, "hotRatio");
        int warmupSec = parseInt(values, "warmupSec");
        int runSec = parseInt(values, "runSec");

        if (threads <= 0) {
            throw new IllegalArgumentException("threads must be > 0");
        }
        if (messagesPerSecond < 0) {
            throw new IllegalArgumentException("messagesPerSecond must be >= 0");
        }
        if (payloadSize < 0) {
            throw new IllegalArgumentException("payloadSize must be >= 0");
        }
        if (hotRatio < 0.0 || hotRatio > 1.0) {
            throw new IllegalArgumentException("hotRatio must be in [0.0, 1.0]");
        }
        if (warmupSec < 0 || runSec <= 0) {
            throw new IllegalArgumentException("warmupSec must be >= 0 and runSec > 0");
        }

        return new LoadGenConfig(
                bootstrap,
                topic,
                mode,
                threads,
                messagesPerSecond,
                payloadSize,
                hotRatio,
                warmupSec,
                runSec);
    }

    private static String required(Map<String, String> values, String key) {
        String value = values.get(key);
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("Missing argument: " + key);
        }
        return value;
    }

    private static int parseInt(Map<String, String> values, String key) {
        String value = required(values, key);
        return Integer.parseInt(value);
    }

    private static double parseDouble(Map<String, String> values, String key) {
        String value = required(values, key);
        return Double.parseDouble(value);
    }
}
