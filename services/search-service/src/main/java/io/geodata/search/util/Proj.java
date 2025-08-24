
package io.geodata.search.util;

import java.util.List;
import java.util.ArrayList;

public final class Proj {
    private static final double ORIGIN_SHIFT = 20037508.342789244;
    private Proj() {}

    // EPSG:3857 bbox to EPSG:4326
    public static List<Double> bbox3857to4326(List<Double> bbox) {
        if (bbox == null || bbox.size() != 4) return bbox;
        double minx = bbox.get(0), miny = bbox.get(1), maxx = bbox.get(2), maxy = bbox.get(3);
        double minLon = (minx / ORIGIN_SHIFT) * 180.0;
        double maxLon = (maxx / ORIGIN_SHIFT) * 180.0;
        double minLat = rad2deg(Math.atan(Math.sinh((miny / ORIGIN_SHIFT) * Math.PI)));
        double maxLat = rad2deg(Math.atan(Math.sinh((maxy / ORIGIN_SHIFT) * Math.PI)));
        List<Double> out = new ArrayList<>();
        out.add(minLon); out.add(minLat); out.add(maxLon); out.add(maxLat);
        return out;
    }
    private static double rad2deg(double rad) { return rad * 180.0 / Math.PI; }
}
