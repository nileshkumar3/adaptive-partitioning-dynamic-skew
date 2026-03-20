package org.debs.kafka.loadgen;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

import org.apache.kafka.clients.producer.Partitioner;
import org.apache.kafka.common.Cluster;
import org.apache.kafka.common.PartitionInfo;

public class RandomPartitioner implements Partitioner {
    @Override
    public void configure(Map<String, ?> configs) {
    }

    @Override
    public int partition(
            String topic,
            Object key,
            byte[] keyBytes,
            Object value,
            byte[] valueBytes,
            Cluster cluster) {
        List<PartitionInfo> available = cluster.availablePartitionsForTopic(topic);
        List<PartitionInfo> partitions = available.isEmpty()
                ? cluster.partitionsForTopic(topic)
                : available;
        int size = partitions.size();
        if (size == 0) {
            return 0;
        }
        int idx = ThreadLocalRandom.current().nextInt(size);
        return partitions.get(idx).partition();
    }

    @Override
    public void close() {
    }
}
