package org.debs.kafka.loadgen.workload;

import java.util.Random;

public class UniformKeyGenerator implements KeyGenerator {
    private final Random random;
    private final int keySpace;

    public UniformKeyGenerator(int keySpace, long seed) {
        if (keySpace <= 0) {
            throw new IllegalArgumentException("keySpace must be > 0");
        }
        this.keySpace = keySpace;
        this.random = new Random(seed);
    }

    @Override
    public String nextKey() {
        int key = random.nextInt(keySpace);
        return "KEY-" + key;
    }
}
