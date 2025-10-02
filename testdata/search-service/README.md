# Testdaten für den search-service

Die SQL-Skripte in diesem Verzeichnis stellen kleine, reproduzierbare Datensätze
für manuelle oder automatisierte Tests des `search-service` bereit.

## PostGIS / TimescaleDB

```
psql "postgresql://app:apppw@localhost:5432/geodata" \
  -f testdata/search-service/postgis-items.sql
```

Damit wird die Tabelle `items` neu befüllt. Anschließend können die Endpunkte
des `search-service` (GET `/api/v1/search/search`, POST `/api/v1/search`) mit
BBox-, CRS- und Textfiltern getestet werden.

## SQLite / SpatiaLite

```
spatialite geodata.db < testdata/search-service/spatialite-items.sql
```

Das Skript initialisiert die Tabelle `items` inkl. Geometriespalte und fügt die
identischen Testfeatures ein.

> Hinweis: Die Testgeometrien decken einen Ausschnitt in Mitteleuropa ab und
> eignen sich sowohl für EPSG:4326 als auch EPSG:3857 Abfragen.
