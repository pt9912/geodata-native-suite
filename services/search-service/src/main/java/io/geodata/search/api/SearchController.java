
package io.geodata.search.api;

import io.micronaut.http.annotation.*;
import io.micronaut.http.HttpStatus;
import java.util.*;

import jakarta.inject.Inject;
import javax.sql.DataSource;
import java.sql.*;

import io.geodata.search.database.*;
import io.geodata.search.cache.*;
import io.geodata.search.model.*;

@Controller("/api/v1")
public class SearchController {

    @Inject
    DataSource ds;

    @Inject
    QueryDb queryDb;


    @Inject
    RedisCache cache;

    @Get("/search/search")
    public List<ItemOut> search(
            @QueryValue Optional<String> bbox,
            @QueryValue(defaultValue = "") String dt_from,
            @QueryValue(defaultValue = "") String dt_to,
            @QueryValue List<String> collections,
            @QueryValue(defaultValue = "") String q,
            @QueryValue(defaultValue = "EPSG:4326") String crs,
            @QueryValue(defaultValue = "50") int limit,
            @QueryValue(defaultValue = "0") int offset) throws Exception {

        long v = cache.version();
        String key = "v" + v + ":sqlite:" + bbox + ":" + dt_from + ":" + dt_to + ":" + collections + ":" + q + ":" + crs + ":" + limit + ":" + offset;
        var cached = cache.get(key);

        if (cached.isPresent()) {
            var arr = new com.fasterxml.jackson.databind.ObjectMapper().readValue(cached.get(), List.class);
            List<ItemOut> out = new ArrayList<>();
            for (Object o : arr) {
                var m = (Map<String, Object>) o;
                out.add(new ItemOut(
                    (String) m.get("id"),
                    (String) m.get("collection"),
                    (String) m.get("datetime"),
                    List.of(
                        ((Number) ((List<?>) m.get("bbox")).get(0)).doubleValue(),
                        ((Number) ((List<?>) m.get("bbox")).get(1)).doubleValue(),
                        ((Number) ((List<?>) m.get("bbox")).get(2)).doubleValue(),
                        ((Number) ((List<?>) m.get("bbox")).get(3)).doubleValue()
                    )
                ));
            }
            return out;
        }

        var stacFilter = new StacFilter();
        if (bbox.isPresent()) {
            String[] p = bbox.get().split(",");
            if (p.length != 4) {
                throw new IllegalArgumentException("bbox minx,miny,maxx,maxy");
            }
            double minx = Double.parseDouble(p[0]);
            double miny = Double.parseDouble(p[1]);
            double maxx = Double.parseDouble(p[2]);
            double maxy = Double.parseDouble(p[3]);
            stacFilter.bbox = List.of(minx, miny, maxx, maxy);
        }
        stacFilter.dt_from  = dt_from;
        stacFilter.dt_to  = dt_to;
        stacFilter.collections = collections;
        stacFilter.crs = crs;
        stacFilter.q = q;
        stacFilter.limit = limit;
        stacFilter.offset = offset;
        
        List<ItemOut> queryResult = queryDb.query(stacFilter);

        var json = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(queryResult);
        cache.set(key, json, 3600);

        return queryResult;
    }

    @Get("/search")
    public Map<String, Object> search(
        @QueryValue Optional<String> bbox,
        @QueryValue Optional<String> datetime,
        @QueryValue(defaultValue="10") int limit,
        @QueryValue(defaultValue="0") int offset
    ) {
        Map<String,Object> res = new LinkedHashMap<>();
        res.put("type","FeatureCollection");
        res.put("count", 0);
        res.put("features", List.of());
        res.put("params", Map.of("bbox", bbox.orElse(null), "datetime", datetime.orElse(null), "limit", limit, "offset", offset));
        return res;
    }

    @Post("/search")
    public Map<String,Object> searchPost(@Body Map<String,Object> filter) {
        Map<String,Object> res = new LinkedHashMap<>();
        res.put("type","FeatureCollection");
        res.put("count", 0);
        res.put("features", List.of());
        res.put("filterEcho", filter);
        return res;
    }
}
