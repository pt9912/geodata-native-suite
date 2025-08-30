package io.geodata.search.database;

import io.geodata.search.*;
import io.geodata.search.model.*;
import java.util.*;

import javax.sql.DataSource;
import java.sql.*;
import java.util.stream.Collectors;

public class QuerySpatiaLite implements QueryDb {

    DataSource ds;

    QuerySpatiaLite(DataSource ds) {
        this.ds = ds;
    }

    public List<ItemOut> query(StacFilter filter) {

        StringBuilder where = new StringBuilder("1=1");
        List<Object> params = new ArrayList<>();

        if (!filter.dt_from.isEmpty()) {
            where.append(" AND dt >= ?");
            params.add(filter.dt_from);
        }
        if (!filter.dt_to.isEmpty()) {
            where.append(" AND dt <= ?");
            params.add(filter.dt_to);
        }
        if (!filter.collections.isEmpty()) {
            List<String> collections = filter.collections.stream()
                .filter(s -> !s.isEmpty())  // Entfernt nur "" (leere Strings)
                .collect(Collectors.toList());
            if (!collections.isEmpty()) {
                where.append(" AND collection IN (" +
                        String.join(",", Collections.nCopies(collections.size(), "?")) +
                    ")");
                params.addAll(collections);
            }
        } 
        if (!filter.q.isEmpty()) {
            where.append(" AND (id LIKE ? OR collection LIKE ? OR COALESCE(props,'') LIKE ?)");
            String like = "%" + filter.q + "%";
            params.add(like);
            params.add(like);
            params.add(like);
        }

        if (!filter.bbox.isEmpty()) {
            //minX, minY, maxX, maxY,
            where.append(" AND ST_Intersects(geom, BuildMBR(?, ?, ?, ?, '4326'))");
            params.addAll(filter.bbox);
        }

        String sql = "SELECT id, collection, dt, MbrMinX(geom), MbrMinY(geom), MbrMaxX(geom), MbrMaxY(geom) " +
                     "FROM items WHERE " + where + " ORDER BY dt DESC LIMIT ? OFFSET ?";
        params.add(filter.limit);
        params.add(filter.offset);

        try (Connection c = ds.getConnection();
             PreparedStatement ps = c.prepareStatement(sql)) {

            for (int i = 0; i < params.size(); i++) {
                ps.setObject(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {
                List<ItemOut> out = new ArrayList<>();
                while (rs.next()) {
                    out.add(new ItemOut(
                        rs.getString(1),
                        rs.getString(2),
                        rs.getString(3),
                        List.of(rs.getDouble(4), rs.getDouble(5), rs.getDouble(6), rs.getDouble(7))
                    ));
                }
                return out;
            }
        } catch (SQLException e) {
            throw new RuntimeException("Fehler beim Initialisieren der Datenbank", e);
        }            

    }
}