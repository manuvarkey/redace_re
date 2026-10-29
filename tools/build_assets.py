#!/usr/bin/env python3
"""Build the Godot game_data folder from the extracted Red Ace install.

Usage: build_assets.py <extracted game dir> <REDACE.CUE> <godot project dir>

All output paths are lower case so lookups from mission files are case-insensitive.
Output (under <project>/game_data/):
  objects/<kind>/<object>/<model>.gltf   converted .dff models (kind = planes, ground, ordinance, particles)
  objects/<kind>/<object>/*.ini          object definitions (plane.ini, ground.ini)
  objects/<kind>/textures/*.png          shared textures, mask textures merged into alpha
  maps/<map>/<bsp>.gltf, map.ini, sky_*.png
  missions/<n>/mission.ini, language/english/...
  help.zip                               original help web pages (opened in the system browser)
  sound/*.wav|*.mp3 (.l3 files are MPEG audio and are renamed), music/track<N>.ogg
"""
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rw2gltf  # noqa: E402


def lower_rel(path, root):
    return os.path.relpath(path, root).lower().replace('\\', '/')


def convert(src, dst, tex_dirs, tex_out):
    data = open(src, 'rb').read()
    root = rw2gltf.Chunk(data, 0)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    gl = rw2gltf.Gltf(dst, tex_dirs, tex_out)
    name = os.path.splitext(os.path.basename(dst))[0]
    if root.type == rw2gltf.T_CLUMP:
        rw2gltf.convert_clump(root, gl, name)
    elif root.type == rw2gltf.T_WORLD:
        rw2gltf.convert_world(root, gl, name)
    else:
        raise ValueError('unsupported root chunk 0x%x' % root.type)
    gl.save()


def copy_text(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)


def build_objects(game, out):
    count = fails = 0
    objroot = os.path.join(game, 'objects')
    for kind in sorted(os.listdir(objroot)):
        kdir = os.path.join(objroot, kind)
        tex_dirs = [os.path.join(kdir, d) for d in os.listdir(kdir) if d.lower() == 'textures']
        # a few objects use map textures (Africanwell.dff -> water010001 in maps/country)
        maps_dir = os.path.join(game, 'maps')
        fallback = [os.path.join(maps_dir, m) for m in sorted(os.listdir(maps_dir))]
        tex_out = os.path.join(out, 'objects', kind.lower(), 'textures')
        for dirpath, _, files in os.walk(kdir):
            for f in files:
                src = os.path.join(dirpath, f)
                rel = lower_rel(src, game)
                ext = os.path.splitext(f)[1].lower()
                if ext == '.dff':
                    dst = os.path.join(out, os.path.splitext(rel)[0] + '.gltf')
                    try:
                        convert(src, dst, tex_dirs + [dirpath] + fallback, tex_out)
                        count += 1
                    except Exception as e:
                        print('FAIL %s: %r' % (rel, e))
                        fails += 1
                elif ext == '.ini':
                    copy_text(src, os.path.join(out, rel))
    print('objects: %d models converted, %d failed' % (count, fails))


def build_maps(game, out):
    mroot = os.path.join(game, 'maps')
    for m in sorted(os.listdir(mroot)):
        mdir = os.path.join(mroot, m)
        odir = os.path.join(out, 'maps', m.lower())
        for f in os.listdir(mdir):
            src = os.path.join(mdir, f)
            ext = os.path.splitext(f)[1].lower()
            if ext == '.bsp':
                convert(src, os.path.join(odir, f.lower()[:-4] + '.gltf'), [mdir], os.path.join(odir, 'textures'))
            elif ext == '.ini':
                copy_text(src, os.path.join(odir, f.lower()))
        # sky box faces and overview map, referenced by name from map.ini
        ini_name = next(f for f in os.listdir(mdir) if f.lower() == 'map.ini')
        ini = open(os.path.join(mdir, ini_name), encoding='latin-1').read()
        for face in ('front', 'left', 'right', 'back', 'up'):
            mm = re.search(r'^\s*%s\s*=\s*(\S+)' % face, ini, re.M)
            if mm:
                tex = rw2gltf.Gltf(os.path.join(odir, 'x.gltf'), [mdir])
                srcf = tex.find_texture(mm.group(1))
                if srcf:
                    rw2gltf.Image.open(srcf).convert('RGB').save(os.path.join(odir, 'sky_%s.png' % face))
        for f in os.listdir(mdir):
            if f.lower() in ('map.jpg', 'map.bmp'):
                hires(rw2gltf.Image.open(os.path.join(mdir, f)).convert('RGB')).save(os.path.join(odir, 'map.png'))
        print('map %s done' % m)


def build_text_trees(game, out):
    for sub in ('missions', 'language'):
        for dirpath, _, files in os.walk(os.path.join(game, sub)):
            for f in files:
                src = os.path.join(dirpath, f)
                rel = lower_rel(src, game)
                ext = os.path.splitext(f)[1].lower()
                if ext in ('.ini', '.html', '.htm', '.txt'):
                    copy_text(src, os.path.join(out, rel))
                elif ext in ('.jpg', '.bmp', '.png', '.gif'):
                    dst = os.path.join(out, os.path.splitext(rel)[0] + '.png')
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    rw2gltf.Image.open(src).convert('RGBA').save(dst)
    for f in os.listdir(game):
        if f.lower().endswith('.ini'):
            copy_text(os.path.join(game, f), os.path.join(out, f.lower()))


def build_help(game, out):
    """The original opened language/<lang>/help/*.htm in the system web browser (ShellExecute on
    file://localhost/...). Keep those pages and their GIFs untouched in one zip; the game unpacks it
    (desktop) or the export step places it next to index.html (web)."""
    import zipfile
    with zipfile.ZipFile(os.path.join(out, 'help.zip'), 'w', zipfile.ZIP_DEFLATED) as z:
        lang_root = os.path.join(game, 'language')
        for lang in sorted(os.listdir(lang_root)):
            for d in os.listdir(os.path.join(lang_root, lang)):
                if d.lower() != 'help':
                    continue
                hdir = os.path.join(lang_root, lang, d)
                for dirpath, _, files in os.walk(hdir):
                    for f in files:
                        src = os.path.join(dirpath, f)
                        # links in the pages use these exact names, so only the top two levels are lowered
                        rel = os.path.relpath(src, hdir).replace('\\', '/')
                        z.write(src, 'language/%s/help/%s' % (lang.lower(), rel))


UPSCALE = 4  # HUD and particle bitmaps are 8..256 px; upscale once so the HUD stays smooth at high resolutions


def upscale(img, factor=UPSCALE):
    """Lanczos upscale with a light unsharp mask; alpha is resampled separately to keep edges clean."""
    from PIL import ImageFilter
    size = (img.width * factor, img.height * factor)
    if img.mode == 'RGBA':
        rgb = img.convert('RGB').resize(size, rw2gltf.Image.LANCZOS).filter(ImageFilter.UnsharpMask(2, 60, 2))
        alpha = img.getchannel('A').resize(size, rw2gltf.Image.LANCZOS)
        rgb.putalpha(alpha)
        return rgb
    return img.resize(size, rw2gltf.Image.LANCZOS).filter(ImageFilter.UnsharpMask(2, 60, 2))


def scale3x(a):
    """Scale3x (AdvMAME3x) on an HxWxC uint8 array: pixel-art edges become 45 degree steps, no blur."""
    import numpy as np
    p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode='edge')
    A, B, C = p[:-2, :-2], p[:-2, 1:-1], p[:-2, 2:]
    D, E, F = p[1:-1, :-2], p[1:-1, 1:-1], p[1:-1, 2:]
    G, H, I = p[2:, :-2], p[2:, 1:-1], p[2:, 2:]

    def eq(x, y):
        return np.all(x == y, axis=-1, keepdims=True)
    core = ~eq(B, H) & ~eq(D, F)
    e = E
    out = [
        np.where(core & eq(D, B), D, e),
        np.where(core & ((eq(D, B) & ~eq(E, C)) | (eq(B, F) & ~eq(E, A))), B, e),
        np.where(core & eq(B, F), F, e),
        np.where(core & ((eq(D, B) & ~eq(E, G)) | (eq(D, H) & ~eq(E, A))), D, e),
        e,
        np.where(core & ((eq(B, F) & ~eq(E, I)) | (eq(H, F) & ~eq(E, C))), F, e),
        np.where(core & eq(D, H), D, e),
        np.where(core & ((eq(D, H) & ~eq(E, I)) | (eq(H, F) & ~eq(E, G))), H, e),
        np.where(core & eq(H, F), F, e),
    ]
    h, w, c = a.shape
    r = np.empty((h * 3, w * 3, c), dtype=a.dtype)
    for i, blk in enumerate(out):
        r[i // 3::3, i % 3::3] = blk
    return r


def pixel_upscale(img, factor):
    """Pixel art (icons, cursor): Scale3x twice (9x), then Lanczos down to factor x - smooth edges,
    no halo. Transparent pixels take their colour from the nearest opaque one before resampling."""
    import numpy as np
    a = np.asarray(img.convert('RGBA'))
    a = scale3x(scale3x(a))
    big = rw2gltf.Image.fromarray(a, 'RGBA')
    size = (img.width * factor, img.height * factor)
    alpha = big.getchannel('A').resize(size, rw2gltf.Image.LANCZOS)
    # premultiply so the black colour key does not bleed into edge colours
    rgb = np.asarray(big.convert('RGB'), dtype=np.float32) * (a[..., 3:4] / 255.0)
    rgb = rw2gltf.Image.fromarray(rgb.astype(np.uint8), 'RGB').resize(size, rw2gltf.Image.LANCZOS)
    an = np.asarray(alpha, dtype=np.float32)[..., None] / 255.0
    un = np.clip(np.asarray(rgb, dtype=np.float32) / np.maximum(an, 1e-3), 0, 255).astype(np.uint8)
    out = rw2gltf.Image.fromarray(un, 'RGB')
    out.putalpha(alpha)
    return out


PIXEL_ART_FACTOR = 8
# 8x8 map icons: their masks are all opaque; the original draws them with the top-left pixel's colour
# as colour key (dark corners transparent, as seen running the original)
KEYED_ICONS = ('smallenemy', 'smallally', 'smalltarget', 'planeicon', 'gun', 'targeticon')


# Real-ESRGAN (ncnn/Vulkan build, https://github.com/xinntao/Real-ESRGAN) for the rendered HUD art and the
# minimaps. The general x4plus model keeps the original look; the anime model invents detail.
# Set REALESRGAN to the executable; without it the Lanczos upscale is used.
REALESRGAN = os.environ.get('REALESRGAN', os.path.expanduser('~/tools/realesrgan/realesrgan-ncnn-vulkan'))
ESRGAN_MODEL = 'realesrgan-x4plus'


def _esrgan_rgb(img):
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = os.path.join(tmp, 'in.png'), os.path.join(tmp, 'out.png')
        img.convert('RGB').save(src)
        subprocess.run([REALESRGAN, '-i', src, '-o', dst, '-n', ESRGAN_MODEL, '-s', '4'],
                       check=True, capture_output=True, cwd=os.path.dirname(REALESRGAN))
        return rw2gltf.Image.open(dst).convert('RGB')


def hires(img):
    """4x upscale of rendered art: Real-ESRGAN when available (colour and alpha each), else Lanczos."""
    if not os.path.isfile(REALESRGAN):
        return upscale(img)
    rgb = _esrgan_rgb(img)
    if img.mode == 'RGBA':
        rgb.putalpha(_esrgan_rgb(img.getchannel('A').convert('RGB')).convert('L'))
    return rgb


def masked_bitmaps(src_dir, dst_dir, hires_art=False):
    """<name>.bmp + <name>m.bmp (mask = alpha) to <dst_dir>/<name>.png, upscaled."""
    os.makedirs(dst_dir, exist_ok=True)
    files = {f.lower(): f for f in os.listdir(src_dir)}
    n = 0
    for low, f in files.items():
        if not low.endswith('.bmp'):
            continue
        stem = low[:-4]
        if stem.endswith('m') and stem[:-1] + '.bmp' in files:
            continue  # a mask
        img = rw2gltf.Image.open(os.path.join(src_dir, f)).convert('RGB')
        mask = files.get(stem + 'm.bmp')
        if mask:
            img = img.convert('RGBA')
            img.putalpha(rw2gltf.Image.open(os.path.join(src_dir, mask)).convert('L').resize(img.size))
        if stem in KEYED_ICONS:
            img = img.convert('RGBA')
            px = img.load()
            key = px[0, 0][:3]
            for y in range(img.height):
                for x in range(img.width):
                    if px[x, y][:3] == key:
                        px[x, y] = (0, 0, 0, 0)
            pixel_upscale(img, PIXEL_ART_FACTOR).save(os.path.join(dst_dir, stem + '.png'))
        else:
            # the menu cursor (antialiased 32x32 frames) also comes out cleanest from Real-ESRGAN
            (hires(img) if hires_art else upscale(img)).save(os.path.join(dst_dir, stem + '.png'))
        n += 1
    return n


def build_ui(game, out):
    """HUD bitmaps to ui/*.png and particle bitmaps to objects/particles/*.png; game fonts copied."""
    n = masked_bitmaps(os.path.join(game, 'Ui'), os.path.join(out, 'ui'), hires_art=True)
    n += masked_bitmaps(os.path.join(game, 'objects', 'particles'), os.path.join(out, 'objects', 'particles'))
    # bullet streak raster (ordinance.ini raster = bullet)
    n += masked_bitmaps(os.path.join(game, 'objects', 'ordinance'), os.path.join(out, 'objects', 'ordinance'))
    odir = os.path.join(out, 'ui')
    for f in os.listdir(game):
        if f.lower().endswith('.ttf'):
            shutil.copyfile(os.path.join(game, f), os.path.join(odir, f.lower()))
    print('ui and particles: %d images' % n)


def build_sound(game, out):
    sdir = os.path.join(game, 'sound')
    odir = os.path.join(out, 'sound')
    os.makedirs(odir, exist_ok=True)
    n = 0
    for f in os.listdir(sdir):
        src = os.path.join(sdir, f)
        low = f.lower()
        if os.path.getsize(src) == 0:
            continue
        if low.endswith('.l3'):
            shutil.copyfile(src, os.path.join(odir, low[:-3] + '.mp3'))
        elif low.endswith(('.wav', '.ini')):
            shutil.copyfile(src, os.path.join(odir, low))
        else:
            continue
        n += 1
    print('sound: %d files' % n)


def build_music(cue, out):
    """Rip the Redbook audio tracks of the CD image to Ogg Vorbis with ffmpeg."""
    bin_path = os.path.join(os.path.dirname(cue), re.search(r'FILE "([^"]+)"', open(cue).read()).group(1))
    starts = []
    track = None
    for line in open(cue):
        mt = re.match(r'\s*TRACK (\d+) (\S+)', line)
        if mt:
            track = (int(mt.group(1)), mt.group(2))
        mi = re.match(r'\s*INDEX 01 (\d+):(\d+):(\d+)', line)
        if mi and track:
            m, s, f = map(int, mi.groups())
            starts.append((track[0], track[1], ((m * 60 + s) * 75 + f) * 2352))
    total = os.path.getsize(bin_path)
    odir = os.path.join(out, 'music')
    os.makedirs(odir, exist_ok=True)
    for i, (num, mode, start) in enumerate(starts):
        if mode != 'AUDIO':
            continue
        end = starts[i + 1][2] if i + 1 < len(starts) else total
        dst = os.path.join(odir, 'track%d.ogg' % num)
        if os.path.exists(dst):
            continue
        with open(bin_path, 'rb') as fh:
            fh.seek(start)
            pcm = fh.read(end - start)
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 's16le', '-ar', '44100', '-ac', '2',
                        '-i', 'pipe:0', '-c:a', 'libvorbis', '-q:a', '4', dst], input=pcm, check=True)
        print('music track %d: %.1f s' % (num, len(pcm) / 176400))


# Raster art that keeps its original size elsewhere in the build: menu pages and briefings (drawn at the
# 640x480 page scale, so up to 4-6x on screen), sky boxes, and the textures of models and maps.
# MENU_ART_SCALE must match HtmlView.ART_SCALE (natural image sizes are divided by it).
MENU_ART_SCALE = 4
SKY_SCALE = 4
MODEL_TEXTURE_SCALE = 2  # Real-ESRGAN 4x, then Lanczos down: sharper than 2x directly, a quarter of the memory
ESRGAN_PAD = 8           # wrap padding so tiling textures stay seamless


def _esrgan_dir(src_dir, dst_dir):
    subprocess.run([REALESRGAN, '-i', src_dir, '-o', dst_dir, '-n', ESRGAN_MODEL, '-s', '4', '-f', 'png', '-t', '128'],
                   check=True, capture_output=True, cwd=os.path.dirname(REALESRGAN))


def hires_files(paths, factor, wrap=False):
    """Upscale PNGs in place with Real-ESRGAN (one batch run; colour and alpha separately) to factor x
    their size. wrap pads tiling textures with their opposite edges first. Files already marked as
    done in .upscaled (same mtime) are skipped, so the pass can run again after a partial rebuild."""
    import json
    import tempfile
    import numpy as np
    if not paths or not os.path.isfile(REALESRGAN):
        return 0
    marks = {}
    todo = []
    for p in paths:
        mf = os.path.join(os.path.dirname(p), '.upscaled')
        if mf not in marks:
            marks[mf] = json.load(open(mf)) if os.path.isfile(mf) else {}
        if marks[mf].get(os.path.basename(p)) != os.path.getmtime(p):
            todo.append(p)
    with tempfile.TemporaryDirectory() as tmp:
        src, dst = os.path.join(tmp, 'in'), os.path.join(tmp, 'out')
        os.makedirs(src)
        os.makedirs(dst)
        info = {}
        for i, p in enumerate(todo):
            img = rw2gltf.Image.open(p)
            alpha = img.mode in ('RGBA', 'LA') or (img.mode == 'P' and 'transparency' in img.info)
            img = img.convert('RGBA' if alpha else 'RGB')
            pad = ESRGAN_PAD if wrap and min(img.size) > 2 * ESRGAN_PAD else 0
            a = np.asarray(img)
            if pad:
                a = np.pad(a, ((pad, pad), (pad, pad), (0, 0)), mode='wrap')
            rw2gltf.Image.fromarray(np.ascontiguousarray(a[..., :3])).save(os.path.join(src, '%d.png' % i))
            if alpha:
                al = np.repeat(a[..., 3:4], 3, axis=2)
                rw2gltf.Image.fromarray(np.ascontiguousarray(al)).save(os.path.join(src, '%da.png' % i))
            info[i] = (p, img.size, alpha, pad)
        if todo:
            _esrgan_dir(src, dst)
        for i, (p, size, alpha, pad) in info.items():
            def load(name):
                im = rw2gltf.Image.open(os.path.join(dst, name))
                if pad:
                    im = im.crop((pad * 4, pad * 4, im.width - pad * 4, im.height - pad * 4))
                return im
            out = load('%d.png' % i).convert('RGB')
            if alpha:
                out.putalpha(load('%da.png' % i).convert('L'))
            target = (size[0] * factor, size[1] * factor)
            if out.size != target:
                out = out.resize(target, rw2gltf.Image.LANCZOS)
            out.save(p)
            mf = os.path.join(os.path.dirname(p), '.upscaled')
            marks[mf][os.path.basename(p)] = os.path.getmtime(p)
    for mf, m in marks.items():
        json.dump(m, open(mf, 'w'), indent=0)
    return len(todo)


def _pngs(root, pred=lambda p: True):
    out = []
    for dirpath, _, files in os.walk(root):
        for f in files:
            p = os.path.join(dirpath, f)
            if f.endswith('.png') and pred(p):
                out.append(p)
    return sorted(out)


def build_hires(out):
    """Real-ESRGAN pass over the raster art the other steps leave at original size (help pages are
    left alone: the system browser shows them at their own size)."""
    n = hires_files(_pngs(os.path.join(out, 'language'), lambda p: '/help/' not in p.replace('\\', '/')),
                    MENU_ART_SCALE)
    n += hires_files(_pngs(os.path.join(out, 'maps'), lambda p: os.path.basename(p).startswith('sky_')), SKY_SCALE)
    tex = _pngs(os.path.join(out, 'maps'), lambda p: '/textures/' in p.replace('\\', '/'))
    tex += _pngs(os.path.join(out, 'objects'), lambda p: '/textures/' in p.replace('\\', '/'))
    n += hires_files(tex, MODEL_TEXTURE_SCALE, wrap=True)
    print('hires: %d images upscaled' % n)


def build_overrides(project, out):
    """Hand-made replacements (godot/overrides, same paths as game_data, e.g. a remodelled tree) are
    copied over the converted files last, so a rebuild keeps them. blend/ holds their Blender sources."""
    root = os.path.join(os.path.dirname(os.path.abspath(project)), 'overrides')
    n = 0
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d != 'blend']
        for f in files:
            src = os.path.join(dirpath, f)
            dst = os.path.join(out, os.path.relpath(src, root))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            n += 1
    print('overrides: %d files' % n)


def main():
    game, cue, project = sys.argv[1:4]
    out = os.path.join(project, 'game_data')
    os.makedirs(out, exist_ok=True)
    # keep Godot from scanning raw sources twice: everything here is generated
    build_objects(game, out)
    build_maps(game, out)
    build_text_trees(game, out)
    build_help(game, out)
    build_ui(game, out)
    build_sound(game, out)
    build_music(cue, out)
    build_hires(out)
    build_overrides(project, out)


if __name__ == '__main__':
    main()
