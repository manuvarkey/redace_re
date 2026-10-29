"""Tree generator for Blender (run inside Blender, e.g. through blender-mcp or `blender --python`).

Builds a low-poly tree to replace one of Red Ace's crossed-card trees: a tapered trunk with branches
and a crown of leaf cards textured with the original foliage image. Lessons from the first tree:
  - every leaf card's front face points out of the crown (double-sided rendering flips back faces,
    which went dark), and cards near the top face upward so they are never seen edge-on;
  - crown normals point out of an ellipsoid round the crown, so it shades as one volume;
  - the result is scaled to the original model's footprint so collisions and placement still fit.

make_tree(spec) returns the object; export_tree(obj, path) writes a .gltf whose images point at the
game's shared ../textures folder (fix up with tools/blender_tree_fixup in the build, see README).
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Quaternion, Vector

# Shared ground-object textures; REDACE_TEX overrides when the script runs without __file__ (blender-mcp).
TEX = os.environ.get("REDACE_TEX") or os.path.join(
    os.path.dirname(os.path.abspath(globals().get("__file__", "."))), "..",
    "redace", "game_data", "objects", "ground", "textures", "")


def _material(name, image, alpha, tint=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(TEX + image, check_existing=True)
    nt.links.new(tex.outputs["Color"], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 1.0
    if tint:
        bs.inputs["Base Color"].default_value = (*tint, 1.0)
    if alpha:
        nt.links.new(tex.outputs["Alpha"], bs.inputs["Alpha"])
        m.use_backface_culling = False
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    return m


def _tube(bm, uvl, points, radii, sides=7, vscale=0.12):
    rings = []
    for i, (p, r) in enumerate(zip(points, radii)):
        d = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        q = d.to_track_quat('Z', 'Y')
        rings.append([bm.verts.new(p + q @ Vector((math.cos(2 * math.pi * k / sides) * r,
                                                    math.sin(2 * math.pi * k / sides) * r, 0)))
                      for k in range(sides)])
    length = 0.0
    for i in range(len(rings) - 1):
        seg = (points[i + 1] - points[i]).length
        for k in range(sides):
            k2 = (k + 1) % sides
            f = bm.faces.new((rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]))
            f.material_index = 0
            u0, u1 = k / sides * 2, (k + 1) / sides * 2
            v0, v1 = length * vscale, (length + seg) * vscale
            for loop, uv in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
                loop[uvl].uv = uv
        length += seg


def _card(bm, uvl, p, normal, half, crown_c, top_z):
    # near the crown top, cards lie flatter so no card is seen edge-on from the side
    if p.z > top_z:
        normal = Vector((normal.x * 0.4, normal.y * 0.4, 1.0)).normalized()
    if normal.dot(p - crown_c) < 0:
        normal = -normal
    q = normal.to_track_quat('Z', 'Y') @ Quaternion((0, 0, 1), random.uniform(0, 2 * math.pi))
    vs = [bm.verts.new(p + q @ Vector(c)) for c in ((-half, -half, 0), (half, -half, 0), (half, half, 0), (-half, half, 0))]
    f = bm.faces.new(vs)
    f.material_index = 1
    for loop, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        loop[uvl].uv = uv


def _tip(bm, uvl, base, half, n=4):
    """Crown tip: a small cone of cards tilted 55 degrees out from vertical round the axis."""
    for k in range(n):
        a = k * 2 * math.pi / n + random.uniform(-.2, .2)
        out = Vector((math.cos(a), math.sin(a), 0))
        nrm = (out * math.sin(math.radians(55)) + Vector((0, 0, math.cos(math.radians(55))))).normalized()
        q = nrm.to_track_quat('Z', 'Y') @ Quaternion((0, 0, 1), random.uniform(0, 2 * math.pi))
        p = base + out * half * .35 + Vector((0, 0, half * .8))
        vs = [bm.verts.new(p + q @ Vector(c)) for c in ((-half, -half, 0), (half, -half, 0), (half, half, 0), (-half, half, 0))]
        f = bm.faces.new(vs)
        f.material_index = 1
        for loop, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uvl].uv = uv


def make_tree(spec):
    """spec keys: name, seed, kind ('broad' | 'poplar' | 'conifer'), leaf_mat, leaf_img, bark_img,
    bark_tint, size (x, y, z of the original), trunk_top, crown_c (z), crown_r (x, z)."""
    random.seed(spec["seed"])
    W, D, H = spec["size"]
    kind = spec["kind"]
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    cz = spec["crown_c"]
    rx, rz = spec["crown_r"]
    C = Vector((0, 0, cz))

    # trunk
    th = spec["trunk_top"]
    lean = Vector((random.uniform(-.4, .4), random.uniform(-.4, .4), 0))
    pts = [Vector((0, 0, -0.5)) + lean * (z / th) + Vector((0, 0, z)) for z in (0, th * .15, th * .4, th * .65, th * .85, th)]
    base_r = spec.get("trunk_r", 1.6)
    _tube(bm, uvl, pts, [base_r * k for k in (1.25, 1.0, .85, .7, .55, .35)])

    # branches
    if kind != "conifer":
        n_br = 6 if kind == "broad" else 8
        for i in range(n_br):
            a = i * 2 * math.pi / n_br + random.uniform(-.4, .4)
            z0 = random.uniform(th * .45, th * .8)
            out = Vector((math.cos(a), math.sin(a), 0))
            reach = rx * (0.65 if kind == "broad" else 0.45)
            rise = rz * (0.5 if kind == "broad" else 0.9)
            base = Vector((0, 0, z0)) + lean * (z0 / th)
            _tube(bm, uvl, [base, base + out * reach * .45 + Vector((0, 0, rise * .35)),
                            base + out * reach + Vector((0, 0, rise * .7))], [base_r * .35, base_r * .22, base_r * .08])

    # crown cards
    top_z = cz + rz * 0.55
    if kind == "broad":
        lobes = []
        for i in range(6):
            a = i * 2 * math.pi / 6 + random.uniform(-.3, .3)
            r = random.uniform(.62, .8) * rx
            lobes.append((Vector((math.cos(a) * r, math.sin(a) * r, cz + random.uniform(-.25, .2) * rz)), random.uniform(.42, .52) * rx))
        lobes.append((Vector((0, 0, cz + rz * .6)), .55 * rx))
        lobes += [(Vector((random.uniform(-.2, .2) * rx, random.uniform(-.2, .2) * rx, cz + random.uniform(-.1, .2) * rz)), .45 * rx) for _ in range(2)]
        for lc, lr in lobes:
            for _ in range(8):
                d = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-.5, 1))).normalized()
                p = lc + d * lr * random.uniform(.35, .8)
                nrm = ((p - C).normalized().lerp(d, .4) + Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))) * .45).normalized()
                _card(bm, uvl, p, nrm, random.uniform(.32, .44) * rx, C, top_z)
    elif kind == "poplar":
        # tall narrow column: stacked rings of cards
        n_rings = 9
        for j in range(n_rings - 1):
            t = j / (n_rings - 1)
            z = cz - rz * .9 + t * rz * 1.8
            r = rx * math.sqrt(max(.05, 1 - (2 * t - 1) ** 2)) * random.uniform(.85, 1.0)
            for k in range(7):
                a = k * 2 * math.pi / 7 + j * .7 + random.uniform(-.3, .3)
                p = Vector((math.cos(a) * r * .75, math.sin(a) * r * .75, z + random.uniform(-2, 2)))
                nrm = (Vector((math.cos(a), math.sin(a), (t - .5) * 1.2)) + Vector((random.uniform(-.5, .5), random.uniform(-.5, .5), random.uniform(-.3, .3)))).normalized()
                _card(bm, uvl, p, nrm, max(r * .7, rx * .45), C, top_z)
        for _ in range(4):
            _card(bm, uvl, Vector((random.uniform(-.3, .3) * rx, random.uniform(-.3, .3) * rx, cz + random.uniform(-.6, .6) * rz)),
                  Vector((random.uniform(-1, 1), random.uniform(-1, 1), .3)).normalized(), rx * .6, C, top_z)
        _tip(bm, uvl, Vector((0, 0, cz + rz * .72)), rx * .45)
    else:  # conifer: tiers of drooping cards on a cone
        n_tiers = 8
        bottom = cz - rz
        for j in range(n_tiers - 1):
            t = j / (n_tiers - 1)
            z = bottom + t * rz * 1.85
            r = rx * (1 - t) * .95 + rx * .12
            n = max(4, int(9 * (1 - t)) + 3)
            for k in range(n):
                a = k * 2 * math.pi / n + j * .5 + random.uniform(-.2, .2)
                out = Vector((math.cos(a), math.sin(a), 0))
                p = out * r * .6 + Vector((0, 0, z + random.uniform(-1, 1)))
                nrm = (out + Vector((0, 0, .9 - t * .2)) + Vector((random.uniform(-.3, .3), random.uniform(-.3, .3), 0))).normalized()
                _card(bm, uvl, p, nrm, max(r * .55, rx * .2), Vector((0, 0, z - rx)), z + 999)
        _tip(bm, uvl, Vector((0, 0, bottom + rz * 1.85 * 6 / 7)), rx * .3)
        # nothing below the ground
        for f in bm.faces:
            if f.material_index == 1:
                mz = min(v.co.z for v in f.verts)
                if mz < 1.0:
                    for v in f.verts:
                        v.co.z += 1.0 - mz

    leaf_top = max(v.co.z for f in bm.faces if f.material_index == 1 for v in f.verts)
    for v in bm.verts:
        if v.link_faces and all(f.material_index == 0 for f in v.link_faces) and v.co.z > leaf_top - 3:
            v.co.z = leaf_top - 3
    me = bpy.data.meshes.new(spec["name"])
    bm.to_mesh(me)
    bm.free()
    me.materials.append(_material(spec["name"] + "_bark", spec["bark_img"], False))
    me.materials.append(_material(spec["leaf_mat"], spec["leaf_img"], True))
    # shading normals: leaves out of the crown ellipsoid, wood flat
    R = Vector((rx, rx, rz))
    ln = []
    for poly in me.polygons:
        for k in poly.loop_indices:
            v = me.vertices[me.loops[k].vertex_index].co
            if poly.material_index == 1:
                d = v - C
                ln.append(Vector((d.x / R.x ** 2, d.y / R.y ** 2, d.z / R.z ** 2)).normalized().lerp(poly.normal, .3).normalized())
            else:
                ln.append(Vector((0, 0, 0)))
    me.normals_split_custom_set(ln)
    obj = bpy.data.objects.new(spec["name"], me)
    bpy.context.scene.collection.objects.link(obj)
    # fit the original footprint (ground at 0 stays at the base)
    bpy.context.view_layer.update()
    dims = obj.dimensions
    obj.scale = (W / dims.x, D / dims.y, H / dims.z)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(scale=True)
    return obj


def export_tree(obj, path):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLTF_SEPARATE', use_selection=True, export_yup=True,
                              export_apply=True, export_normals=True, export_texcoords=True, export_materials='EXPORT')


def _finish(bm, spec, mats, size, normal_fn=None):
    """Mesh from bmesh, materials, optional custom normals, scaled to the original footprint."""
    me = bpy.data.meshes.new(spec["name"])
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    if normal_fn:
        ln = []
        for poly in me.polygons:
            for k in poly.loop_indices:
                ln.append(normal_fn(poly, me.vertices[me.loops[k].vertex_index].co))
        me.normals_split_custom_set(ln)
    obj = bpy.data.objects.new(spec["name"], me)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.update()
    W, D, H = size
    dims = obj.dimensions
    obj.scale = (W / dims.x, D / dims.y, H / dims.z)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(scale=True)
    return obj


def make_palm(spec):
    """Palm: curved ringed trunk (palmbrk1) and arched, folded fronds (palmleaf: base at v=0).
    spec: name, seed, size, height, lean (x, y), n_fronds, frond_len, trunk_r, frond_mat, bark_mat."""
    random.seed(spec["seed"])
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    h = spec["height"]
    lx, ly = spec["lean"]
    # trunk: quadratic curve, slight random wobble
    pts, radii = [], []
    segs = 10
    for i in range(segs + 1):
        t = i / segs
        pts.append(Vector((lx * t * t, ly * t * t, -0.5 + t * h)))
        radii.append(spec["trunk_r"] * (1.25 - 0.45 * t) * (1.0 + 0.06 * math.sin(i * 2.7)))
    _tube(bm, uvl, pts, radii, sides=8, vscale=0.08)
    top = pts[-1]
    up_dir = (pts[-1] - pts[-2]).normalized()
    # crown knob
    _tube(bm, uvl, [top - up_dir * 1.0, top + up_dir * 1.5], [spec["trunk_r"] * 1.15, spec["trunk_r"] * 0.4], sides=8)
    n = spec["n_fronds"]
    L = spec["frond_len"]
    for i in range(n):
        a = i * 2 * math.pi / n + random.uniform(-.25, .25)
        young = i % 4 == 0
        out = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-math.sin(a), math.cos(a), 0))
        length = L * (0.6 if young else random.uniform(.85, 1.05))
        pitch0 = math.radians(random.uniform(45, 65) if young else random.uniform(15, 35))
        droop = math.radians(random.uniform(10, 25) if young else random.uniform(70, 100))
        width = length * 0.42
        k = 6
        spine = []
        p = top + up_dir * 0.8
        for j in range(k + 1):
            t = j / k
            ang = pitch0 - droop * t * t
            spine.append(p.copy())
            p = p + (out * math.cos(ang) + Vector((0, 0, math.sin(ang)))) * (length / k)
        # folded strip: the two halves rise above the spine (a shallow V)
        rows = []
        for j, sp in enumerate(spine):
            t = j / k
            fold = Vector((0, 0, width * 0.18 * (1 - t)))
            rows.append([bm.verts.new(sp - side * width / 2 + fold), bm.verts.new(sp),
                         bm.verts.new(sp + side * width / 2 + fold)])
        for j in range(k):
            v0, v1 = j / k, (j + 1) / k
            for c in range(2):
                f = bm.faces.new((rows[j][c], rows[j][c + 1], rows[j + 1][c + 1], rows[j + 1][c]))
                f.material_index = 1
                u0, u1 = c * 0.5, c * 0.5 + 0.5
                for loop, uv in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
                    loop[uvl].uv = uv
    C = top

    def nfn(poly, co):
        if poly.material_index == 1:
            d = co - C
            return (Vector((d.x, d.y, 0)).normalized() * 0.5 + Vector((0, 0, 1))).normalized()
        return Vector((0, 0, 0))
    mats = [_material(spec["bark_mat"], "palmbrk1.png", False), _material(spec["frond_mat"], "palmleaf_a.png", True)]
    return _finish(bm, spec, mats, spec["size"], nfn)


def make_bush(spec):
    """Desert scrub: a star of tilted vertical cards (desertbush) and a domed top (desertbushtop).
    spec: name, seed, size, n_cards, top_mat, side_mat."""
    random.seed(spec["seed"])
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    n = spec["n_cards"]
    R, H = 6.0, 11.0
    for i in range(n):
        a = i * math.pi / n + random.uniform(-.15, .15)
        d = Vector((math.cos(a), math.sin(a), 0))
        tilt = Vector((-d.y, d.x, 0)) * random.uniform(-.25, .25)
        w = R * random.uniform(.9, 1.05)
        hh = H * random.uniform(.85, 1.0)
        off = Vector((random.uniform(-.6, .6), random.uniform(-.6, .6), 0))
        vs = [bm.verts.new(off + d * -w), bm.verts.new(off + d * w),
              bm.verts.new(off + d * w + (Vector((0, 0, 1)) + tilt) * hh), bm.verts.new(off + d * -w + (Vector((0, 0, 1)) + tilt) * hh)]
        f = bm.faces.new(vs)
        f.material_index = 0
        for loop, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uvl].uv = uv
    for i in range(3):
        z = H * random.uniform(.55, .8)
        rr = R * random.uniform(.7, .9)
        a = random.uniform(0, 2 * math.pi)
        nrm = Vector((random.uniform(-.3, .3), random.uniform(-.3, .3), 1)).normalized()
        q = nrm.to_track_quat('Z', 'Y') @ Quaternion((0, 0, 1), a)
        vs = [bm.verts.new(Vector((0, 0, z)) + q @ Vector(c)) for c in ((-rr, -rr, 0), (rr, -rr, 0), (rr, rr, 0), (-rr, rr, 0))]
        f = bm.faces.new(vs)
        f.material_index = 1
        for loop, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uvl].uv = uv
    C = Vector((0, 0, H * .4))

    def nfn(poly, co):
        d = co - C
        return Vector((d.x / R ** 2, d.y / R ** 2, d.z / (H * .6) ** 2 + 0.02)).normalized()
    mats = [_material(spec["side_mat"], "desertbush_a.png", True), _material(spec["top_mat"], "desertbushtop_a.png", True)]
    return _finish(bm, spec, mats, spec["size"], nfn)
