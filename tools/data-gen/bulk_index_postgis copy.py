
#!/usr/bin/env python3
import sys, json, argparse, psycopg
from psycopg.rows import dict_row

def ensure(conn):
    with conn.cursor() as cur:
        cur.execute("CREATE EXTENSION IF NOT EXISTS postgis;")
        cur.execute("CREATE TABLE IF NOT EXISTS collections (id text PRIMARY KEY)")
        cur.execute("""
            CREATE TABLE IF NOT EXISTS items (
              id text PRIMARY KEY,
              collection text NOT NULL REFERENCES collections(id),
              dt timestamptz NOT NULL,
              geom geometry(GEOMETRY,4326) NOT NULL,
              props jsonb
            );""")
        conn.commit()

def ingest(conn, item):
    props = item.get("properties") or {}
    dt = props.get("datetime") or props.get("start_datetime") or props.get("end_datetime")
    coll = item.get("collection","test-collection")
    geom = json.dumps(item.get("geometry"))
    with conn.cursor() as cur:
        cur.execute("INSERT INTO collections(id) VALUES (%s) ON CONFLICT (id) DO NOTHING",(coll,))
        cur.execute("""
            INSERT INTO items(id, collection, dt, geom, props)
            VALUES (%s,%s,%s, ST_SetSRID(ST_GeomFromGeoJSON(%s),4326), %s::jsonb)
            ON CONFLICT (id) DO UPDATE SET collection=EXCLUDED.collection, dt=EXCLUDED.dt, geom=EXCLUDED.geom, props=EXCLUDED.props
        """, (item["id"], coll, dt, geom, json.dumps(props)))
        conn.commit()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pg", required=True, help="postgresql://user:pass@host:port/db")
    args = ap.parse_args()
    conn = psycopg.connect(args.pg)
    ensure(conn)
    for line in sys.stdin:
        line=line.strip()
        if not line: continue
        item = json.loads(line)
        ingest(conn, item)
    conn.close()

if __name__ == "__main__":
    main()
