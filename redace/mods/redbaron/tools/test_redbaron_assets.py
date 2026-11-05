#!/usr/bin/env python3
"""Checks the Red Baron models in game_data (after build_planes.py): files, stages, scale against stock
planes, low poly, propellers the game spins, shadows. Usage: python3 test_redbaron_assets.py"""
import json
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parents[3] / "game_data" / "objects"
fails = 0
checks = 0


def check(ok, what):
    global fails, checks
    checks += 1
    if not ok:
        fails += 1
        print("FAIL:", what)


def model(path):
    g = json.loads(path.read_text())
    lo, hi, tris = [1e9] * 3, [-1e9] * 3, 0
    for m in g["meshes"]:
        for p in m["primitives"]:
            a = g["accessors"][p["attributes"]["POSITION"]]
            lo = [min(lo[i], a["min"][i]) for i in range(3)]
            hi = [max(hi[i], a["max"][i]) for i in range(3)]
            tris += g["accessors"][p["indices"]]["count"] // 3 if "indices" in p else 0
    mats = [m.get("name", "") for m in g.get("materials", [])]
    return [hi[i] - lo[i] for i in range(3)], tris, mats, g


albatros_span = model(DATA / "planes/albertross/albertross.gltf")[0][0]  # 22.5 for 9.0 m: 2.5 per metre
per_m = albatros_span / 9.0
for name, span_m, max_tris in [("re8", 13.0, 1500), ("handleypage", 30.5, 2500)]:
    d = DATA / "planes" / name
    for f in [f"{name}.gltf", "damaged1.gltf", "damaged2.gltf", "wreck.gltf", f"{name}shadow.gltf", "plane.ini"]:
        check((d / f).exists(), f"{name}: {f}")
    size, tris, mats, g = model(d / f"{name}.gltf")
    check(abs(size[0] - span_m * per_m) < 0.08 * span_m * per_m, f"{name}: span {size[0]:.1f} for {span_m} m")
    check(tris <= max_tris, f"{name}: low poly ({tris} tris)")
    check(any(m.startswith("soppropeller") for m in mats), f"{name}: propeller material the game spins")
    props = [n for n in g["nodes"] if n.get("name", "").startswith("Propeller")]
    check(len(props) >= 1 and all("translation" in n for n in props), f"{name}: propellers pivot at their hubs")
    for stage in ["damaged1", "damaged2", "wreck"]:
        check(model(d / f"{stage}.gltf")[0] == size, f"{name}: {stage} keeps the airframe")
    ini = (d / "plane.ini").read_text()
    for key in [f"dff = {name}.dff", "damagedff1 = damaged1.dff", "deaddff = wreck.dff", f"shadow = {name}shadow.dff"]:
        check(key in ini, f"{name}: plane.ini {key}")
b = DATA / "ground" / "balloon"
for f in ["balloon.gltf", "damaged1.gltf", "wreck.gltf", "ground.ini"]:
    check((b / f).exists(), f"balloon: {f}")
size, tris, mats, g = model(b / "balloon.gltf")
check(abs(size[2] - 28.0 * per_m) < 0.1 * 28.0 * per_m, f"balloon: length {size[2]:.1f} for 28 m")
check(tris <= 1200, f"balloon: low poly ({tris} tris)")
check(model(b / "wreck.gltf")[1] < tris, "balloon: the wreck has burnt away")
print(f"RED BARON ASSETS: {checks} checks, {fails} failures")
sys.exit(1 if fails else 0)
