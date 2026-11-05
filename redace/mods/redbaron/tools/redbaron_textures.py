#!/usr/bin/env python3
"""Textures for the Red Baron models (overrides/redbaron/textures/*.png), made procedurally (no downloads).

fabric: doped linen, near white, with rib tapes and stitching, tinted per material in Blender (PC10
khaki, clear dope, balloon grey); fabric_scorch1/2: the same with burn holes and soot, for the damage
stages; wicker: the balloon basket.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

GODOT = Path(__file__).resolve().parents[4]
OUT = GODOT / "overrides" / "redbaron" / "textures"
rng = np.random.default_rng(1917)


def fabric():
    a = np.full((512, 512, 3), 226.0) + rng.normal(0, 4, (512, 512, 1))
    y, x = np.mgrid[:512, :512]
    a += (np.sin(y / 3.0) * 1.5)[..., None]  # weave
    im = Image.fromarray(np.clip(a, 0, 255).astype("uint8"))
    d = ImageDraw.Draw(im)
    for k in range(0, 512, 32):  # rib tapes, stitching
        d.line((k, 0, k, 512), fill=(196, 194, 186), width=3)
        for j in range(0, 512, 8):
            d.point((k + 3, j), fill=(170, 168, 160))
    return im.filter(ImageFilter.GaussianBlur(0.6))


def scorch(im, stage):
    a = np.array(im).astype(float)
    y, x = np.mgrid[:512, :512]
    soot = (np.sin(x / 41 + np.sin(y / 57) * 2) + np.cos(y / 33 + x / 77)) > (1.3 - stage * 0.5)
    a[soot] *= 0.35
    im = Image.fromarray(np.clip(a, 0, 255).astype("uint8"))
    d = ImageDraw.Draw(im)
    for _ in range(14 * stage):  # holes
        cx, cy, r = rng.integers(0, 512), rng.integers(0, 512), rng.integers(3, 9)
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(18, 16, 14))
    return im


def wicker():
    a = np.full((256, 256, 3), (150, 112, 68), dtype=float) + rng.normal(0, 8, (256, 256, 1))
    y, x = np.mgrid[:256, :256]
    a *= (0.8 + 0.2 * (np.sin(x / 2.0) * np.sin(y / 6.0) > 0))[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype("uint8"))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    f = fabric()
    f.save(OUT / "fabric.png")
    for stage in (1, 2):
        scorch(f, stage).save(OUT / f"fabric_scorch{stage}.png")
    wicker().save(OUT / "wicker.png")
    print("textures ->", OUT)
