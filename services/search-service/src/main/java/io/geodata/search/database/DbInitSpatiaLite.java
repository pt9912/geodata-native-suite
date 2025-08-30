package io.geodata.search.database;

import javax.sql.DataSource;
import java.sql.*;


public class DbInitSpatiaLite {

    public static void init(DataSource ds) {

        try (Connection connection = ds.getConnection();
            Statement st = connection.createStatement()) {
            DatabaseMetaData metaData = connection.getMetaData();

            // 1. Datenbankproduktname abfragen
            String databaseProductName = metaData.getDatabaseProductName();
            System.out.println("Datenbankprodukt: " + databaseProductName);

            // 2. Je nach Produkt weiter prüfen
            if (databaseProductName.equalsIgnoreCase("SQLite")) {
                try {
                    st.execute("SELECT load_extension('mod_spatialite')");
                } catch (SQLException e) {
                    // Ignorieren, falls die Extension bereits geladen ist
                }

                st.execute("CREATE TABLE IF NOT EXISTS items (" +
                    "id TEXT PRIMARY KEY, " +
                    "collection TEXT, " +
                    "dt TEXT, " +
                    "geom TEXT, " +
                    "props TEXT" +
                ")");

                st.execute("CREATE INDEX IF NOT EXISTS idx_items_dt ON items(dt)");
                st.execute("CREATE INDEX IF NOT EXISTS idx_items_collection ON items(collection)");
            }
        } catch (SQLException e) {
            throw new RuntimeException("Fehler beim Initialisieren der Datenbank", e);
        }
    }
}
