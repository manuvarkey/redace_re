#!/usr/bin/env python3
"""Railway track for the Red Baron mod (mission 9's rail yard): ground object `rail`, written into
overrides/redbaron/objects/ground/rail/ (rail.gltf + rail.bin, rail.png, ground.ini). build_planes.py copies it
into game_data.

One straight segment, SEGMENT long along +z (the mission's `at`), WIDTH wide: a single textured quad (2 triangles)
just above the ground, the ballast, sleepers and the two rails painted in the texture so the line reads clearly from
the air and costs almost nothing. Missions lay segments end to end (junctions and sidings are segments at an angle;
a stored matrix may stretch one along `at`); m09.gd puts each on the terrain under it.
Scale 2.5 units per metre: standard gauge 1.435 m = 3.6 units, ballast bed about 3.2 m = 8 units.
"""
import json
import random
import struct
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parents[4] / "overrides" / "redbaron" / "objects" / "ground" / "rail"
SEGMENT = 60.0
WIDTH = 8.0
LIFT = 0.25
TEX_W, TEX_H = 64, 512
SLEEPERS = 36  # per segment (about 0.66 m apart)


def texture(path):
    random.seed(9)
    im = Image.new("RGB", (TEX_W, TEX_H))
    px = im.load()
    for y in range(TEX_H):
        for x in range(TEX_W):
            edge = min(x, TEX_W - 1 - x) / (TEX_W * 0.5)
            n = random.randint(-14, 14)
            base = (126, 117, 104) if edge > 0.18 else (98, 88, 74)  # ballast, darker earth at the shoulders
            px[x, y] = tuple(max(0, min(255, c + n)) for c in base)
    pitch = TEX_H / SLEEPERS
    for k in range(SLEEPERS):
        y0 = int(k * pitch + pitch * 0.3)
        for y in range(y0, y0 + 5):
            for x in range(8, TEX_W - 8):
                n = random.randint(-6, 6)
                px[x, y % TEX_H] = (72 + n, 54 + n, 40 + n)
    for rail in (TEX_W * 0.5 - 14.4, TEX_W * 0.5 + 14.4):
        r = int(round(rail))
        for y in range(TEX_H):
            px[r - 1, y] = (48, 48, 52)
            px[r, y] = (150, 150, 156)  # the worn top of the rail catches the light
            px[r + 1, y] = (48, 48, 52)
    im.save(path)


def gltf():
    hw, hl = WIDTH / 2.0, SEGMENT / 2.0
    pos = [(-hw, LIFT, -hl), (hw, LIFT, -hl), (hw, LIFT, hl), (-hw, LIFT, hl)]
    nrm = [(0.0, 1.0, 0.0)] * 4
    uv = [(0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0)]
    idx = [0, 2, 1, 0, 3, 2]
    blob = b"".join(struct.pack("<3f", *p) for p in pos) + b"".join(struct.pack("<3f", *n) for n in nrm) \
        + b"".join(struct.pack("<2f", *t) for t in uv) + struct.pack("<6H", *idx)
    blob += b"\0" * (-len(blob) % 4)
    (OUT / "rail.bin").write_bytes(blob)
    doc = {
        "asset": {"version": "2.0", "generator": "redbaron_rails.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "rail"}],
        "meshes": [{"name": "rail", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                                                     "indices": 3, "material": 0}]}],
        "materials": [{"name": "RB_rail", "doubleSided": True, "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": 0.9}}],
        "textures": [{"sampler": 0, "source": 0}],
        "images": [{"mimeType": "image/png", "name": "rail", "uri": "rail.png"}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 10497}],
        "buffers": [{"byteLength": len(blob), "uri": "rail.bin"}],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 48, "target": 34962},
                        {"buffer": 0, "byteOffset": 48, "byteLength": 48, "target": 34962},
                        {"buffer": 0, "byteOffset": 96, "byteLength": 32, "target": 34962},
                        {"buffer": 0, "byteOffset": 128, "byteLength": 12, "target": 34963}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3",
             "min": [-hw, LIFT, -hl], "max": [hw, LIFT, hl]},
            {"bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": 4, "type": "VEC2"},
            {"bufferView": 3, "componentType": 5123, "count": 6, "type": "SCALAR"}],
    }
    (OUT / "rail.gltf").write_text(json.dumps(doc, indent=1))


INI = """; Red Baron mod: railway track segment (tools/redbaron_rails.py), 60 units long along the placed `at`, 8 wide.
; Scenery: missions place it with groups = 0. High endurance so stray rounds never "destroy" the line; soft so a
; contact with it only wears a plane down (as trees), never a hard crash.
[details]
name=rail

[appearance]
dff=rail.dff
diffuse = 1
ambient = 0.5
specular = 0

[physics]
endurance = 100000
soft = 1

[sound]
hitsound = bulletground1.wav
"""

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    texture(OUT / "rail.png")
    gltf()
    (OUT / "ground.ini").write_text(INI)
    print(f"rail: {OUT}")
