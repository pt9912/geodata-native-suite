
package io.geodata.search.api;

import io.geodata.search.database.QueryDb;
import io.geodata.search.model.ItemOut;
import io.geodata.search.model.StacFilter;
import io.geodata.search.util.Proj;
import io.micronaut.http.annotation.*;
import jakarta.inject.Inject;
import java.util.*;

@Controller("/api/v1")
public class StacSearchController {

    @Post("/search")
    public Map<String,Object> searchPost(@Body StacFilter filter) {
        StacFilter effective = normaliseFilter(filter);
        List<ItemOut> items = queryDb.query(effective);

        Map<String, Object> collection = new LinkedHashMap<>();
        collection.put("type", "FeatureCollection");
        collection.put("features", buildFeatures(items));
        collection.put("numberMatched", items.size());
        collection.put("numberReturned", items.size());
        collection.put("links", List.of());
        collection.put("context", buildContext(filter, effective, items.size()));
        return collection;
    }

    @Inject
    QueryDb queryDb;

    private StacFilter normaliseFilter(StacFilter incoming) {
        StacFilter out = new StacFilter();

        List<Double> bbox = incoming != null ? incoming.bbox : null;
        String crs = incoming != null ? incoming.crs : null;
        if (bbox != null && crs != null && "EPSG:3857".equalsIgnoreCase(crs)) {
            bbox = Proj.bbox3857to4326(bbox);
        }

        out.bbox = bbox != null ? bbox : List.of();
        out.dt_from = incoming != null && incoming.dt_from != null ? incoming.dt_from : "";
        out.dt_to = incoming != null && incoming.dt_to != null ? incoming.dt_to : "";
        out.collections = incoming != null && incoming.collections != null ? incoming.collections : List.of();
        out.q = incoming != null && incoming.q != null ? incoming.q : "";
        out.crs = "EPSG:4326";
        out.limit = incoming != null && incoming.limit != null ? incoming.limit : 10;
        out.offset = incoming != null && incoming.offset != null ? incoming.offset : 0;
        out.intersects = incoming != null ? incoming.intersects : null;
        return out;
    }

    private List<Map<String, Object>> buildFeatures(List<ItemOut> items) {
        List<Map<String, Object>> features = new ArrayList<>(items.size());
        for (ItemOut item : items) {
            Map<String, Object> feature = new LinkedHashMap<>();
            feature.put("type", "Feature");
            feature.put("id", item.id());
            feature.put("collection", item.collection());
            feature.put("bbox", item.bbox());
            feature.put("geometry", geometryFromBbox(item.bbox()));
            feature.put("properties", Map.of("datetime", item.datetime()));
            feature.put("links", List.of());
            features.add(feature);
        }
        return features;
    }

    private Map<String, Object> geometryFromBbox(List<Double> bbox) {
        if (bbox == null || bbox.size() != 4) {
            return null;
        }
        double minx = bbox.get(0);
        double miny = bbox.get(1);
        double maxx = bbox.get(2);
        double maxy = bbox.get(3);
        List<List<List<Double>>> coordinates = List.of(
            List.of(
                List.of(minx, miny),
                List.of(maxx, miny),
                List.of(maxx, maxy),
                List.of(minx, maxy),
                List.of(minx, miny)
            )
        );
        Map<String, Object> geometry = new LinkedHashMap<>();
        geometry.put("type", "Polygon");
        geometry.put("coordinates", coordinates);
        return geometry;
    }

    private Map<String, Object> buildContext(StacFilter original, StacFilter effective, int returned) {
        Map<String, Object> ctx = new LinkedHashMap<>();
        ctx.put("bbox", effective.bbox.isEmpty() ? null : effective.bbox);
        ctx.put("dt_from", effective.dt_from);
        ctx.put("dt_to", effective.dt_to);
        ctx.put("collections", effective.collections);
        ctx.put("q", effective.q);
        ctx.put("crs", effective.crs);
        ctx.put("limit", effective.limit);
        ctx.put("offset", effective.offset);
        ctx.put("returned", returned);
        if (original != null && original.intersects != null) {
            ctx.put("intersects", original.intersects);
        }
        return ctx;
    }
}
