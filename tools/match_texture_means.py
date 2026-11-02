#!/usr/bin/env python3
"""Scale each upscaled texture's channels so its visible mean equals the original image's.

Real-ESRGAN shifted the brightness of some textures (foliage and bridge templates by up to 60%).
Usage: match_texture_means.py ORIGINAL_GAME_DIR GAME_DATA_DIR [--apply]
Without --apply it only lists what would change. Only shifts over TOLERANCE are corrected.
"""
import os
import sys

import numpy as np
from PIL import Image

EXTS = ('.bmp', '.jpg', '.jpeg', '.png', '.tga')
TOLERANCE = 0.03


def index(top):
    found = {}
    for sub in ('objects', 'maps'):
        for root, _, files in os.walk(os.path.join(top, sub)):
            for f in files:
                name, ext = os.path.splitext(f)
                if ext.lower() in EXTS:
                    found[(os.path.relpath(root, top).lower(), name.lower())] = os.path.join(root, f)
    return found


def main():
    orig_dir, data_dir = sys.argv[1:3]
    apply = '--apply' in sys.argv
    orig = index(orig_dir)
    changed = 0
    for sub in ('objects', 'maps'):
        for root, _, files in os.walk(os.path.join(data_dir, sub)):
            for f in files:
                if not f.endswith('.png') or f.lower() == 'map.png':  # minimaps are not rendered textures
                    continue
                name = f[:-4].lower()
                rel = os.path.relpath(root, data_dir).lower()
                base = name[:-2] if name.endswith('_a') else name
                src = orig.get((rel, base))
                if src is None:
                    continue
                path = os.path.join(root, f)
                img = Image.open(path).convert('RGBA')
                a = np.asarray(img).astype(np.float64)
                o = np.asarray(Image.open(src).convert('RGB')).astype(np.float64)
                # the same area of both: the texture's own alpha, at the original's size
                alpha = np.asarray(img.getchannel('A').resize((o.shape[1], o.shape[0]))).astype(np.float64)
                keep_o = alpha > 128
                keep_a = a[..., 3] > 128
                if not keep_o.any() or not keep_a.any():
                    continue
                gain = (o[keep_o].mean(0) + 1.0) / (a[keep_a][:, :3].mean(0) + 1.0)
                if np.abs(gain - 1.0).max() <= TOLERANCE:
                    continue
                changed += 1
                print('%-60s gain %s' % (os.path.join(rel, f)[-60:], np.round(gain, 2)))
                if apply:
                    a[..., :3] = np.clip(a[..., :3] * gain, 0, 255)
                    Image.fromarray(a.round().astype(np.uint8), 'RGBA').save(path)
    print(changed, 'textures', 'changed' if apply else 'would change')


main()
