#!/usr/bin/env python3
"""raw-outlines.json (from export-symbols.swift) -> symbols.json + contact-sheet.html.

Native outline units are already y-down (top-left origin) at ~2 units per point. We keep that orientation, scale by 0.5 so one unit is
1/100 of the symbol's point size (a 16pt symbol = scale(0.16)), translate to the tight bounds, round to 2 dp.
(The PDF route was abandoned: AppKit rasterises symbols when drawing to a PDF context, so there is no path data
in the PDF to convert. This replaces the planned pdf2svg.py.)
"""
import json, re, sys, os, html
HERE = os.path.dirname(os.path.abspath(__file__))
RAW = sys.argv[1] if len(sys.argv) > 1 else "/tmp/scratch/scratchpad/paper/symbols/raw-outlines.json"
SCALE = 0.5
tok = re.compile(r'([MLCQZ])([^MLCQZ]*)')
def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s
raw = json.load(open(RAW))["symbols"]
out = {}
for name, r in raw.items():
    bx, by, bw, bh = r["bounds"]
    maxy = by + bh
    parts = []
    for cmd, args in tok.findall(r["d"]):
        n = [float(x) for x in args.split()]
        if cmd == "Z": parts.append("Z"); continue
        xy = []
        for i in range(0, len(n), 2):
            xy += [fmt((n[i] - bx) * SCALE), fmt((n[i + 1] - by) * SCALE)]
        parts.append(cmd + " ".join(xy))
    w, h = round(bw * SCALE, 2), round(bh * SCALE, 2)
    out[name] = {"viewBox": f"0 0 {fmt(w)} {fmt(h)}", "w": w, "h": h, "d": "".join(parts),
                 "fillRule": "evenodd" if r["evenOdd"] else "nonzero"}
json.dump(out, open(os.path.join(HERE, "symbols.json"), "w"), indent=1)
cells = []
for name, s in out.items():
    cells.append(f'<div class="c"><svg viewBox="{s["viewBox"]}" width="{min(s["w"],110)}" height="{min(s["h"],110)}" '
                 f'preserveAspectRatio="xMidYMid meet"><path d="{s["d"]}" fill="#000" fill-rule="{s["fillRule"]}"/></svg>'
                 f'<div class="n">{html.escape(name)}</div></div>')
open(os.path.join(HERE, "contact-sheet.html"), "w").write(
 '<!doctype html><meta charset="utf-8"><title>Symbols</title><style>'
 'body{margin:12px;background:#fff;color:#000;font:10px -apple-system,sans-serif}'
 '.g{display:grid;grid-template-columns:repeat(8,1fr);gap:8px}'
 '.c{border:1px solid #ddd;height:130px;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:4px;overflow:hidden}'
 '.c svg{flex:none;max-width:100%}.n{margin-top:6px;word-break:break-all;text-align:center}</style>'
 '<div class="g">' + "".join(cells) + '</div>')
print(len(out), "symbols")
