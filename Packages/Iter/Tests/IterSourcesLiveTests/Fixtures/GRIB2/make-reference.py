#!/usr/bin/env python3
"""Writes <name>.eccodes.json next to every <name>.grib2 in this folder: the independent ecCodes reading of each
fixture that the Swift tests compare the decoder against.

Needs the `eccodes` Python package (ecCodes >= 2.3x; the committed JSON came from 2.50):
    python3 -m venv venv && venv/bin/pip install eccodes
    venv/bin/python -I make-reference.py
Not part of the build; the venv is never committed.

Per message: identification keys, the decoded values, and ecCodes' nearest-point result for the file's test point
(W = Mount Whitney for hrrr-W / gfs-W files, S = Swiss Alps for gfs-S files). Grid latitudes/longitudes are stored
once per file under "grid" (every message in a file shares one grid), rounded to 6 decimals. For regular lat/lon
(GFS) files "bilinear" is an independent bilinear interpolation at the test point, computed here from ecCodes' own
coordinates.
"""
import glob, json, math, os, sys
import eccodes as ec

HERE = os.path.dirname(os.path.abspath(__file__))
POINTS = {"W": (36.5785, -118.2923), "S": (46.5586, 8.5610)}


def keys(h, *names):
    return {n: ec.codes_get_long(h, n) for n in names}


def bilinear(values, lats, lons, ni, nj, lat, lon):
    """Bilinear on a regular lat/lon grid (data order, row-major j then i), independent of the Swift code."""
    la = [lats[j * ni] for j in range(nj)]
    lo = [lons[i] for i in range(ni)]
    lon_n = lon % 360.0 if min(lo) >= 0 else lon

    def bracket(axis, x):
        asc = axis[-1] > axis[0]
        for k in range(len(axis) - 1):
            a, b = axis[k], axis[k + 1]
            if (a <= x <= b) if asc else (b <= x <= a):
                return k, (x - a) / (b - a)
        return None

    bj, bi = bracket(la, lat), bracket(lo, lon_n)
    if bj is None or bi is None:
        return None
    (j, fj), (i, fi) = bj, bi
    v = lambda jj, ii: values[jj * ni + ii]
    top = v(j, i) * (1 - fi) + v(j, i + 1) * fi
    bot = v(j + 1, i) * (1 - fi) + v(j + 1, i + 1) * fi
    return top * (1 - fj) + bot * fj


def convert(path):
    name = os.path.basename(path)[:-len(".grib2")]
    plat, plon = POINTS[name.split("-")[1]]
    out = {"file": name + ".grib2", "testPoint": {"lat": plat, "lon": plon}, "messages": []}
    with open(path, "rb") as f:
        while True:
            h = ec.codes_grib_new_from_file(f)
            if h is None:
                break
            m = keys(h, "discipline", "parameterCategory", "parameterNumber", "typeOfFirstFixedSurface", "level",
                     "productDefinitionTemplateNumber", "dataRepresentationTemplateNumber",
                     "gridDefinitionTemplateNumber", "forecastTime", "dataDate", "dataTime")
            m["stepRange"] = ec.codes_get_string(h, "stepRange")
            grid_t = m["gridDefinitionTemplateNumber"]
            nx, ny = (keys(h, "Ni", "Nj") if grid_t == 0 else keys(h, "Nx", "Ny")).values()
            m["nx"], m["ny"] = nx, ny
            vals = [None if (isinstance(v, float) and math.isnan(v)) else float(v)
                    for v in ec.codes_get_values(h)]
            m["values"] = vals
            if "grid" not in out:
                lats, lons = ec.codes_get_array(h, "latitudes"), ec.codes_get_array(h, "longitudes")
                out["grid"] = {"lats": [round(float(x), 6) for x in lats], "lons": [round(float(x), 6) for x in lons]}
                grid_lats, grid_lons = [float(x) for x in lats], [float(x) for x in lons]
            near = ec.codes_grib_find_nearest(h, plat, plon)
            best = min(near, key=lambda n: n["distance"])
            m["nearest"] = {"index": int(best["index"]), "lat": round(best["lat"], 6), "lon": round(best["lon"], 6),
                            "value": best["value"], "distance": best["distance"]}
            if grid_t == 0 and None not in vals:
                m["bilinear"] = bilinear(vals, grid_lats, grid_lons, nx, ny, plat, plon)
            out["messages"].append(m)
            ec.codes_release(h)
    with open(os.path.join(HERE, name + ".eccodes.json"), "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print(name, len(out["messages"]), "messages")


if __name__ == "__main__":
    for p in sorted(glob.glob(os.path.join(HERE, "*.grib2"))):
        convert(p)
