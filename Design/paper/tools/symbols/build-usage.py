#!/usr/bin/env python3
"""Builds USAGE.json: {symbol name: [file:line, ...]} for Iter (run from anywhere)."""
import json, os, re, sys
ROOT = "/path/to/Iter"
EXTRA = ["sidebar.left","chevron.down","chevron.up.chevron.down","chevron.right","checkmark","xmark","plus","minus",
 "magnifyingglass","star.fill","location.north.fill","ellipsis",
 # hourly weather (WeatherKit symbolName values, incl. .fill variants the provider returns)
 "sun.max.fill","moon.stars.fill","cloud.sun.fill","cloud.moon.fill","cloud.fill","cloud.rain.fill","cloud.fog.fill",
 "cloud.drizzle.fill","cloud.heavyrain.fill","cloud.snow.fill","cloud.bolt.rain.fill","cloud.sleet.fill","wind","snowflake",
 "smoke.fill","sun.haze.fill","moon.fill","cloud","cloud.drizzle","cloud.snow","cloud.bolt.rain","wind.snow",
 "sun.horizon.fill","sunrise.fill","sunset.fill","star","calendar","clock","safari","pawprint","drop","tree","car","sparkles",
 "chevron.up","message","envelope","doc","folder","desktopcomputer","externaldrive","note.text","list.bullet","icloud.slash","sidebar.right","square.and.arrow.down","arrow.uturn.backward","line.3.horizontal","photo","globe","link","lock","person.crop.circle","square.on.square","plus.magnifyingglass","minus.magnifyingglass","location","scope","location.north.line","dot.radiowaves.left.and.right",
 "chevron.right.2","chevron.forward.2",
 "gearshape","pencil","trash","mappin","map","binoculars","bookmark","flask","square.and.arrow.up","info.circle"]
files = []
for base in ("App/Sources","Packages/IterKit/Sources"):
    for d,_,fs in os.walk(os.path.join(ROOT,base)):
        files += [os.path.join(d,f) for f in fs if f.endswith(".swift")]
for f in ("Design/SCREENS.md","Design/COMPONENTS.md"): files.append(os.path.join(ROOT,f))
lit = re.compile(r'"([a-z0-9]+(?:\.[a-z0-9]+)*)"')
tick = re.compile(r'`([a-z0-9]+(?:\.[a-z0-9]+)*)`')
cand = {}
for p in files:
    rel = os.path.relpath(p,ROOT)
    for i,line in enumerate(open(p,encoding="utf-8"),1):
        rx = tick if p.endswith(".md") else lit
        for m in rx.findall(line):
            cand.setdefault(m,[]).append(f"{rel}:{i}")
src = {}
# names the sources use as symbols: from the grep audit
CONTEXT = re.compile(r'systemName|systemImage|symbol|fact\(|icon')
for p in files:
    rel = os.path.relpath(p,ROOT)
    for i,line in enumerate(open(p,encoding="utf-8"),1):
        if p.endswith(".swift"):
            if not CONTEXT.search(line) and not re.match(r'\s*case \.[a-zA-Z]+: "', line) and not re.search(r'case "\w+": symbol',line): continue
            for m in lit.findall(line):
                if m.startswith("com.") or m[0].isdigit(): continue
                if "." in m or m in ("map","binoculars","bookmark","flask","safari","clock","pencil","trash","calendar","plus","gearshape","sunrise","sunset","sparkles","car","pawprint","drop","tree","cloud","mappin","magnifyingglass"):
                    src.setdefault(m,[]).append(f"{rel}:{i}")
        else:
            for m in tick.findall(line):
                if m in cand and ("." in m or m in ("map","binoculars","bookmark","flask","safari","clock","pencil","trash","calendar","plus","gearshape","sunrise","sunset","sparkles","car","pawprint","drop","tree","mappin","star")):
                    src.setdefault(m,[]).append(f"{rel}:{i}")
# drop md noise like tokens.json
for k in list(src):
    if k.endswith(".json") or k in ("1.000",): del src[k]
for n in EXTRA:
    src.setdefault(n,[])
    if not src[n]: src[n].append("added: design chrome / weather mapping (not literal in source)")
json.dump(dict(sorted(src.items())), open(os.path.join(os.path.dirname(os.path.abspath(__file__)),"USAGE.json"),"w"), indent=1)
print(len(src))
