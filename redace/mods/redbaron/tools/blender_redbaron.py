"""Red Baron mod models, authored in Blender (run with `blender --background --python` or through the MCP
bridge with tools/run_blender_mcp.py): the RE8 two-seater, the Handley Page O/100 bomber and the
Caquot observation balloon. Low poly like the stock planes, at the stock planes' scale (2.5 units per
metre: the stock Albatros D.III spans 22.5 for 9.0 m), in game axes (+Y up, +Z nose, X span), exported
as glTF without axis conversion like the Britain models. Each plane: model, damaged1, damaged2, wreck
(paint scorched, airframe rigid), a flat shadow clump; propellers are separate objects with their pivot
at the hub and a material named soppropeller* so the game spins them. The balloon: model, a scorched
sagging stage and a wreck of tatters. Writes overrides/redbaron/objects/... and saves the .blend there.
"""
import bpy, math, sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[4]
OVR = ROOT / "overrides" / "redbaron"
TEX = OVR / "textures"
U = 2.5  # game units per metre

if bpy.context.window:  # through the MCP bridge: a scene of its own, the user's scenes stay as they are
    scene = bpy.data.scenes.get("Red Baron assets") or bpy.data.scenes.new("Red Baron assets")
    bpy.context.window.scene = scene
else:  # blender --background --factory-startup: the empty default scene
    scene = bpy.context.scene
for o in list(scene.objects):
    bpy.data.objects.remove(o, do_unlink=True)

materials = {}
parts = []


def material(name, colour, texture=None):
    full = name if name.startswith("soppropeller") else "RB_" + name  # the game spins soppropeller* atomics
    m = bpy.data.materials.get(full) or bpy.data.materials.new(full)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    p.inputs["Base Color"].default_value = (*colour, 1)
    p.inputs["Roughness"].default_value = 0.85
    for n in [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE"]:
        m.node_tree.nodes.remove(n)
    if texture:
        t = m.node_tree.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(str(TEX / (texture + ".png")), check_existing=True)
        mix = m.node_tree.nodes.new("ShaderNodeMix") if bpy.app.version >= (3, 4) else None
        if mix:
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs[0].default_value = 1.0
            mix.inputs[6].default_value = (*colour, 1)
            m.node_tree.links.new(t.outputs["Color"], mix.inputs[7])
            m.node_tree.links.new(mix.outputs[2], p.inputs["Base Color"])
        else:
            m.node_tree.links.new(t.outputs["Color"], p.inputs["Base Color"])
    materials[name] = m
    return m


# PC10 (khaki green-brown, upper and side surfaces), clear dope (undersides), roundel colours, metal
PAINT = [("pc10", (0.27, 0.25, 0.15), "fabric"), ("clear", (0.80, 0.74, 0.58), "fabric"),
         ("pc10_s1", (0.27, 0.25, 0.15), "fabric_scorch1"), ("clear_s1", (0.80, 0.74, 0.58), "fabric_scorch1"),
         ("pc10_s2", (0.27, 0.25, 0.15), "fabric_scorch2"), ("clear_s2", (0.80, 0.74, 0.58), "fabric_scorch2"),
         ("balloon", (0.62, 0.62, 0.57), "fabric"), ("balloon_s1", (0.62, 0.62, 0.57), "fabric_scorch1"),
         ("balloon_s2", (0.45, 0.43, 0.40), "fabric_scorch2"), ("wicker", (1, 1, 1), "wicker"),
         ("red", (0.55, 0.07, 0.05), None), ("white", (0.85, 0.84, 0.78), None), ("blue", (0.08, 0.12, 0.35), None),
         ("metal", (0.36, 0.36, 0.33), None), ("black", (0.04, 0.04, 0.04), None), ("wood", (0.38, 0.25, 0.13), None),
         ("glass", (0.25, 0.32, 0.33), None), ("scorch", (0.10, 0.09, 0.08), None), ("shadow", (0, 0, 0), None),
         ("soppropeller_rb", (0.33, 0.21, 0.10), None), ("rope", (0.45, 0.40, 0.30), None)]
for n, c, t in PAINT:
    material(n, c, t)
SCORCH = {1: {"pc10": "pc10_s1", "clear": "clear_s1", "balloon": "balloon_s1"},
          2: {"pc10": "pc10_s2", "clear": "clear_s2", "balloon": "balloon_s2"}}


def mesh(name, verts, faces, mat, uvscale=12.0):
    # a two-sided card (the same vertices listed again in reverse) gets its own copy of the vertices:
    # Blender rejects two faces on one vertex set
    verts, seen, out = list(verts), set(), []
    for f in faces:
        key = frozenset(f)
        if key in seen:
            base = len(verts)
            verts += [verts[i] for i in f]
            f = tuple(range(base, base + len(f)))
        seen.add(key)
        out.append(f)
    faces = out
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    scene.collection.objects.link(o)
    me.materials.append(materials[mat])
    uv = me.uv_layers.new()
    for poly in me.polygons:
        a = max(range(3), key=lambda j: abs(poly.normal[j]))
        axes = [j for j in range(3) if j != a]
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (v[axes[0]] / uvscale, v[axes[1]] / uvscale)
    parts.append(o)
    return o


def box(name, c, size, mat):
    x, y, z = c
    w, h, d = size
    v = [(x + a * w / 2, y + b * h / 2, z + e * d / 2) for a, b, e in
         [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    return mesh(name, v, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 4, 7, 3), (1, 2, 6, 5), (3, 7, 6, 2), (0, 1, 5, 4)], mat)


def beam(name, a, b, r, mat, sides=4):
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    u = d.cross(Vector((0, 1, 0)))
    if u.length < 0.1:
        u = d.cross(Vector((1, 0, 0)))
    u.normalize()
    w = d.cross(u)
    vs = [tuple(p + r * (math.cos(i * math.tau / sides) * u + math.sin(i * math.tau / sides) * w))
          for p in (a, b) for i in range(sides)]
    faces = [tuple(range(sides - 1, -1, -1)), tuple(range(sides, 2 * sides))] + \
            [(i, (i + 1) % sides, (i + 1) % sides + sides, i + sides) for i in range(sides)]
    return mesh(name, vs, faces, mat)


def loft(name, sections, mat, closed=True):
    """sections: lists of points (same count), joined in order; caps at both ends."""
    n = len(sections[0])
    vs = [p for s in sections for p in s]
    faces = [(j * n + i, j * n + (i + 1) % n, (j + 1) * n + (i + 1) % n, (j + 1) * n + i)
             for j in range(len(sections) - 1) for i in range(n)]
    if closed:
        faces += [tuple(range(n - 1, -1, -1)), tuple(range((len(sections) - 1) * n, len(sections) * n))]
    return mesh(name, vs, faces, mat)


def wing(name, span, chord, y, z, thick, mat_top, mat_bottom, dihedral=0.0, centre_gap=0.0):
    """Two panels (left and right), each a thin box with upper and lower surfaces in their own paint."""
    for side in (-1, 1):
        x0, x1 = side * centre_gap / 2, side * span / 2
        dy = abs(x1 - x0) * math.tan(math.radians(dihedral))
        top = [(x0, y + thick / 2, z + chord / 2), (x1, y + dy + thick / 2, z + chord / 2),
               (x1, y + dy + thick / 2, z - chord / 2), (x0, y + thick / 2, z - chord / 2)]
        bot = [(p[0], p[1] - thick, p[2]) for p in top]
        f = (0, 1, 2, 3) if side < 0 else (3, 2, 1, 0)
        mesh(name + " top", top, [f], mat_top)
        mesh(name + " bottom", bot, [tuple(reversed(f))], mat_bottom)
        rim = top + bot
        mesh(name + " edges", rim, [(0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)], mat_bottom)


def disc(name, c, r, normal, mat, sides=12):
    c, n = Vector(c), Vector(normal).normalized()
    u = n.cross(Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))).normalized()
    w = n.cross(u)
    vs = [tuple(c + r * (math.cos(i * math.tau / sides) * u + math.sin(i * math.tau / sides) * w)) for i in range(sides)]
    return mesh(name, vs, [tuple(range(sides))], mat)


def roundel(c, r, normal):
    n = Vector(normal).normalized()
    disc("Roundel blue", Vector(c) + n * 0.02, r, n, "blue")
    disc("Roundel white", Vector(c) + n * 0.04, r * 0.66, n, "white")
    disc("Roundel red", Vector(c) + n * 0.06, r * 0.33, n, "red")


def wheel(c, r, w):
    x, y, z = c
    sides = 10
    sec = [[(x + s * w / 2, y + r * math.sin(i * math.tau / sides), z + r * math.cos(i * math.tau / sides))
            for i in range(sides)] for s in (-1, 1)]
    loft("Wheel", sec, "black")


def propeller(c, radius, blades=2):
    vs, faces = [], []
    for k in range(blades):
        a = k * math.tau / blades
        ca, sa = math.cos(a), math.sin(a)
        base = len(vs)
        for px, py in [(0.25, 0.3), (0.35, radius), (-0.35, radius), (-0.25, 0.3)]:
            vs.append((px * ca - py * sa, px * sa + py * ca, 0.0))
        faces += [(base, base + 1, base + 2, base + 3), (base + 3, base + 2, base + 1, base)]
    o = mesh("Propeller", vs, faces, "soppropeller_rb")
    o.location = c
    return o


def shadow(name, outline_quads):
    """A flat planform at y = 0 (the game flattens and places it under the plane)."""
    global parts
    keep = parts
    parts = []
    for q in outline_quads:
        mesh("Shadow", [(x, 0.0, z) for x, z in q], [(0, 1, 2, 3), (3, 2, 1, 0)], "shadow")
    objs = parts
    parts = keep
    return objs


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def gltf(path, objs):
    select_only(objs)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLTF_SEPARATE", use_selection=True,
                              export_yup=False, export_apply=True, export_materials="EXPORT", export_texcoords=True)


def tris(objs):
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)


def finish(name, folder, shadow_objs=None, stages=("damaged1", "damaged2", "wreck"), balloon=False):
    """Join the static parts, export the model and its damage stages."""
    global parts
    props = [o for o in parts if o.name.startswith("Propeller")]
    static = [o for o in parts if not o.name.startswith("Propeller")]
    select_only(static)
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name
    out = OVR / "objects" / folder / name
    objs = [body] + props
    gltf(out / f"{name}.gltf", objs)
    report = {"model": tris(objs)}
    for stage, file in enumerate(stages, 1):
        clones = []
        for src in objs:
            c = src.copy()
            c.data = src.data.copy()
            scene.collection.objects.link(c)
            c.name = f"{name}_{file}"
            level = min(stage, 2)
            for slot, mat in enumerate(c.data.materials):
                key = mat.name[3:] if mat.name.startswith("RB_") else mat.name
                if key in SCORCH[level]:
                    c.data.materials[slot] = materials[SCORCH[level][key]]
            if file == "wreck":
                c.data.materials.append(materials["scorch"])
                burn = len(c.data.materials) - 1
                for poly in c.data.polygons:
                    p = poly.center
                    if math.sin(p.x * 0.7 + p.z * 0.53) + math.cos(p.y * 0.91) > -0.2:
                        poly.material_index = burn
                if balloon:  # the envelope burns away: tatters round the basket and rigging
                    import bmesh
                    bm = bmesh.new()
                    bm.from_mesh(c.data)
                    gone = [f for f in bm.faces if f.calc_center_median().y > -6.0 and
                            (math.sin(f.calc_center_median().x * 1.3) + math.cos(f.calc_center_median().z * 0.9)) > -0.6]
                    bmesh.ops.delete(bm, geom=gone, context="FACES")
                    for v in bm.verts:
                        if v.co.y > -6.0:
                            v.co.y = -6.0 + (v.co.y + 6.0) * 0.25
                    bm.to_mesh(c.data)
                    bm.free()
            elif balloon:  # scorched and going soft: sags and narrows
                for v in c.data.vertices:
                    if v.co.y > -6.0:
                        v.co.y *= 0.9
                        v.co.x *= 0.93
            clones.append(c)
        gltf(out / f"{file}.gltf", clones)
        report[file] = tris(clones)
        for c in clones:
            bpy.data.objects.remove(c, do_unlink=True)
    if shadow_objs:
        select_only(shadow_objs)
        bpy.ops.object.join()
        s = bpy.context.view_layer.objects.active
        s.name = name + "shadow"
        gltf(out / f"{name}shadow.gltf", [s])
        s.hide_set(True)
    for o in objs:
        o.hide_set(True)
    parts = []
    print(f"MODEL {name}: " + ", ".join(f"{k} {v} tris" for k, v in report.items()))


# ------------------------------------------------------------------ RE8 (R.A.F. Reconnaissance Experimental 8)
def re8():
    m = U
    L = 8.5 * m  # 21.3
    zn, zt = 0.42 * L, -0.58 * L  # nose and tail
    secs = []
    for z, w, h, yc in [(zn, 1.0, 1.25, 0.15), (zn - 1.0 * m, 1.05, 1.45, 0.1), (zn - 2.6 * m, 1.0, 1.5, 0.05),
                        (zn - 4.6 * m, 0.8, 1.2, 0.0), (zn - 6.4 * m, 0.45, 0.75, 0.05), (zt, 0.12, 0.35, 0.15)]:
        w, h, yc = w * m / 2, h * m / 2, yc * m
        secs.append([(-w, yc - h, z), (w, yc - h, z), (w, yc + h, z), (-w, yc + h, z)])
    loft("Fuselage", secs, "pc10")
    box("Engine cowling", (0, 0.25 * m, zn - 0.4 * m), (1.1 * m, 1.35 * m, 0.9 * m), "metal")
    box("Air scoop", (0, 1.05 * m, zn - 0.2 * m), (0.6 * m, 0.7 * m, 0.7 * m), "metal")
    for side in (-1, 1):
        beam("Exhaust", (side * 0.25 * m, 0.9 * m, zn - 0.9 * m), (side * 0.25 * m, 2.2 * m, zn - 1.6 * m), 0.18, "black")
    # wings: upper span 13.0 m, lower 12.2 m, chord 1.7 m, gap 1.9 m; the RE8's upper wing overhangs
    wing("Upper wing", 13.0 * m, 1.7 * m, 1.75 * m, zn - 2.3 * m, 0.3, "pc10", "clear", dihedral=2.5)
    wing("Lower wing", 12.2 * m, 1.6 * m, -0.15 * m, zn - 2.5 * m, 0.3, "pc10", "clear", dihedral=2.5, centre_gap=1.0 * m)
    for side in (-1, 1):
        for x in (2.2, 5.2):
            beam("Interplane strut", (side * x * m, -0.1 * m, zn - 2.3 * m), (side * x * m, 1.7 * m, zn - 2.2 * m), 0.18, "wood")
            beam("Interplane strut", (side * x * m, -0.1 * m, zn - 3.2 * m), (side * x * m, 1.7 * m, zn - 3.0 * m), 0.18, "wood")
        beam("Cabane", (side * 0.4 * m, 0.7 * m, zn - 2.0 * m), (side * 0.5 * m, 1.65 * m, zn - 1.9 * m), 0.14, "metal")
        roundel((side * 5.0 * m, 1.75 * m + 0.25 + 0.2, zn - 2.3 * m), 0.65 * m, (0, 1, 0))
        roundel((side * 4.8 * m, -0.15 * m - 0.3, zn - 2.5 * m), 0.6 * m, (0, -1, 0))
        roundel((side * 0.52 * m, 0.1 * m, zn - 5.6 * m), 0.35 * m, (side, 0, 0))
        beam("Undercarriage", (side * 0.4 * m, -0.6 * m, zn - 0.9 * m), (side * 0.85 * m, -1.45 * m, zn - 1.4 * m), 0.14, "wood")
        beam("Undercarriage", (side * 0.4 * m, -0.6 * m, zn - 2.0 * m), (side * 0.85 * m, -1.45 * m, zn - 1.4 * m), 0.14, "wood")
        wheel((side * 1.0 * m, -1.5 * m, zn - 1.4 * m), 0.4 * m, 0.15 * m)
    beam("Axle", (-1.0 * m, -1.5 * m, zn - 1.4 * m), (1.0 * m, -1.5 * m, zn - 1.4 * m), 0.1, "metal")
    # tail: tailplane 4 m, the RE8's tall fin and rudder with the period stripes
    wing("Tailplane", 4.2 * m, 1.1 * m, 0.2 * m, zt + 0.7 * m, 0.2, "pc10", "clear")
    fin = [(0, 0.3 * m, zt + 1.6 * m), (0, 1.6 * m, zt + 0.4 * m), (0, 1.6 * m, zt), (0, 0.2 * m, zt)]
    mesh("Fin", fin, [(0, 1, 2, 3), (3, 2, 1, 0)], "pc10")
    for i, c in enumerate(("blue", "white", "red")):
        z0 = zt - i * 0.28 * m
        mesh("Rudder stripe", [(0, 0.1 * m, z0), (0, 1.6 * m, z0), (0, 1.6 * m, z0 - 0.28 * m), (0, 0.1 * m, z0 - 0.28 * m)],
             [(0, 1, 2, 3), (3, 2, 1, 0)], c)
    # cockpits: pilot, observer behind with the Scarff ring and Lewis gun
    box("Pilot", (0, 0.95 * m, zn - 3.0 * m), (0.45 * m, 0.45 * m, 0.4 * m), "wood")
    box("Observer", (0, 0.95 * m, zn - 4.3 * m), (0.45 * m, 0.45 * m, 0.4 * m), "wood")
    ring = [(0.55 * m * math.cos(i * math.tau / 10), 0.78 * m, zn - 4.3 * m + 0.55 * m * math.sin(i * math.tau / 10)) for i in range(10)]
    for i in range(10):
        beam("Scarff ring", ring[i], ring[(i + 1) % 10], 0.1, "metal", sides=3)
    beam("Lewis gun", (0, 1.25 * m, zn - 4.3 * m), (0.2 * m, 1.35 * m, zn - 5.6 * m), 0.12, "black")
    beam("Vickers", (0.3 * m, 0.85 * m, zn - 0.6 * m), (0.3 * m, 0.85 * m, zn - 1.8 * m), 0.1, "black")
    propeller((0, 0.25 * m, zn + 0.25), 1.45 * m, blades=4)
    sh = shadow("re8", [[(-6.5 * m, zn - 1.45 * m), (6.5 * m, zn - 1.45 * m), (6.5 * m, zn - 3.15 * m), (-6.5 * m, zn - 3.15 * m)],
                        [(-0.5 * m, zn), (0.5 * m, zn), (0.2 * m, zt), (-0.2 * m, zt)],
                        [(-2.1 * m, zt + 1.25 * m), (2.1 * m, zt + 1.25 * m), (2.1 * m, zt + 0.15 * m), (-2.1 * m, zt + 0.15 * m)]])
    finish("re8", "planes", sh)


# ------------------------------------------------------------------ Handley Page O/100
def handleypage():
    m = U
    L = 19.2 * m  # 48
    zn, zt = 0.42 * L, -0.58 * L
    secs = []
    for z, w, h, yc in [(zn, 0.9, 1.2, 0.2), (zn - 1.2 * m, 1.3, 1.7, 0.1), (zn - 4.0 * m, 1.35, 1.75, 0.0),
                        (zn - 9.0 * m, 1.2, 1.5, 0.0), (zn - 14.0 * m, 0.7, 0.9, 0.1), (zt, 0.3, 0.45, 0.2)]:
        w, h, yc = w * m / 2, h * m / 2, yc * m
        secs.append([(-w, yc - h, z), (w, yc - h, z), (w, yc + h, z), (-w, yc + h, z)])
    loft("Fuselage", secs, "pc10")
    box("Cockpit glazing", (0, 0.85 * m, zn - 1.6 * m), (1.2 * m, 0.35 * m, 1.2 * m), "glass")
    # wings: 30.5 m span (upper), lower 21 m inboard of the engines plus outer panels; chord 3.05 m, gap 3.4 m
    wing("Upper wing", 30.5 * m, 3.05 * m, 3.05 * m, zn - 4.6 * m, 0.4, "pc10", "clear", dihedral=0.0)
    wing("Lower wing", 21.0 * m, 3.05 * m, -0.35 * m, zn - 4.6 * m, 0.4, "pc10", "clear", dihedral=0.0, centre_gap=1.4 * m)
    for side in (-1, 1):
        for x in (2.0, 4.4, 7.4, 10.4):
            for dz in (-0.3, 2.6):
                beam("Interplane strut", (side * x * m, -0.3 * m, zn - 3.3 * m - dz * m), (side * x * m, 3.0 * m, zn - 3.3 * m - dz * m), 0.22, "wood")
        # engines between the wings, radiators in front
        ex = side * 4.4 * m
        secs = []
        for z, r in [(zn - 1.0 * m, 0.55), (zn - 2.0 * m, 0.75), (zn - 4.5 * m, 0.7), (zn - 6.2 * m, 0.25)]:
            r *= m
            secs.append([(ex + r * math.cos(i * math.tau / 8), 1.35 * m + r * math.sin(i * math.tau / 8), z) for i in range(8)])
        loft("Nacelle", secs, "metal")
        box("Radiator", (ex, 1.35 * m, zn - 0.95 * m), (1.0 * m, 1.3 * m, 0.25 * m), "black")
        propeller((ex, 1.35 * m, zn - 0.6 * m), 1.7 * m, blades=4)
        for z in (-3.0, -5.6):
            beam("Undercarriage", (ex - 0.5 * m, -0.4 * m, zn + z * m * 0.5), (ex - 0.7 * m, -2.0 * m, zn - 3.0 * m), 0.2, "wood")
            beam("Undercarriage", (ex + 0.5 * m, -0.4 * m, zn + z * m * 0.5), (ex + 0.7 * m, -2.0 * m, zn - 3.0 * m), 0.2, "wood")
        for dx in (-0.7, 0.7):
            wheel((ex + dx * m, -2.0 * m, zn - 3.0 * m), 0.55 * m, 0.25 * m)
        roundel((side * 11.5 * m, 3.05 * m + 0.4, zn - 4.6 * m), 1.2 * m, (0, 1, 0))
        roundel((side * 8.0 * m, -0.35 * m - 0.4, zn - 4.6 * m), 1.1 * m, (0, -1, 0))
        roundel((side * 0.62 * m, 0.0, zn - 12.0 * m), 0.55 * m, (side, 0, 0))
    # biplane tail with twin fins
    for y in (0.3, 1.8):
        wing("Tailplane", 5.0 * m, 1.6 * m, y * m, zt + 1.0 * m, 0.25, "pc10", "clear")
    for side in (-1, 1):
        x = side * 1.3 * m
        mesh("Fin", [(x, 0.3 * m, zt + 1.6 * m), (x, 1.8 * m, zt + 1.6 * m), (x, 1.8 * m, zt + 0.2 * m), (x, 0.3 * m, zt + 0.2 * m)],
             [(0, 1, 2, 3), (3, 2, 1, 0)], "pc10")
        for i, c in enumerate(("blue", "white", "red")):
            z0 = zt + 0.2 * m - i * 0.25 * m
            mesh("Rudder stripe", [(x, 0.3 * m, z0), (x, 1.8 * m, z0), (x, 1.8 * m, z0 - 0.25 * m), (x, 0.3 * m, z0 - 0.25 * m)],
                 [(0, 1, 2, 3), (3, 2, 1, 0)], c)
    # crew: nose gunner's ring and Lewis, dorsal gunner behind the wings
    for zc, y in ((zn - 0.4 * m, 0.8 * m), (zn - 8.0 * m, 0.9 * m)):
        ring = [(0.6 * m * math.cos(i * math.tau / 10), y, zc + 0.6 * m * math.sin(i * math.tau / 10)) for i in range(10)]
        for i in range(10):
            beam("Scarff ring", ring[i], ring[(i + 1) % 10], 0.12, "metal", sides=3)
        box("Gunner", (0, y + 0.3 * m, zc), (0.45 * m, 0.5 * m, 0.4 * m), "wood")
    beam("Nose Lewis", (0, 1.4 * m, zn - 0.4 * m), (0.1 * m, 1.5 * m, zn + 0.8 * m), 0.14, "black")
    beam("Dorsal Lewis", (0, 1.5 * m, zn - 8.0 * m), (0.2 * m, 1.6 * m, zn - 9.4 * m), 0.14, "black")
    sh = shadow("handleypage", [[(-15.25 * m, zn - 3.1 * m), (15.25 * m, zn - 3.1 * m), (15.25 * m, zn - 6.1 * m), (-15.25 * m, zn - 6.1 * m)],
                                [(-0.7 * m, zn), (0.7 * m, zn), (0.2 * m, zt), (-0.2 * m, zt)],
                                [(-2.5 * m, zt + 1.8 * m), (2.5 * m, zt + 1.8 * m), (2.5 * m, zt + 0.2 * m), (-2.5 * m, zt + 0.2 * m)]])
    finish("handleypage", "planes", sh)


# ------------------------------------------------------------------ Caquot type R observation balloon
def balloon():
    m = U
    L = 28.0 * m  # 70
    R = 4.6 * m  # body radius (9.3 m)
    secs = []
    n = 14
    for t in [0.0, 0.03, 0.1, 0.22, 0.38, 0.55, 0.7, 0.82, 0.92, 1.0]:
        # fuller in front, tapering to the tail (z: nose at +L*0.45)
        r = R * (math.sin(math.pi * min(1.0, 0.08 + t * 0.95)) ** 0.55) * (1.0 - 0.25 * t)
        r = max(r, 0.3)
        z = L * 0.45 - t * L
        secs.append([(r * math.cos(i * math.tau / n), r * math.sin(i * math.tau / n), z) for i in range(n)])
    loft("Envelope", secs, "balloon")
    # three tail lobes: the Caquot's air-filled stabilisers, top and two below at 120 degrees
    for k in range(3):
        a = math.pi / 2 + k * math.tau / 3
        dx, dy = math.cos(a), math.sin(a)
        lsecs = []
        for t, rr in [(0.0, 0.3), (0.25, 1.6), (0.6, 1.8), (1.0, 0.4)]:
            z = -L * 0.22 - t * L * 0.28
            cx, cy = dx * (R * 0.5 + rr * m * 0.6), dy * (R * 0.5 + rr * m * 0.6)
            lsecs.append([(cx + rr * m * 0.55 * math.cos(i * math.tau / 8) * abs(dy) + rr * m * 0.25 * math.cos(i * math.tau / 8) * abs(dx),
                           cy + rr * m * 0.55 * math.sin(i * math.tau / 8) * abs(dx) + rr * m * 0.25 * math.sin(i * math.tau / 8) * abs(dy), z)
                          for i in range(8)])
        loft("Tail lobe", lsecs, "balloon")
    # basket hanging 6 m below on its rigging, observers' telephone line and the tether
    by = -R - 6.0 * m
    box("Basket", (0, by, 0), (1.4 * m, 1.1 * m, 1.4 * m), "wicker")
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        beam("Rigging", (sx * 0.7 * m, by + 0.55 * m, sz * 0.7 * m), (sx * 1.8 * m, -R * 0.85, sz * 5.0 * m), 0.08, "rope", sides=3)
    for sz in (-8.0, 8.0):
        beam("Rigging", (0, by + 0.55 * m, 0), (0, -R * 0.95, sz * m), 0.08, "rope", sides=3)
    beam("Tether", (0, by - 0.55 * m, 0), (0, by - 110.0 * m, 0), 0.12, "rope", sides=3)
    finish("balloon", "ground", None, stages=("damaged1", "wreck"), balloon=True)


re8()
handleypage()
balloon()
OVR.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(OVR / "redbaron.blend"), copy=True)
print("BLEND", OVR / "redbaron.blend")
