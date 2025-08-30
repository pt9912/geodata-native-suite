#!/usr/bin/env python3
import sys
import json
import argparse
import sqlite3
from sqlite3 import Error

def ensure(conn):
    cursor = conn.cursor()

    # 1. SpatiaLite-Erweiterung laden (ignoriere Fehler)
    try:
        cursor.execute("SELECT load_extension('mod_spatialite')")
       
    except Error:
        pass  # Bereits geladen

    # 2. Prüfe, ob spatial_ref_sys bereits existiert (Idempotenz für InitSpatialMetaData)
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='spatial_ref_sys'")
    if not cursor.fetchone():
        try:
            cursor.execute("SELECT InitSpatialMetaData(1)")
            #cursor.execute("SELECT InitSpatialMetaDataFull()")
        except Error:
            pass  # Metadaten bereits initialisiert

    # 3. Tabellen erstellen (falls nicht vorhanden)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS collections (
            id TEXT PRIMARY KEY
        )
    """)

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS items (
            id TEXT PRIMARY KEY,
            collection TEXT NOT NULL,
            dt TIMESTAMP,
            props TEXT,
            FOREIGN KEY (collection) REFERENCES collections(id)
        )
    """)
    conn.execute("CREATE INDEX IF NOT EXISTS idx_items_dt ON items(dt)")
    conn.execute("CREATE INDEX IF NOT EXISTS idx_items_collection ON items(collection)")

    # 4. Prüfe, ob 'geom' bereits eine Geometriespalte ist
    cursor.execute("PRAGMA table_info(items)")
    columns = cursor.fetchall()
    geom_column = next((col for col in columns if col[1] == 'geom'), None)

    if geom_column is None:
        # Spalte existiert nicht → hinzufügen
        cursor.execute("SELECT AddGeometryColumn('items', 'geom', 4326, 'GEOMETRY', 'XY', 1)")
    else:
        # Prüfe, ob es eine Geometriespalte ist (via geometry_columns)
        cursor.execute("""
            SELECT f_table_name, f_geometry_column
            FROM geometry_columns
            WHERE f_table_name = 'items' AND f_geometry_column = 'geom'
        """)
        if not cursor.fetchone():
            # Spalte existiert, aber ist keine Geometrie → Fehler
            raise Error("Spalte 'geom' existiert, ist aber keine Geometriespalte!")

    # 5. Räumlichen Index erstellen (falls nicht vorhanden)
    cursor.execute("""
        SELECT name FROM sqlite_master
        WHERE type='table' AND name LIKE 'idx_items_geom%'
    """)
    if not cursor.fetchone():
        try:
            cursor.execute("SELECT CreateSpatialIndex('items', 'geom')")
        except Error as e:
            if "already defined" not in str(e):
                raise  # Unerwarteter Fehler

    conn.commit()



def ingest(conn, item):
    props = item.get("properties") or {}
    dt = props.get("datetime") or props.get("start_datetime") or props.get("end_datetime")
    coll = item.get("collection", "test-collection")
    geom = json.dumps(item.get("geometry"))  # GeoJSON als String

    #print(f"geom: {geom}")
    cursor = conn.cursor()

    # Sammlung einfügen (falls nicht vorhanden)
    cursor.execute(
        "INSERT INTO collections(id) VALUES (?) ON CONFLICT(id) DO NOTHING",
        (coll,)
    )

    # Item einfügen oder aktualisieren
    try:
        cursor.execute("""
            INSERT INTO items(id, collection, dt, geom, props)
            VALUES (?, ?, ?, SetSRID(GeomFromGeoJSON(?), 4326), ?)
            ON CONFLICT(id) DO UPDATE SET
                collection = EXCLUDED.collection,
                dt = EXCLUDED.dt,
                geom = EXCLUDED.geom,
                props = EXCLUDED.props
        """, (item["id"], coll, dt, geom, json.dumps(props)))
        conn.commit()
    except Error as e:
        print(f"Fehler beim Einfügen von {item['id']}: {e}")
        conn.rollback()

def ingest_batch(conn, items):
    cursor = conn.cursor()
    for item in items:
        props = item.get("properties") or {}
        dt = props.get("datetime") or props.get("start_datetime") or props.get("end_datetime")
        coll = item.get("collection", "test-collection")
        geom = json.dumps(item.get("geometry"))

        cursor.execute(
            "INSERT INTO collections(id) VALUES (?) ON CONFLICT(id) DO NOTHING",
            (coll,)
        )
        cursor.execute("""
            INSERT INTO items(id, collection, dt, geom, props)
            VALUES (?, ?, ?, SetSRID(GeomFromGeoJSON(?), 4326), ?)
            ON CONFLICT(id) DO UPDATE SET
                collection = EXCLUDED.collection,
                dt = EXCLUDED.dt,
                geom = EXCLUDED.geom,
                props = EXCLUDED.props
        """, (item["id"], coll, dt, geom, json.dumps(props)))
    conn.commit()  # Ein Commit für alle Items
    
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True, help="Pfad zur SQLite-Datenbank (z. B. /data/geodata.db)")
    ap.add_argument("--batch", action="store_true", help="Batch-Modus aktivieren")
    ap.add_argument("--batch-size", type=int, default=100, help="Anzahl Items pro Batch (Default: 100)")
    args = ap.parse_args()

    # SQLite-Datenbank verbinden
    conn = sqlite3.connect(args.db)
    conn.enable_load_extension(True)  # Erlaube Erweiterungen

    ensure(conn)

    items_count = 0
    if args.batch:
        items = []
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                items_count += 1
                items.append(json.loads(line))
                if len(items) >= args.batch_size:
                    ingest_batch(conn, items)
                    items = []
                    if items_count % 100 == 0:
                        print(f"\rVerarbeitet: {items_count} Items...", end="", file=sys.stderr)
            except json.JSONDecodeError:
                print(f"ERROR: Ungültiges JSON: {line}", file=sys.stderr)
                continue

        if items:
            ingest_batch(conn, items)        
    else:
        for line in sys.stdin:
            #print(f"{line}")
            line = line.strip()
            if not line:
                #print(f"No line")
                continue
            try:
                items_count += 1
                item = json.loads(line)
                #print(f"DEBUG: Verarbeite Item {item['id']}", file=sys.stderr)  # Debug-Ausgabe
                ingest(conn, item)
                if items_count % 100 == 0:
                    print(f"\rVerarbeitet: {items_count} Items...", end="", file=sys.stderr)
                
            except json.JSONDecodeError as e:
                print(f"ERROR: Ungültiges JSON: {line}", file=sys.stderr)
            except Exception as e:
                print(f"ERROR: Fehler bei Item {line}: {e}", file=sys.stderr)
                raise

    print(f"\ndone. {items_count} items")
      
    conn.commit()   
    conn.close()

if __name__ == "__main__":
    main()
