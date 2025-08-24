
package io.geodata.search.model;

import io.micronaut.serde.annotation.Serdeable;
import java.util.List;
import java.util.Map;

@Serdeable
public class StacFilter {
    public List<Double> bbox;
    public String datetime;
    public List<String> collections;
    public Map<String, Object> intersects;
    public String q;
    public String crs = "EPSG:4326";
}
