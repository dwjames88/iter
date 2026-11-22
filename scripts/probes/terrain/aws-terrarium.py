#!/usr/bin/env python3 -I
# Fetch one Terrarium tile per test point from AWS Open Data and decode elevation (pure python, zlib PNG).
import math, urllib.request, zlib, struct, os, sys
UA = "IterProbe/0.1 (data-source evaluation)"
OUT = "${TMPDIR:-/tmp}/iter-probes/terrain"
os.makedirs(OUT, exist_ok=True)
def tile(lat, lon, z):
    n = 2**z; x = (lon+180)/360*n
    y = (1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*n
    return int(x), int(y), (x-int(x)), (y-int(y))
def png_decode(b):
    assert b[:8] == b"\x89PNG\r\n\x1a\n"
    p = 8; idat = b""; 
    while p < len(b):
        ln, = struct.unpack(">I", b[p:p+4]); typ = b[p+4:p+8]; d = b[p+8:p+8+ln]; p += 12+ln
        if typ == b"IHDR": w, h, bd, ct = struct.unpack(">IIBB", d[:10])
        elif typ == b"IDAT": idat += d
    bpp = {2:3, 6:4}[ct]; raw = zlib.decompress(idat); stride = w*bpp; rows = []; prev = bytearray(stride); q = 0
    for _ in range(h):
        f = raw[q]; line = bytearray(raw[q+1:q+1+stride]); q += 1+stride
        for i in range(stride):
            a = line[i-bpp] if i >= bpp else 0; bb = prev[i]; c = prev[i-bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i]+a) & 255
            elif f == 2: line[i] = (line[i]+bb) & 255
            elif f == 3: line[i] = (line[i]+((a+bb)>>1)) & 255
            elif f == 4:
                pa = abs(bb-c); pb = abs(a-c); pc = abs(a+bb-2*c)
                pr = a if pa <= pb and pa <= pc else (bb if pb <= pc else c)
                line[i] = (line[i]+pr) & 255
        rows.append(line); prev = line
    return w, h, bpp, rows
for name, lat, lon in [("whitney", 36.5785, -118.2923), ("swiss", 46.5586, 8.5610)]:
    for z in (10, 12, 14):
        x, y, fx, fy = tile(lat, lon, z)
        url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            r = urllib.request.urlopen(req, timeout=60); b = r.read(); st = r.status
        except Exception as e:
            print(name, z, url, "FAIL", e); continue
        open(f"{OUT}/terrarium_{name}_{z}.png", "wb").write(b)
        w, h, bpp, rows = png_decode(b)
        px = rows[int(fy*h)][int(fx*w)*bpp:int(fx*w)*bpp+3]
        e = px[0]*256 + px[1] + px[2]/256 - 32768
        print(f"{name} z{z} HTTP {st} {len(b)}B {w}x{h} url={url} elev={e:.1f} m")
