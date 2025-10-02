from __future__ import annotations

import math
from pathlib import Path
from typing import Iterable, Optional, Sequence

import rasterio
from rasterio.crs import CRS
from rasterio.errors import RasterioError
from rasterio.vrt import WarpedVRT
from rasterio.windows import from_bounds


class ClipError(RuntimeError):
    """Raised when clipping or reprojection fails."""


def _prepare_bounds(dataset, bbox: Optional[Sequence[float]]):
    if bbox is None:
        return dataset.bounds
    if len(bbox) != 4:
        raise ClipError("bbox must contain exactly four numeric values")
    minx, miny, maxx, maxy = map(float, bbox)
    if minx >= maxx or miny >= maxy:
        raise ClipError("bbox coordinates are invalid (min must be < max)")
    return (minx, miny, maxx, maxy)


def _round_window(window):
    return window.round_offsets(op=math.floor).round_lengths(op=math.ceil)


def clip_geotiff(
    source_path: Path,
    dest_path: Path,
    bbox: Optional[Iterable[float]],
    target_crs: Optional[str],
) -> None:
    """Clip (and optionally reproject) a GeoTIFF to the requested bbox/CRS."""

    try:
        with rasterio.Env():
            with rasterio.open(source_path) as src:
                desired_crs = _target_crs(src, target_crs)
                if desired_crs and src.crs and desired_crs != src.crs:
                    with WarpedVRT(src, crs=desired_crs) as vrt:
                        _write_clip(vrt, dest_path, bbox)
                else:
                    _write_clip(src, dest_path, bbox)
    except RasterioError as exc:
        raise ClipError(str(exc)) from exc


def _write_clip(dataset, dest_path: Path, bbox: Optional[Iterable[float]]):
    bounds = _prepare_bounds(dataset, bbox)
    window = from_bounds(*bounds, transform=dataset.transform)
    window = _round_window(window)
    if window.width <= 0 or window.height <= 0:
        raise ClipError("computed window has non-positive size; check bbox")

    data = dataset.read(window=window, boundless=True, fill_value=dataset.nodata)
    transform = dataset.window_transform(window)

    profile = dataset.profile.copy()
    profile.update(
        driver="GTiff",
        height=data.shape[1],
        width=data.shape[2],
        transform=transform,
        crs=dataset.crs,
    )
    if dataset.nodata is not None:
        profile.setdefault("nodata", dataset.nodata)

    dest_path.parent.mkdir(parents=True, exist_ok=True)
    with rasterio.open(dest_path, "w", **profile) as dst:
        dst.write(data)


def _target_crs(src, target_crs: Optional[str]) -> Optional[CRS]:
    if not target_crs:
        return src.crs
    candidate = CRS.from_user_input(target_crs)
    if src.crs is None:
        return candidate
    return candidate
