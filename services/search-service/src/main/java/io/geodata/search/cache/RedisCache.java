package io.geodata.search.cache;

import io.lettuce.core.api.StatefulRedisConnection;
import jakarta.inject.Singleton;
import jakarta.inject.Inject;
import java.util.Optional;

@Singleton
public class RedisCache {

    @Inject
    StatefulRedisConnection<String, String> conn;

    public long version() {
        try {
            String v = conn.sync().get("search:cache:version");
            return v == null ? 0L : Long.parseLong(v);
        } catch (Exception e) {
            return 0L;
        }
    }

    public Optional<String> get(String key) {
        try {
            return Optional.ofNullable(conn.sync().get(key));
        } catch (Exception e) {
            return Optional.empty();
        }
    }

    public void set(String key, String val, int ttlSeconds) {
        try {
            conn.sync().setex(key, ttlSeconds, val);
        } catch (Exception ignored) {
        }
    }

    public void bump() {
        try {
            conn.sync().incr("search:cache:version");
        } catch (Exception ignored) {
        }
    }
}
