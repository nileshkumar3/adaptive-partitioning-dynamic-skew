package org.debs.kafka.loadgen.workload;

import java.util.Random;

public class HotKeyGenerator implements KeyGenerator {
    private final Random random;
    private final double hotRatio;
    private final int keySpace;

    public HotKeyGenerator(double hotRatio, int keySpace, long seed) {
        if (hotRatio < 0.0 || hotRatio > 1.0) {
            throw new IllegalArgumentException("hotRatio must be in [0.0, 1.0]");
        }
        if (keySpace <= 0) {
            throw new IllegalArgumentException("keySpace must be > 0");
        }
        this.hotRatio = hotRatio;
        this.keySpace = keySpace;
        this.random = new Random(seed);
    }

    @Override
    public String nextKey() {
        if (random.nextDouble() < hotRatio) {
            return "HOT";
        }
        int key = random.nextInt(keySpace);
        return "COLD-" + key;
    }
}
