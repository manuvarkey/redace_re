"""Shared deterministic Dover-inspired geography, in game coordinates."""
import math
SIZE=6000
def coast(z): return 3050+240*math.sin(z/540)+110*math.sin(z/173)-410*math.exp(-((z-1750)/500)**2)
def height(x,z):
    d=coast(z)-x
    if d<0: return -12
    h=60+50*math.sin(x/470)*math.cos(z/610)+115*math.exp(-((x-2250)/470)**2-((z-3100)/800)**2)+65*math.exp(-((x-1550)/400)**2-((z-3900)/450)**2)
    for cx,cz,r,level in [(1800,3300,260,46),(2450,1700,430,18),(1550,1700,260,32)]:
        t=max(0,min(1,(math.hypot(x-cx,z-cz)-r)/130)); t=t*t*(3-2*t);h=level*(1-t)+h*t
    return h*min(1,d/70)
