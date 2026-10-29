#!/usr/bin/env python3
"""Convert RenderWare 3.1 clumps (.dff) and worlds (.bsp) from The Red Ace to glTF 2.0.

Usage:
  rw2gltf.py <input.dff|input.bsp> <output.gltf> --textures <dir> [--textures <dir> ...] [--texout <dir>]

Textures are looked up by material texture name (any of .jpg/.bmp/.png, case-insensitive).
A mask texture ("<name>m") is merged into the alpha channel and written as PNG next to the output.
"""
import argparse
import base64
import json
import math
import os
import struct
import sys

from PIL import Image

T_STRUCT, T_STRING, T_EXT, T_TEXTURE, T_MATERIAL, T_MATLIST = 0x01, 0x02, 0x03, 0x06, 0x07, 0x08
T_ATOMICSECT, T_PLANESECT, T_WORLD, T_FRAMELIST, T_GEOMETRY, T_CLUMP = 0x09, 0x0A, 0x0B, 0x0E, 0x0F, 0x10
T_ATOMIC, T_GEOMLIST, T_BINMESH = 0x14, 0x1A, 0x50E

GEO_TRISTRIP, GEO_POSITIONS, GEO_TEXTURED, GEO_PRELIT, GEO_NORMALS = 0x01, 0x02, 0x04, 0x08, 0x10


class Chunk:
    def __init__(self, data, off):
        self.type, self.size, self.lib = struct.unpack_from('<3I', data, off)
        self.data = data
        self.start = off + 12
        self.end = self.start + self.size

    def children(self):
        o = self.start
        while o + 12 <= self.end:
            c = Chunk(self.data, o)
            yield c
            o = c.end

    def child(self, t):
        return next((c for c in self.children() if c.type == t), None)

    def body(self):
        return self.data[self.start:self.end]


def read_string(c):
    return c.body().split(b'\0')[0].decode('latin-1')


# ---------------------------------------------------------------- materials

def read_material(c):
    s = c.child(T_STRUCT).body()
    _flags, = struct.unpack_from('<I', s, 0)
    rgba = tuple(s[4:8])
    textured = struct.unpack_from('<I', s, 12)[0]
    mat = {'color': rgba, 'texture': None, 'mask': None}
    tex = c.child(T_TEXTURE)
    if textured and tex is not None:
        names = [read_string(x) for x in tex.children() if x.type == T_STRING]
        mat['texture'] = names[0] if names else None
        mat['mask'] = names[1] if len(names) > 1 and names[1] else None
    return mat


def read_matlist(c):
    s = c.child(T_STRUCT).body()
    n, = struct.unpack_from('<I', s, 0)
    idx = struct.unpack_from('<%di' % n, s, 4)
    mats = [read_material(x) for x in c.children() if x.type == T_MATERIAL]
    out, it = [], iter(mats)
    for i in idx:
        out.append(next(it) if i < 0 else out[i])
    return out


# ---------------------------------------------------------------- geometry

def read_geometry_30(c, s):
    """RenderWare 3.0 (library id 0x300) geometry: UVs as signed 8.8 fixed-point pairs, triangles,
    bounding sphere, float positions and float normals."""
    flags, ntri, nvert, nmorph = struct.unpack_from('<4I', s, 0)
    p = 28
    uvs = [tuple(x / 256.0 for x in struct.unpack_from('<2h', s, p + 4 * i)) for i in range(nvert)]
    p += 4 * nvert
    tris = []
    for i in range(ntri):
        v2, v1, m, v3 = struct.unpack_from('<4H', s, p + 8 * i)
        tris.append((m, v1, v2, v3))
    p += 8 * ntri + 16
    has_v, has_n = struct.unpack_from('<2I', s, p)
    p += 8
    pos = [struct.unpack_from('<3f', s, p + 12 * i) for i in range(nvert)]
    p += 12 * nvert
    nrm = [struct.unpack_from('<3f', s, p + 12 * i) for i in range(nvert)] if has_n and p + 12 * nvert <= len(s) else None
    return {'pos': pos, 'nrm': nrm, 'uv': uvs, 'col': None, 'tris': tris}


def _size_31(flags, ntri, nvert, s):
    """Struct size the 3.1 layout would need (with or without stored normals)."""
    n = 28 + (4 * nvert if flags & GEO_PRELIT else 0) + (8 * nvert if flags & GEO_TEXTURED else 0) + 8 * ntri + 24
    p = n - 8
    if p + 8 > len(s):
        return -1
    has_v, has_n = struct.unpack_from('<2I', s, p)
    return n + (12 * nvert if has_v else 0) + (12 * nvert if has_n else 0)


def read_geometry(c):
    s = c.child(T_STRUCT).body()
    flags, ntri, nvert, nmorph = struct.unpack_from('<4I', s, 0)
    if c.lib == 0x300 and len(s) != _size_31(flags, ntri, nvert, s):
        # some library-0x300 files use the older layout; the struct size tells them apart
        g = read_geometry_30(c, s)
        g['mats'] = read_matlist(c.child(T_MATLIST))
        return g
    p = 16 + 12  # surface properties (ambient, specular, diffuse) present in 3.1
    colors = uvs = None
    if flags & GEO_PRELIT:
        colors = [tuple(s[p + 4 * i:p + 4 * i + 4]) for i in range(nvert)]
        p += 4 * nvert
    if flags & GEO_TEXTURED:
        uvs = [struct.unpack_from('<2f', s, p + 8 * i) for i in range(nvert)]
        p += 8 * nvert
    tris = []
    for i in range(ntri):
        v2, v1, m, v3 = struct.unpack_from('<4H', s, p + 8 * i)
        tris.append((m, v1, v2, v3))
    p += 8 * ntri
    p += 16  # bounding sphere
    has_v, has_n = struct.unpack_from('<2I', s, p)
    p += 8
    pos = [struct.unpack_from('<3f', s, p + 12 * i) for i in range(nvert)] if has_v else []
    p += 12 * nvert if has_v else 0
    nrm = [struct.unpack_from('<3f', s, p + 12 * i) for i in range(nvert)] if has_n else None

    mats = read_matlist(c.child(T_MATLIST))
    ext = c.child(T_EXT)
    binmesh = ext.child(T_BINMESH) if ext is not None else None
    if binmesh is not None:
        b = binmesh.body()
        strip, nmesh, _ = struct.unpack_from('<3I', b, 0)
        q = 12
        tris = []
        for _ in range(nmesh):
            nidx, m = struct.unpack_from('<2I', b, q)
            q += 8
            idx = struct.unpack_from('<%dI' % nidx, b, q)
            q += 4 * nidx
            if strip:
                for k in range(nidx - 2):
                    a, bb, cc = idx[k], idx[k + 1], idx[k + 2]
                    if a == bb or bb == cc or a == cc:
                        continue
                    tris.append((m, a, bb, cc) if k % 2 == 0 else (m, bb, a, cc))
            else:
                tris += [(m, idx[k], idx[k + 1], idx[k + 2]) for k in range(0, nidx, 3)]
    return {'pos': pos, 'nrm': nrm, 'uv': uvs, 'col': colors, 'tris': tris, 'mats': mats}


def read_world_sector(c, mats, fmt):
    s = c.child(T_STRUCT).body()
    base, ntri, nvert = struct.unpack_from('<3I', s, 0)
    p = 44
    pos = [struct.unpack_from('<3f', s, p + 12 * i) for i in range(nvert)]
    p += 12 * nvert
    nrm = None
    if fmt & GEO_NORMALS:
        nrm = []
        for i in range(nvert):
            x, y, z, _ = struct.unpack_from('<4b', s, p + 4 * i)
            nrm.append((x / 127.0, y / 127.0, z / 127.0))
        p += 4 * nvert
    col = None
    if fmt & GEO_PRELIT:
        col = [tuple(s[p + 4 * i:p + 4 * i + 4]) for i in range(nvert)]
        p += 4 * nvert
    uv = None
    if fmt & GEO_TEXTURED:
        uv = [struct.unpack_from('<2f', s, p + 8 * i) for i in range(nvert)]
        p += 8 * nvert
    # RW 3.1 world sectors: u8 material id (relative to window base) and u8 vertex indices
    tris = [(base + s[p + 4 * i], s[p + 4 * i + 1], s[p + 4 * i + 2], s[p + 4 * i + 3]) for i in range(ntri)]
    return {'pos': pos, 'nrm': nrm, 'uv': uv, 'col': col, 'tris': tris, 'mats': mats}


def fix_winding(g):
    """Orient each triangle so its face normal agrees with the stored vertex normals."""
    if not g['nrm']:
        return
    P, N = g['pos'], g['nrm']
    out = []
    for m, a, b, c in g['tris']:
        e1 = [P[b][i] - P[a][i] for i in range(3)]
        e2 = [P[c][i] - P[a][i] for i in range(3)]
        fn = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        vn = [N[a][i] + N[b][i] + N[c][i] for i in range(3)]
        out.append((m, a, b, c) if sum(fn[i] * vn[i] for i in range(3)) >= 0 else (m, a, c, b))
    g['tris'] = out


# ---------------------------------------------------------------- glTF writer

class Gltf:
    def __init__(self, out_path, tex_dirs, tex_out=None):
        self.out_path = out_path
        self.out_dir = os.path.dirname(os.path.abspath(out_path))
        self.tex_dirs = tex_dirs
        self.tex_out = os.path.abspath(tex_out) if tex_out else os.path.join(self.out_dir, 'textures')
        self.bin = bytearray()
        self.j = {'asset': {'version': '2.0', 'generator': 'rw2gltf (Red Ace)'},
                  'scene': 0, 'scenes': [{'nodes': []}], 'nodes': [], 'meshes': [],
                  'materials': [], 'textures': [], 'images': [], 'samplers': [{'wrapS': 10497, 'wrapT': 10497}],
                  'accessors': [], 'bufferViews': [], 'buffers': []}
        self.mat_cache = {}
        self.tex_cache = {}
        self._index = None

    def find_texture(self, name):
        if self._index is None:
            self._index = {}
            for d in self.tex_dirs:
                for f in os.listdir(d):
                    stem, ext = os.path.splitext(f)
                    if ext.lower() in ('.jpg', '.jpeg', '.bmp', '.png'):
                        self._index.setdefault(stem.lower(), os.path.join(d, f))
        return self._index.get(name.lower())

    def texture(self, name, mask):
        key = (name.lower(), (mask or '').lower())
        if key in self.tex_cache:
            return self.tex_cache[key]
        src = self.find_texture(name)
        if src is None:
            print('warning: texture %r not found' % name, file=sys.stderr)
            self.tex_cache[key] = None
            return None
        img = Image.open(src).convert('RGB')
        msrc = self.find_texture(mask) if mask else None
        has_alpha = False
        if msrc:
            m = Image.open(msrc).convert('L').resize(img.size)
            img = img.convert('RGBA')
            img.putalpha(m)
            has_alpha = True
        os.makedirs(self.tex_out, exist_ok=True)
        fname = name.lower() + ('_a' if has_alpha else '') + '.png'
        dst = os.path.join(self.tex_out, fname)
        if not os.path.exists(dst):
            img.save(dst)
        uri = os.path.relpath(dst, self.out_dir).replace(os.sep, '/')
        self.j['images'].append({'uri': uri})
        self.j['textures'].append({'source': len(self.j['images']) - 1, 'sampler': 0})
        self.tex_cache[key] = (len(self.j['textures']) - 1, has_alpha)
        return self.tex_cache[key]

    def material(self, mat):
        key = (mat['color'], mat['texture'], mat['mask'])
        if key in self.mat_cache:
            return self.mat_cache[key]
        r, g, b, a = mat['color']
        pbr = {'baseColorFactor': [r / 255, g / 255, b / 255, a / 255], 'metallicFactor': 0.0, 'roughnessFactor': 1.0}
        m = {'name': mat['texture'] or 'untextured', 'pbrMetallicRoughness': pbr}
        if mat['texture']:
            t = self.texture(mat['texture'], mat['mask'])
            if t:
                pbr['baseColorTexture'] = {'index': t[0]}
                if t[1]:
                    m['alphaMode'] = 'MASK'
                    m['alphaCutoff'] = 0.5
                    m['doubleSided'] = True
        self.j['materials'].append(m)
        self.mat_cache[key] = len(self.j['materials']) - 1
        return self.mat_cache[key]

    def accessor(self, fmt, rows, comp, typ, target=None, minmax=False):
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        for r in rows:
            self.bin += struct.pack(fmt, *r) if isinstance(r, (tuple, list)) else struct.pack(fmt, r)
        bv = {'buffer': 0, 'byteOffset': off, 'byteLength': len(self.bin) - off}
        if target:
            bv['target'] = target
        self.j['bufferViews'].append(bv)
        acc = {'bufferView': len(self.j['bufferViews']) - 1, 'componentType': comp, 'count': len(rows), 'type': typ}
        if minmax:
            acc['min'] = [min(r[i] for r in rows) for i in range(3)]
            acc['max'] = [max(r[i] for r in rows) for i in range(3)]
        self.j['accessors'].append(acc)
        return len(self.j['accessors']) - 1

    def mesh(self, g, name):
        """Add a mesh; vertices are shared by all primitives, one primitive per material."""
        if not g['tris'] or not g['pos']:
            return None
        g['pos'] = [p if all(math.isfinite(x) for x in p) else (0.0, 0.0, 0.0) for p in g['pos']]
        if g['uv']:
            g['uv'] = [t if all(math.isfinite(x) for x in t) else (0.0, 0.0) for t in g['uv']]
        attrs = {'POSITION': self.accessor('<3f', g['pos'], 5126, 'VEC3', 34962, True)}
        if g['nrm']:
            nrm = []
            for n in g['nrm']:
                ln = math.sqrt(sum(x * x for x in n)) if all(math.isfinite(x) for x in n) else 0.0
                nrm.append(tuple(x / ln for x in n) if ln > 1e-6 else (0.0, 1.0, 0.0))
            attrs['NORMAL'] = self.accessor('<3f', nrm, 5126, 'VEC3', 34962)
        if g['uv']:
            attrs['TEXCOORD_0'] = self.accessor('<2f', g['uv'], 5126, 'VEC2', 34962)
        if g['col']:
            attrs['COLOR_0'] = self.accessor('<4B', g['col'], 5121, 'VEC4', 34962)
            self.j['accessors'][-1]['normalized'] = True
        by_mat = {}
        for m, a, b, c in g['tris']:
            by_mat.setdefault(m, []).extend((a, b, c))
        prims = []
        for m, idx in sorted(by_mat.items()):
            ia = self.accessor('<I', idx, 5125, 'SCALAR', 34963)
            prim = {'attributes': attrs, 'indices': ia}
            if m < len(g['mats']):
                prim['material'] = self.material(g['mats'][m])
            prims.append(prim)
        self.j['meshes'].append({'name': name, 'primitives': prims})
        return len(self.j['meshes']) - 1

    def node(self, **kw):
        self.j['nodes'].append(kw)
        return len(self.j['nodes']) - 1

    def save(self):
        binname = os.path.splitext(os.path.basename(self.out_path))[0] + '.bin'
        open(os.path.join(self.out_dir, binname), 'wb').write(self.bin)
        self.j['buffers'] = [{'uri': binname, 'byteLength': len(self.bin)}]
        for k in ('textures', 'images', 'materials'):
            if not self.j[k]:
                del self.j[k]
        if 'textures' not in self.j:
            del self.j['samplers']
        json.dump(self.j, open(self.out_path, 'w'), indent=1)


# ---------------------------------------------------------------- converters

def convert_clump(root, gl, name):
    fl = root.child(T_FRAMELIST).child(T_STRUCT).body()
    nframes, = struct.unpack_from('<I', fl, 0)
    frames = []
    for i in range(nframes):
        v = struct.unpack_from('<12fiI', fl, 4 + 56 * i)
        rx, ry, rz, ux, uy, uz, ax, ay, az, px, py, pz = v[:12]
        matrix = [rx, ry, rz, 0, ux, uy, uz, 0, ax, ay, az, 0, px, py, pz, 1]
        frames.append((matrix, v[12]))
    nodes = [gl.node(name='%s_frame%d' % (name, i), matrix=m) for i, (m, _) in enumerate(frames)]
    for i, (_, parent) in enumerate(frames):
        if parent >= 0:
            gl.j['nodes'][nodes[parent]].setdefault('children', []).append(nodes[i])
        else:
            gl.j['scenes'][0]['nodes'].append(nodes[i])

    geoms = []
    gl_chunk = root.child(T_GEOMLIST)
    if gl_chunk is not None:
        geoms = [read_geometry(c) for c in gl_chunk.children() if c.type == T_GEOMETRY]
    for k, at in enumerate(c for c in root.children() if c.type == T_ATOMIC):
        s = at.child(T_STRUCT).body()
        frame = struct.unpack_from('<I', s, 0)[0]
        gc = at.child(T_GEOMETRY)
        g = read_geometry(gc) if gc is not None else geoms[struct.unpack_from('<I', s, 4)[0]]
        fix_winding(g)
        mi = gl.mesh(g, '%s_atomic%d' % (name, k))
        if mi is not None:
            n = gl.node(name='%s_atomic%d' % (name, k), mesh=mi)
            gl.j['nodes'][nodes[frame]].setdefault('children', []).append(n)


def convert_world(root, gl, name):
    s = root.child(T_STRUCT).body()
    fmt = struct.unpack_from('<I', s, 48)[0]
    inv_origin = struct.unpack_from('<3f', s, 4)
    mats = read_matlist(root.child(T_MATLIST))
    sectors = []

    def collect(c):
        for x in c.children():
            if x.type == T_ATOMICSECT:
                sectors.append(read_world_sector(x, mats, fmt))
            elif x.type == T_PLANESECT:
                collect(x)
    collect(root)
    # merge all sectors into one vertex/index set
    merged = {'pos': [], 'nrm': [] if fmt & GEO_NORMALS else None, 'uv': [] if fmt & GEO_TEXTURED else None,
              'col': [] if fmt & GEO_PRELIT else None, 'tris': [], 'mats': mats}
    for sec in sectors:
        base = len(merged['pos'])
        merged['pos'] += sec['pos']
        for k in ('nrm', 'uv', 'col'):
            if merged[k] is not None:
                merged[k] += sec[k]
        merged['tris'] += [(m, a + base, b + base, c + base) for m, a, b, c in sec['tris']]
    fix_winding(merged)
    mi = gl.mesh(merged, name)
    n = gl.node(name=name, mesh=mi, extras={'rw_inverse_origin': inv_origin, 'sectors': len(sectors)})
    gl.j['scenes'][0]['nodes'].append(n)
    return len(sectors), len(merged['pos']), len(merged['tris'])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('input')
    ap.add_argument('output')
    ap.add_argument('--textures', action='append', default=[])
    ap.add_argument('--texout', help='shared output directory for converted textures')
    a = ap.parse_args()
    data = open(a.input, 'rb').read()
    root = Chunk(data, 0)
    name = os.path.splitext(os.path.basename(a.input))[0]
    os.makedirs(os.path.dirname(os.path.abspath(a.output)), exist_ok=True)
    gl = Gltf(a.output, a.textures or [os.path.dirname(a.input)], a.texout)
    if root.type == T_CLUMP:
        convert_clump(root, gl, name)
    elif root.type == T_WORLD:
        print('world: %d sectors, %d vertices, %d triangles' % convert_world(root, gl, name))
    else:
        sys.exit('unsupported root chunk 0x%x' % root.type)
    gl.save()


if __name__ == '__main__':
    main()
