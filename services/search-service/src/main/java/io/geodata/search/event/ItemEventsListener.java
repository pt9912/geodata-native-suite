package io.geodata.search.event;

import io.micronaut.configuration.kafka.annotation.KafkaListener;
import io.micronaut.configuration.kafka.annotation.Topic;
import jakarta.inject.Inject;
import io.geodata.search.cache.*;

@KafkaListener(groupId = "search-cache-bump")
public class ItemEventsListener {

    @Inject
    RedisCache cache;

    @Topic({"stac.item.updated", "stac.item.deleted"})
    public void onChange(byte[] payload) {
        cache.bump();
    }
}
