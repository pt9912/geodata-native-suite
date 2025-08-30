
#!/usr/bin/env python3
from osgeo import gdal, osr
import numpy as np
import argparse, os, sys, math

def make_array(width, height, bands, dtype, pattern):
    dt = np.dtype(dtype)
    if pattern == "gradient":
        x = np.linspace(0, 1, num=width, dtype=dt)
        y = np.linspace(0, 1, num=height, dtype=dt)
        arr = np.outer(y, x)
        data = np.stack([arr]*bands, axis=0)
    elif pattern == "noise":
        rng = np.random.default_rng(42)
        data = rng.random((bands, height, width), dtype=dt)
    elif pattern == "ramps":
        data = np.zeros((bands, height, width), dtype=dt)
        for b in range(bands):
            data[b,:,:] = ((np.arange(width, dtype=dt)[None,:] + np.arange(height, dtype=dt)[:,None]) % (256 if 'int' in dtype else 1.0))
    else:
        data = np.zeros((bands, height, width), dtype=dt)
    return data

def write_gtiff(path, data, geotransform, crs_epsg, tiled=True, blockx=512, blocky=512, compress="DEFLATE", predictor=2, nodata=None):
    bands, height, width = data.shape
    driver = gdal.GetDriverByName('GTiff')
    dtype_map = {
        'uint8': gdal.GDT_Byte, 'int16': gdal.GDT_Int16, 'uint16': gdal.GDT_UInt16,
        'int32': gdal.GDT_Int32, 'uint32': gdal.GDT_UInt32,
        'float32': gdal.GDT_Float32, 'float64': gdal.GDT_Float64
    }
    gdal_dtype = dtype_map.get(str(data.dtype), gdal.GDT_Float32)
    opts = ['TILED=YES' if tiled else 'TILED=NO', f'BLOCKXSIZE={blockx}', f'BLOCKYSIZE={blocky}', f'COMPRESS={compress}', f'PREDICTOR={predictor}']
    ds = driver.Create(path, width, height, bands, gdal_dtype, options=opts)
    ds.SetGeoTransform(geotransform)
    if crs_epsg:
        srs = osr.SpatialReference(); srs.ImportFromEPSG(crs_epsg)
        ds.SetProjection(srs.ExportToWkt())
    for i in range(bands):
        rb = ds.GetRasterBand(i+1)
        rb.WriteArray(data[i])
        if nodata is not None: rb.SetNoDataValue(nodata)
        rb.FlushCache()
    ds.FlushCache(); ds = None

def to_cog(src, dst, compress):
    # requires GDAL>=3.1 with COG driver
    if compress:
        gdal.Translate(dst, src, format="COG", creationOptions=[
            "COMPRESS=DEFLATE","LEVEL=9","PREDICTOR=2","RESAMPLING=AVERAGE","OVERVIEWS=AUTO","BLOCKSIZE=512"
        ])
    else:
        gdal.Translate(dst, src, format="COG", creationOptions=[
            "RESAMPLING=AVERAGE","OVERVIEWS=AUTO","BLOCKSIZE=512"
        ])

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, required=True)
    ap.add_argument("--height", type=int, required=True)
    ap.add_argument("--bands", type=int, default=1)
    ap.add_argument("--dtype", default="float32", choices=["uint8","int16","uint16","int32","uint32","float32","float64"])
    ap.add_argument("--pattern", default="gradient", choices=["gradient","noise","ramps","zeros"])
    ap.add_argument("--epsg", type=int, default=4326)
    ap.add_argument("--bbox", default="-10,40,10,60", help="minx,miny,maxx,maxy for geotransform")
    ap.add_argument("--compress", type=bool, default=False)
    ap.add_argument("--outfile", required=True)
    ap.add_argument("--cog", action="store_true")
    args = ap.parse_args()

    minx, miny, maxx, maxy = [float(x) for x in args.bbox.split(",")]
    px = (maxx-minx)/args.width; py = (maxy-miny)/args.height
    gt = (minx, px, 0.0, maxy, 0.0, -py)

    data = make_array(args.width, args.height, args.bands, args.dtype, args.pattern)
    tmp = args.outfile if not args.cog else args.outfile+".tmp.tif"
    os.makedirs(os.path.dirname(args.outfile) or ".", exist_ok=True)
    write_gtiff(tmp, data, gt, args.epsg)
    if args.cog:
        to_cog(tmp, args.outfile, args.compress)
        os.remove(tmp)
    print(f"Wrote {args.outfile}", file=sys.stderr)

if __name__ == "__main__":
    main()
