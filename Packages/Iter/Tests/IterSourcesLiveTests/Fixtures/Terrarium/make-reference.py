#!/usr/bin/env python3 -I
"""Independent reference for the Terrarium decoder: a pure-Python PNG decoder (zlib + filter reversal, no ImageIO,
no third-party code) reads the two recorded tiles and writes reference.json next to this script.

Run:  python3 -I make-reference.py        (paths are relative to this script; stdlib only)

For each tile it records: tile coordinate, size, FNV-1a 64 checksum of all RGB bytes (rows top to bottom, R G B per
pixel), and 20 sample pixels (4 corners, the test point's pixel, 15 from a fixed LCG) with their raw R G B and
elevation_m = (R*256 + G + B/256) - 32768. The Swift tests must match these bytes exactly.
"""
import json, math, os, struct, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
TILES = [
    # name, file, lat, lon of the test point, tile x, tile y at z12
    ("W", "terrarium-12-702-1600-W.png", 36.5785, -118.2923, 702, 1600),
    ("S", "terrarium-12-2145-1448-S.png", 46.5586, 8.5610, 2145, 1448),
]
ZOOM = 12


def png_rgb(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    p, idat = 8, b""
    w = h = bd = ct = interlace = None
    while p < len(data):
        ln, = struct.unpack(">I", data[p:p + 4])
        typ, body = data[p + 4:p + 8], data[p + 8:p + 8 + ln]
        p += 12 + ln
        if typ == b"IHDR":
            w, h, bd, ct, _, _, interlace = struct.unpack(">IIBBBBB", body[:13])
        elif typ == b"IDAT":
            idat += body
    assert bd == 8 and ct in (2, 6) and interlace == 0, f"unsupported PNG: depth {bd} type {ct} interlace {interlace}"
    bpp = 3 if ct == 2 else 4
    raw = zlib.decompress(idat)
    stride = w * bpp
    prev = bytearray(stride)
    out = bytearray()
    q = 0
    for _ in range(h):
        f = raw[q]
        line = bytearray(raw[q + 1:q + 1 + stride])
        q += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        prev = line
        for x in range(w):
            out += line[x * bpp:x * bpp + 3]
    return w, h, bytes(out)


def fnv1a64(b):
    h = 0xcbf29ce484222325
    for byte in b:
        h = ((h ^ byte) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return f"{h:016x}"


def point_pixel(lat, lon, z):
    n = 2 ** z
    fx = (lon + 180) / 360 * n
    fy = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return fx, fy


result = {
    "note": "Produced by make-reference.py (pure-Python PNG decode, python3 -I). elevation_m = (r*256 + g + b/256) - 32768. "
            "checksum_fnv1a64 is FNV-1a 64 over all RGB bytes, rows top to bottom.",
    "zoom": ZOOM,
    "tiles": [],
}
for name, fname, lat, lon, tx, ty in TILES:
    with open(os.path.join(HERE, fname), "rb") as f:
        w, h, rgb = png_rgb(f.read())
    fx, fy = point_pixel(lat, lon, ZOOM)
    assert int(fx) == tx and int(fy) == ty, "test point is not inside this tile"
    px, py = int((fx - tx) * w), int((fy - ty) * h)
    coords = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (px, py)]
    seed = 12345
    for _ in range(15):
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        x = seed % w
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
        y = seed % h
        coords.append((x, y))
    samples = []
    for x, y in coords:
        i = (y * w + x) * 3
        r, g, b = rgb[i], rgb[i + 1], rgb[i + 2]
        samples.append({"x": x, "y": y, "r": r, "g": g, "b": b, "elevation_m": r * 256 + g + b / 256 - 32768})

    def elev(x, y):
        i = (y * w + x) * 3
        return rgb[i] * 256 + rgb[i + 1] + rgb[i + 2] / 256 - 32768

    # bilinear at the exact test point (pixel centres at i + 0.5), neighbours inside the tile
    u, v = (fx - tx) * w - 0.5, (fy - ty) * h - 0.5
    x0, y0 = math.floor(u), math.floor(v)
    tx_, ty_ = u - x0, v - y0
    bil = ((elev(x0, y0) * (1 - tx_) + elev(x0 + 1, y0) * tx_) * (1 - ty_)
           + (elev(x0, y0 + 1) * (1 - tx_) + elev(x0 + 1, y0 + 1) * tx_) * ty_)
    result["tiles"].append({
        "name": name, "file": fname, "x": tx, "y": ty, "width": w, "height": h,
        "latitude": lat, "longitude": lon,
        "point_pixel": {"x": px, "y": py},
        "nearest_elevation_m_at_point": elev(px, py),
        "bilinear_elevation_m_at_point": bil,
        "checksum_fnv1a64": fnv1a64(rgb),
        "sample_count": len(samples),
        "samples": samples,
    })

with open(os.path.join(HERE, "reference.json"), "w") as f:
    json.dump(result, f, indent=1)
    f.write("\n")
for t in result["tiles"]:
    print(t["name"], t["width"], t["height"], "nearest", t["nearest_elevation_m_at_point"],
          "bilinear", round(t["bilinear_elevation_m_at_point"], 3), t["checksum_fnv1a64"])
