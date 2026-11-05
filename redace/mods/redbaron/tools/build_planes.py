#!/usr/bin/env python3
"""Build the Red Baron plane folders in game_data/objects/planes (and ground objects in objects/ground).

Each folder in overrides/redbaron/objects/planes/<name>/ holds the tuned plane.ini and, when repainted,
<name>.png (made by paint_planes.py). The model (glTF + bin, shadow) is copied from the stock folder in
BASE; when the folder has its own paint, the copied model's atlas (ATLAS) is pointed at it.
Run paint_planes.py first, then this, then `godot --headless --path redace --import`.
"""
import json
import shutil
from pathlib import Path

GODOT = Path(__file__).resolve().parents[4]
SRC = GODOT / "overrides" / "redbaron" / "objects" / "planes"
DST = GODOT / "redace" / "game_data" / "objects" / "planes"
# folder prefix -> (stock folder, stock atlas that the paint replaces)
BASE = {"albatros_": ("albertross", "albatrostemp1_a.png"), "fokker_": ("fokkertriplane", "fokker_a.png"),
        "re8": ("aircodh2", "")}  # re8: placeholder model until the Phase 5 build
GROUND_SRC = GODOT / "overrides" / "redbaron" / "objects" / "ground"
GROUND_DST = GODOT / "redace" / "game_data" / "objects" / "ground"


def build(name):
    stock, atlas = next(v for k, v in BASE.items() if name.startswith(k))
    out = DST / name
    out.mkdir(parents=True, exist_ok=True)
    paint = SRC / name / f"{name}.png"
    for f in (DST / stock).iterdir():
        if f.suffix == ".bin":
            shutil.copy2(f, out / f.name)
        elif f.suffix == ".gltf":
            g = json.loads(f.read_text())
            if paint.exists() and atlas:
                for img in g.get("images", []):
                    if img.get("uri", "").endswith("/" + atlas):
                        img["uri"] = paint.name
            (out / f.name).write_text(json.dumps(g, indent=1))
    for f in (SRC / name).iterdir():
        if f.is_file():
            shutil.copy2(f, out / f.name)
    print(f"{name}: model from {stock}" + (f", paint {paint.name}" if paint.exists() else ", stock paint"))


def build_ground(name):
    """Ground objects: the folder's files as they are (models may live in another object's folder)."""
    out = GROUND_DST / name
    out.mkdir(parents=True, exist_ok=True)
    for f in (GROUND_SRC / name).iterdir():
        if f.is_file():
            shutil.copy2(f, out / f.name)
    print(f"ground {name}")


if __name__ == "__main__":
    for name in sorted(p.name for p in SRC.iterdir() if p.is_dir()):
        build(name)
    for name in sorted(p.name for p in GROUND_SRC.iterdir() if p.is_dir()):
        build_ground(name)
