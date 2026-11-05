#!/usr/bin/env python3
"""Build the Red Baron plane folders in game_data/objects/planes.

Each folder in overrides/redbaron/objects/planes/<name>/ holds the tuned plane.ini and any repainted
textures; the model (glTF + bin, shadow) comes from the stock folder named in BASE until a folder
supplies its own. Run, then `godot --headless --path redace --import` so Godot imports new models.
"""
import shutil
from pathlib import Path

GODOT = Path(__file__).resolve().parents[4]
SRC = GODOT / "overrides" / "redbaron" / "objects" / "planes"
DST = GODOT / "redace" / "game_data" / "objects" / "planes"
BASE = {"albatros_red": "albertross", "albatros_brenner": "albertross"}


def build(name):
    out = DST / name
    out.mkdir(parents=True, exist_ok=True)
    base = DST / BASE[name]
    for f in base.iterdir():
        if f.suffix in (".gltf", ".bin") and not (SRC / name / f.name).exists():
            shutil.copy2(f, out / f.name)
    for f in (SRC / name).iterdir():
        if f.is_file():
            shutil.copy2(f, out / f.name)
    print(f"{name}: model from {BASE[name]}, {sum(1 for _ in (SRC / name).iterdir())} override file(s)")


if __name__ == "__main__":
    for name in sorted(p.name for p in SRC.iterdir() if p.is_dir()):
        build(name)
