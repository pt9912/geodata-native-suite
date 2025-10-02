-- Sample STAC-like items for PostGIS based integration tests
-- Usage:
--   psql "$POSTGRES_URL" -f postgis-items.sql

BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS items (
    id          TEXT PRIMARY KEY,
    collection  TEXT NOT NULL,
    dt          TIMESTAMP WITH TIME ZONE NOT NULL,
    geom        geometry(POLYGON, 4326) NOT NULL,
    props       JSONB DEFAULT '{}'::jsonb
);

TRUNCATE items;

INSERT INTO items (id, collection, dt, geom, props) VALUES
  (
    'S2A_20250101T101031_Z34T',
    'sentinel-2-l2a',
    '2025-01-01T10:10:31Z',
    ST_GeomFromText('POLYGON((12.0 52.0, 12.3 52.0, 12.3 52.2, 12.0 52.2, 12.0 52.0))', 4326),
    jsonb_build_object('cloud_cover', 3.2, 'platform', 'Sentinel-2A')
  ),
  (
    'S2B_20250215T094021_Z33U',
    'sentinel-2-l2a',
    '2025-02-15T09:40:21Z',
    ST_GeomFromText('POLYGON((11.5 51.8, 12.1 51.8, 12.1 52.1, 11.5 52.1, 11.5 51.8))', 4326),
    jsonb_build_object('cloud_cover', 15.0, 'platform', 'Sentinel-2B')
  ),
  (
    'L8_20250303T104512_P198',
    'landsat-8-l1',
    '2025-03-03T10:45:12Z',
    ST_GeomFromText('POLYGON((8.9 49.9, 9.3 49.9, 9.3 50.2, 8.9 50.2, 8.9 49.9))', 4326),
    jsonb_build_object('cloud_cover', 5.8, 'platform', 'Landsat-8')
  );

COMMIT;
