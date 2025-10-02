package io.geodata.search.util;

import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Utility methods for parsing CRS identifiers of the form EPSG:XXXX. */
public final class Crs {
    private static final Pattern EPSG_PATTERN = Pattern.compile("EPSG:(\\d+)", Pattern.CASE_INSENSITIVE);

    private Crs() {}

    public static int srid(String crs) {
        if (crs == null || crs.isBlank()) {
            return 4326;
        }
        String normalized = crs.trim().toUpperCase(Locale.ROOT);
        if ("EPSG:4326".equals(normalized)) {
            return 4326;
        }
        Matcher matcher = EPSG_PATTERN.matcher(normalized);
        if (matcher.matches()) {
            return Integer.parseInt(matcher.group(1));
        }
        throw new IllegalArgumentException("Unsupported CRS: " + crs);
    }
}
