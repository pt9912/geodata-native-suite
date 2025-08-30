package io.geodata.search.database;

//import io.micronaut.context.annotation.Bean;
import io.micronaut.context.annotation.Factory;
import jakarta.inject.Singleton;
import javax.sql.DataSource;
import java.sql.*;

@Factory
public class QueryDBFactory {

    @Singleton
    public QueryDb queryDb(DataSource ds) {
        try (Connection connection = ds.getConnection();) {
            DatabaseMetaData metaData = connection.getMetaData();

            // 1. Datenbankproduktname abfragen
            String databaseProductName = metaData.getDatabaseProductName();
            System.out.println("Datenbankprodukt: " + databaseProductName);

            if (databaseProductName.equalsIgnoreCase("SQLite")) {
                DbInitSpatiaLite.init(ds);
                return new QuerySpatiaLite(ds);
            } else if (databaseProductName.equalsIgnoreCase("PostgreSQL")) {
                return new QueryPostGis(ds);
            } else {
                System.out.println("Unbekannte Datenbank: " + databaseProductName);
            }
            return null;
        } catch (SQLException e) {
            throw new RuntimeException("Fehler beim Initialisieren der Datenbank", e);
        }                          
    }
}
