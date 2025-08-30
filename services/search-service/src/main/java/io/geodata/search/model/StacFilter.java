
package io.geodata.search.model;

import io.micronaut.serde.annotation.Serdeable;
import java.util.List;
import java.util.Map;

@Serdeable
public class StacFilter {
    public List<Double> bbox;
    public String dt_from;
    public String dt_to;
    public List<String> collections;
    public Map<String, Object> intersects;
    public String q;
    public String crs = "EPSG:4326";
    public Integer limit;
    public Integer offset;
}
