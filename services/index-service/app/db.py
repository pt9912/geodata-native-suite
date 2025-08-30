import os
import sqlite3
from sqlite3 import Error
import json
import geojson
from geojson import Feature, Point, Polygon
from typing import Optional, Dict, Any
import psycopg

def getenv(name: str, default: Optional[str] = None) -> str:
    return os.getenv(name, default)

POSTGRES = getenv("DB_DIALECT", "postgres").lower().startswith("post")
SQLITE = getenv("DB_DIALECT", "").lower().startswith("sqlite")

PG_CFG = {
    "host": getenv("DB_HOST", "postgres"),
    "port": int(getenv("DB_PORT", "5432")),
    "dbname": getenv("DB_NAME", "geodata"),
    "user": getenv("DB_USER", "app"),
    "password": getenv("DB_PASSWORD", "apppw"),
}
SQLITE_PATH = getenv("SQLITE_PATH", "/var/lib/search/search.db")

def init_schema() -> None:
    if POSTGRES:
        with psycopg.connect(**PG_CFG) as conn, conn.cursor() as cur:
            cur.execute("CREATE EXTENSION IF NOT EXISTS postgis;")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS collections (
                    id text PRIMARY KEY
                );
                CREATE TABLE IF NOT EXISTS items (
                    id text PRIMARY KEY,
                    collection text NOT NULL REFERENCES collections(id),
                    dt timestamptz NOT NULL,
                    geom geometry(GEOMETRY, 4326),
                    props jsonb
                );
                CREATE INDEX IF NOT EXISTS idx_items_geom ON items USING GIST (geom);
                CREATE INDEX IF NOT EXISTS idx_items_dt ON items (dt);
                CREATE INDEX IF NOT EXISTS idx_items_coll_dt ON items (collection, dt);
                ALTER TABLE items DROP COLUMN IF EXISTS tsv;
                ALTER TABLE items ADD COLUMN IF NOT EXISTS tsv tsvector
                    GENERATED ALWAYS AS (
                        to_tsvector('simple', coalesce(id,'')||' '||coalesce(collection,'')||' '||coalesce(props::text,''))
                    ) STORED;
                CREATE INDEX IF NOT EXISTS idx_items_tsv ON items USING GIN (tsv);
            """)
            conn.commit()
    else:
        os.makedirs(os.path.dirname(SQLITE_PATH), exist_ok=True)
        conn = sqlite3.connect(SQLITE_PATH)
        conn.enable_load_extension(True)  # Erlaube Erweiterungen
        spatialite_ensure(conn)
        conn.close()
            
def spatialite_ensure(conn):
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



def get_item_props(id: str) -> Optional[Dict[str, Any]]:
    if POSTGRES:
        with psycopg.connect(**PG_CFG) as conn, conn.cursor() as cur:
            cur.execute("SELECT props::text FROM items WHERE id=%s", (id,))
            row = cur.fetchone()
            return json.loads(row[0]) if row and row[0] else None
    else:
        conn = sqlite3.connect(SQLITE_PATH)
        try:
            cur = conn.execute("SELECT props FROM items WHERE id=?", (id,))
            row = cur.fetchone()
            return json.loads(row[0]) if row and row[0] else None
        finally:
            conn.close()

def validate_geojson(geom_geojson: Optional[Dict[str, Any]]) -> bool:
    if geom_geojson is None:
        return True
    try:
        geojson.GeoJSON.to_instance(geom_geojson)
        return True
    except Exception:
        return False

def upsert_item(
    id: str,
    collection: str,
    dt_iso: str,
    geom_geojson: Optional[Dict[str, Any]],
    props: Dict[str, Any]
) -> str:
    if geom_geojson and not isinstance(geom_geojson, dict):
        raise ValueError("geom_geojson must be a dictionary or None")
    if geom_geojson and not validate_geojson(geom_geojson):
        raise ValueError("Invalid GeoJSON")

    prev = get_item_props(id)
    state = "indexed" if prev is None else "updated"

    if POSTGRES:
        with psycopg.connect(**PG_CFG) as conn, conn.cursor() as cur:
            # Collection sicherstellen
            cur.execute(
                "INSERT INTO collections(id) VALUES (%s) ON CONFLICT (id) DO NOTHING",
                (collection,)
            )
            # Item einfügen oder aktualisieren
            cur.execute("""
                INSERT INTO items(id, collection, dt, geom, props)
                VALUES (
                    %s, %s, %s::timestamptz,
                    CASE
                        WHEN %s IS NULL THEN NULL
                        ELSE ST_SetSRID(ST_GeomFromGeoJSON(%s), 4326)
                    END,
                    %s::jsonb
                )
                ON CONFLICT (id) DO UPDATE SET
                    collection=EXCLUDED.collection,
                    dt=EXCLUDED.dt,
                    geom=EXCLUDED.geom,
                    props=EXCLUDED.props
            """, (
                id,
                collection,
                dt_iso,
                None if geom_geojson is None else json.dumps(geom_geojson),
                None if geom_geojson is None else json.dumps(geom_geojson),
                json.dumps(props)
            ))
            conn.commit()
    else:
        conn = sqlite3.connect(SQLITE_PATH)
        try:
            props_text = json.dumps(props, ensure_ascii=False)
            geom_text = json.dumps(geom_geojson) if geom_geojson else None
            conn.execute(
                "INSERT OR IGNORE INTO collections(id) VALUES (?)",
                (collection,)
            )
            conn.execute("""
                INSERT INTO items(id, collection, dt, geom, props)
                VALUES (?, ?, ?, SetSRID(GeomFromGeoJSON(?), 4326), ?)
                ON CONFLICT(id) DO UPDATE SET
                    collection=excluded.collection,
                    dt=excluded.dt,
                    geom=excluded.geom,
                    props=excluded.props
            """, (
                id,
                collection,
                dt_iso,
                geom_text,
                props_text
            ))
            conn.commit()
        finally:
            conn.close()

    return state
