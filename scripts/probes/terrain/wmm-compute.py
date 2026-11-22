#!/usr/bin/env python3 -I
# Local WMM2025 declination from WMM.COF (Schmidt semi-normalised spherical harmonics, n<=12) - proves the algorithm is small.
# Usage: python3 -I wmm-compute.py <WMM.COF> [lat lon year heightKm]
import math, sys
cof = sys.argv[1]
lat, lon, yr, h = (float(x) for x in sys.argv[2:6]) if len(sys.argv) >= 6 else (36.5785, -118.2923, 2026.8904, 0.0)
N = 12; epoch = None
g = [[0.0]*(N+1) for _ in range(N+1)]; hh = [[0.0]*(N+1) for _ in range(N+1)]
gd = [[0.0]*(N+1) for _ in range(N+1)]; hd = [[0.0]*(N+1) for _ in range(N+1)]
for ln in open(cof):
    p = ln.split()
    if not p: continue
    if epoch is None: epoch = float(p[0]); continue
    if p[0].startswith("9999"): break
    n, m = int(p[0]), int(p[1]); g[n][m], hh[n][m], gd[n][m], hd[n][m] = map(float, p[2:6])
t = yr - epoch
a = 6378.137; f = 1/298.257223563; e2 = f*(2-f); A = 6371.2
phi = math.radians(lat); lam = math.radians(lon)
Rc = a/math.sqrt(1-e2*math.sin(phi)**2)
p_ = (Rc+h)*math.cos(phi); z = (Rc*(1-e2)+h)*math.sin(phi)
r = math.hypot(p_, z); phic = math.asin(z/r)
# Schmidt semi-normalised Legendre functions and d/dtheta
th = math.pi/2 - phic; ct, st = math.cos(th), math.sin(th)
P = [[0.0]*(N+1) for _ in range(N+1)]; dP = [[0.0]*(N+1) for _ in range(N+1)]
P[0][0] = 1.0
for n in range(1, N+1):
    for m in range(0, n+1):
        if n == m:
            if n == 1: P[1][1] = st; dP[1][1] = ct
            else:
                k = math.sqrt((2*n-1)/(2*n))
                P[n][n] = k*st*P[n-1][n-1]; dP[n][n] = k*(st*dP[n-1][n-1] + ct*P[n-1][n-1])
        else:
            d = math.sqrt(n*n-m*m); k2 = math.sqrt((n-1)**2-m*m) if n-1 >= m else 0.0
            p2 = P[n-2][m] if n >= 2 else 0.0; dp2 = dP[n-2][m] if n >= 2 else 0.0
            P[n][m] = ((2*n-1)*ct*P[n-1][m] - k2*p2)/d
            dP[n][m] = ((2*n-1)*(ct*dP[n-1][m] - st*P[n-1][m]) - k2*dp2)/d
Br = Bt = Bp = 0.0
for n in range(1, N+1):
    rr = (A/r)**(n+2)
    for m in range(0, n+1):
        gc = g[n][m]+t*gd[n][m]; hc = hh[n][m]+t*hd[n][m]
        c, s = math.cos(m*lam), math.sin(m*lam)
        Br += rr*(n+1)*(gc*c+hc*s)*P[n][m]
        Bt += -rr*(gc*c+hc*s)*dP[n][m]
        Bp += rr*m*(gc*s-hc*c)*P[n][m]
Bp = Bp/st
Xc = -Bt; Yc = Bp; Zc = -Br
# rotate to geodetic
psi = phi - phic  # geodetic - geocentric
X = Xc*math.cos(psi) + Zc*math.sin(psi); Y = Yc; Z = -Xc*math.sin(psi) + Zc*math.cos(psi)
print(f"WMM epoch {epoch}; lat {lat} lon {lon} year {yr}: declination = {math.degrees(math.atan2(Y, X)):.3f} deg  (X={X:.0f} Y={Y:.0f} Z={Z:.0f} nT)")
