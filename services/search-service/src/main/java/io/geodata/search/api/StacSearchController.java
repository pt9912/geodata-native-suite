
package io.geodata.search.api;

import io.geodata.search.model.StacFilter;
import io.geodata.search.util.Proj;
import io.micronaut.http.annotation.*;
import java.util.*;

@Controller("/api/v1")
public class StacSearchController {

    @Post("/search")
    public Map<String,Object> searchPost(@Body StacFilter filter) {
        List<Double> bbox = filter.bbox;
        if (bbox != null && "EPSG:3857".equalsIgnoreCase(filter.crs)) {
            bbox = Proj.bbox3857to4326(bbox);
        }
        Map<String,Object> fc = new LinkedHashMap<>();
        fc.put("type","FeatureCollection");
        fc.put("features", List.of());
        Map<String,Object> ctx = new LinkedHashMap<>();
        ctx.put("bbox", bbox);
        ctx.put("dt_from", filter.dt_from);
        ctx.put("dt_to", filter.dt_to);
        ctx.put("collections", filter.collections);
        ctx.put("q", filter.q);
        ctx.put("crs", "EPSG:4326");
        ctx.put("limit", filter.limit);
        ctx.put("offset", filter.offset);
        fc.put("context", ctx);
        // TODO: PostGIS/SpatiaLite Query; Textsuche; Paging
        return fc;
    }
}
