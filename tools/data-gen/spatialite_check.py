import sqlite3

conn = sqlite3.connect(":memory:")
conn.enable_load_extension(True)
cursor = conn.cursor()

# SpatiaLite laden
cursor.execute("SELECT load_extension('/usr/lib/x86_64-linux-gnu/mod_spatialite.so')")
cursor.execute("SELECT InitSpatialMetaData(1)")

# Tabelle löschen, falls sie existiert
cursor.execute("DROP TABLE IF EXISTS test_points")

# Tabelle erstellen
cursor.execute("""
    CREATE TABLE test_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT
    )
""")

# Geometriespalte hinzufügen
cursor.execute("SELECT AddGeometryColumn('test_points', 'geometry', 4326, 'POINT', 'XY')")

# Punkt einfügen
cursor.execute("""
    INSERT INTO test_points (name, geometry)
    VALUES ('Zürich', MakePoint(8.5417, 47.3769, 4326))
""")

# Abfrage
cursor.execute("SELECT name, AsText(geometry) FROM test_points")
print(cursor.fetchall())

conn.commit()
conn.close()
