
#!/usr/bin/env python3
import json, argparse, datetime as dt

def gen(bbox, tiles, start, end, collection="test-collection"):
    minx,miny,maxx,maxy = bbox
    nx, ny = tiles
    dx = (maxx-minx)/nx; dy = (maxy-miny)/ny
    cur = start
    while cur <= end:
        for i in range(nx):
            for j in range(ny):
                x0 = minx + i*dx; x1 = x0 + dx
                y0 = miny + j*dy; y1 = y0 + dy
                geom = {"type":"Polygon","coordinates":[[[x0,y0],[x1,y0],[x1,y1],[x0,y1],[x0,y0]]]}
                item = {
                    "id": f"{collection}-{cur.strftime('%Y%m%d')}-{i}-{j}",
                    "collection": collection,
                    "type": "Feature",
                    "geometry": geom,
                    "properties": {"datetime": cur.strftime("%Y-%m-%dT00:00:00Z")}
                }
                yield item
        cur += dt.timedelta(days=1)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bbox", required=True, help="minx,miny,maxx,maxy")
    ap.add_argument("--tiles", required=True, help="nx,ny")
    ap.add_argument("--from", dest="start", required=True)
    ap.add_argument("--to", dest="end", required=True)
    ap.add_argument("--collection", default="test-collection")
    args = ap.parse_args()
    bbox = [float(x) for x in args.bbox.split(",")]
    tiles = [int(x) for x in args.tiles.split(",")]
    start = dt.datetime.fromisoformat(args.start)
    end = dt.datetime.fromisoformat(args.end)
    for item in gen(bbox, tiles, start, end, args.collection):
        print(json.dumps(item))

if __name__ == "__main__":
    main()
