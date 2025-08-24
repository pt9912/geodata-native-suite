
package io.geodata.search.api;

import io.micronaut.http.annotation.*;
import io.micronaut.http.HttpStatus;
import java.util.*;

@Controller("/api/v1")
public class SearchController {

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
