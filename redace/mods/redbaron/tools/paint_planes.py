#!/usr/bin/env python3
"""Paint the Red Baron plane textures from the stock atlases (design "Paint schemes").

Writes overrides/redbaron/objects/planes/<folder>/<folder>.png, which build_planes.py copies next to the
folder's model and points the model's atlas at. Regions are pixel boxes in the 1024 x 1024 upscaled
atlases (game_data/objects/planes/textures/*_a.png):

  albatrostemp1_a: wing upper surfaces x 0..140 / 430..575, y 0..655 (green; painted red too, at the
                   user's request: the design allowed camouflage), fuselage sides x 620..770 / 780..920,
                   y 0..790 (tail at the top, metal nose at the bottom), wheel covers 0..140 x 665..800,
                   fin and rudder 0..150 x 800..990, tailplane 175..470 x 865..1010.
  fokker_a:        already red (the original game's Red Baron); fuselage sides x 700..1000 (tail at the
                   top), rudder (white field with a black cross) 285..460 x 855..1010.

Painting keeps each pixel's shading: coloured pixels (saturation above a threshold) get the target hue
at their own brightness; black crosses, white fields, metal and the pilot are left alone.
Usage: python3 paint_planes.py
"""
import colorsys
from pathlib import Path

from PIL import Image

GODOT = Path(__file__).resolve().parents[4]
TEX = GODOT / "redace" / "game_data" / "objects" / "planes" / "textures"
OUT = GODOT / "overrides" / "redbaron" / "objects" / "planes"

FOKKER_RED = (186, 42, 0)  # the stock Dr.I's red, so the squadron matches
ALBATROS_PAINT = [(620, 0, 770, 790), (780, 0, 920, 790), (0, 665, 140, 800), (0, 800, 150, 990),
                  (175, 865, 470, 1010)]
ALBATROS_WINGS = [(0, 0, 140, 655), (430, 0, 575, 655)]  # the green upper surfaces; the cream undersides stay
ALBATROS_BAND = [(620, 150, 770, 200), (780, 150, 920, 200)]  # behind the fuselage cross, ahead of the tail
FOKKER_BAND = [(700, 150, 830, 200), (840, 150, 1000, 200)]
FOKKER_RUDDER = (285, 855, 460, 1010)
ACCENTS = {"yellow": (225, 190, 30), "blue": (40, 80, 190), "green": (40, 130, 50), "black": (25, 25, 25)}


def recolour(img, boxes, colour, min_sat=0.22):
    """Coloured paint in boxes -> colour, keeping the pixel's brightness relative to the paint's mean."""
    px = img.load()
    th, _, tv = colorsys.rgb_to_hsv(*(c / 255 for c in colour))
    _, ts, _ = colorsys.rgb_to_hsv(*(c / 255 for c in colour))
    for x0, y0, x1, y1 in boxes:
        for y in range(y0, y1):
            for x in range(x0, x1):
                r, g, b, a = px[x, y]
                h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                if a < 8 or s < min_sat or v < 0.08:
                    continue
                # stock paint sits at value ~0.3-0.45; scale so its brighter parts land on the target's value
                nv = min(1.0, v / 0.45 * tv)
                nr, ng, nb = colorsys.hsv_to_rgb(th, ts, nv)
                px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)


def white_fields(img, box, colour, min_value=0.72, max_sat=0.18):
    """Light, unsaturated pixels in box (a white field) -> colour, keeping their shading."""
    px = img.load()
    x0, y0, x1, y1 = box
    th, ts, tv = colorsys.rgb_to_hsv(*(c / 255 for c in colour))
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if a < 8 or v < min_value or s > max_sat:
                continue
            nr, ng, nb = colorsys.hsv_to_rgb(th, ts, tv * v)
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)


def band(img, boxes, colour=(235, 232, 222)):
    """A painted band: every painted (non-transparent, non-black) pixel in boxes, shaded like the paint."""
    px = img.load()
    for x0, y0, x1, y1 in boxes:
        for y in range(y0, y1):
            for x in range(x0, x1):
                r, g, b, a = px[x, y]
                v = max(r, g, b) / 255
                if a < 8 or v < 0.12:
                    continue
                k = min(1.0, 0.75 + v * 0.4)
                px[x, y] = (int(colour[0] * k), int(colour[1] * k), int(colour[2] * k), a)


def save(img, folder):
    d = OUT / folder
    d.mkdir(parents=True, exist_ok=True)
    img.save(d / f"{folder}.png")
    print(f"{folder}/{folder}.png")


def main():
    albatros = Image.open(TEX / "albatrostemp1_a.png").convert("RGBA")
    red = albatros.copy()
    recolour(red, ALBATROS_PAINT + ALBATROS_WINGS, FOKKER_RED)
    save(red, "albatros_red")
    brenner = red.copy()
    band(brenner, ALBATROS_BAND)
    save(brenner, "albatros_brenner")

    fokker = Image.open(TEX / "fokker_a.png").convert("RGBA")
    save(fokker.copy(), "fokker_red")
    fb = fokker.copy()
    band(fb, FOKKER_BAND)
    save(fb, "fokker_brenner")
    for name, colour in ACCENTS.items():
        rookie = fokker.copy()
        white_fields(rookie, FOKKER_RUDDER, colour)
        save(rookie, "fokker_rookie" if name == "yellow" else f"fokker_rookie_{name}")


if __name__ == "__main__":
    main()
