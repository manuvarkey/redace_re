#!/usr/bin/env python3
"""Dawn sky box for the Red Baron mod (mission 6): the trenches map's sunset sky, lifted and cooled
into early morning (pale rose low down, grey-blue above). Writes mods/redbaron/skies/dawn/sky_*.jpg.
The dusk missions use the trenches sky as it is (map.ini of a mission: [environment] sky).
"""
from pathlib import Path

from PIL import Image, ImageEnhance

GODOT = Path(__file__).resolve().parents[4]
SRC = GODOT / "redace" / "game_data" / "maps" / "trenches"
OUT = GODOT / "redace" / "mods" / "redbaron" / "skies" / "dawn"


def dawn(img):
    img = img.convert("RGB")
    img = ImageEnhance.Brightness(img).enhance(1.75)
    img = ImageEnhance.Color(img).enhance(0.55)
    r, g, b = img.split()
    r = r.point(lambda v: min(255, int(v * 1.02 + 6)))
    g = g.point(lambda v: min(255, int(v * 0.96 + 4)))
    b = b.point(lambda v: min(255, int(v * 1.08 + 14)))
    return Image.merge("RGB", (r, g, b))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for face in ["front", "back", "left", "right", "up"]:
        dawn(Image.open(SRC / f"sky_{face}.png")).save(OUT / f"sky_{face}.jpg", quality=90)
        print(OUT / f"sky_{face}.jpg")
