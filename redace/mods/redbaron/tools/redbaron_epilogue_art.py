"""The Red Baron campaign's epilogue picture (not in the original): a war cemetery at dusk, rows of pale crosses
running away into the mist under a sunset sky, poplars beyond, and in the foreground a laurel wreath at the foot
of a cross with a Pour le Merite (blue enamel Maltese cross, gold eagles between the arms) on its black and white
ribbon lying on it. Rendered with Cycles; tools/redbaron_epilogue_art.py --post then grades it (warm sepia, a
darkened calm area where the epilogue text sits, vignette) into
game_data/language/english/campaigns/redbaron/img/epilogue.png (2560 x 1920, like the other full pages).

    blender --background --python redbaron_epilogue_art.py -- OUT.png [width height samples]
    python3 redbaron_epilogue_art.py --post OUT.png
"""
import math
import random
import sys
from pathlib import Path

IMG = Path(__file__).resolve().parents[3] / "game_data" / "language" / "english" / "campaigns" / "redbaron" / "img"


def post(src):
    """Grade the render into the page picture: warm, a calm dark area behind the text, vignette."""
    from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
    im = Image.open(src).convert("RGB").resize((2560, 1920), Image.LANCZOS)
    im = ImageEnhance.Color(im).enhance(0.8)
    warm = Image.new("RGB", im.size, (120, 78, 40))
    im = Image.blend(im, warm, 0.12)
    # the epilogue's text column (page 640 x 480: x 60..580, y 60..380) on a darker, calm field
    mask = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((60 * 4, 50 * 4, 580 * 4, 390 * 4), radius=160, fill=115)
    mask = mask.filter(ImageFilter.GaussianBlur(140))
    im = Image.composite(Image.new("RGB", im.size, (8, 6, 5)), im, mask)
    # vignette
    v = Image.new("L", im.size, 0)
    ImageDraw.Draw(v).ellipse((-500, -400, im.width + 500, im.height + 400), fill=255)
    v = v.filter(ImageFilter.GaussianBlur(260))
    im = Image.composite(im, Image.new("RGB", im.size, (0, 0, 0)), v)
    IMG.mkdir(parents=True, exist_ok=True)
    im.save(IMG / "epilogue.png")
    print("wrote", IMG / "epilogue.png")


def render(out, width=1600, height=1200, samples=96):
    import bpy
    import bmesh
    from mathutils import Vector

    random.seed(1918)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    try:
        scene.render.engine = "CYCLES"
    except TypeError:
        pass
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.film_transparent = False
    try:
        scene.view_settings.view_transform = "Filmic"
    except TypeError:
        pass
    try:
        scene.view_settings.look = "Medium High Contrast"
    except TypeError:
        pass

    def principled(mat):
        return next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")

    def material(name, colour, rough=0.6, metal=0.0, spec=0.3):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        p = principled(m)
        p.inputs["Base Color"].default_value = (*colour, 1.0)
        p.inputs["Roughness"].default_value = rough
        p.inputs["Metallic"].default_value = metal
        return m

    def noisy(mat, colour2, scale=6.0, bump=0.3):
        nt = mat.node_tree
        p = principled(mat)
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = scale
        tex.inputs["Detail"].default_value = 8.0
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs[6].default_value = p.inputs["Base Color"].default_value
        mix.inputs[7].default_value = (*colour2, 1.0)
        nt.links.new(tex.outputs["Fac"], mix.inputs[0])
        nt.links.new(mix.outputs[2], p.inputs["Base Color"])
        b = nt.nodes.new("ShaderNodeBump")
        b.inputs["Strength"].default_value = bump
        nt.links.new(tex.outputs["Fac"], b.inputs["Height"])
        nt.links.new(b.outputs["Normal"], p.inputs["Normal"])
        return mat

    def box(name, size, loc, mat, rot=(0, 0, 0)):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
        o = bpy.context.object
        o.name = name
        o.scale = size
        bpy.ops.object.transform_apply(scale=True)
        o.data.materials.append(mat)
        bev = o.modifiers.new("bevel", "BEVEL")
        bev.width = min(size) * 0.12
        bev.segments = 2
        return o

    # ---- ground
    grass = noisy(material("grass", (0.09, 0.13, 0.04), 0.9), (0.22, 0.20, 0.08), 2.5, 0.35)
    bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 0, 0))
    g = bpy.context.object
    g.data.materials.append(grass)
    gravel = material("gravel", (0.22, 0.18, 0.13), 1.0)
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.0, 60.0, 0.01))
    path = bpy.context.object
    path.scale = (1.6, 130.0, 1.0)
    path.data.materials.append(gravel)

    # ---- the crosses: rows running away from the camera (+y), a path down the middle
    stone = noisy(material("stone", (0.78, 0.74, 0.66), 0.75), (0.55, 0.52, 0.46), 18.0, 0.2)
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    proto = bpy.context.object
    bm = bmesh.new()
    # the upright and the two arms as separate blocks (no overlapping faces)
    for size, x, z in (((0.11, 0.09, 1.05), 0.0, 0.525), ((0.225, 0.09, 0.11), -0.1675, 0.78), ((0.225, 0.09, 0.11), 0.1675, 0.78)):
        geom = bmesh.ops.create_cube(bm, size=1.0)
        for v in geom["verts"]:
            v.co.x = v.co.x * size[0] + x
            v.co.y *= size[1]
            v.co.z = v.co.z * size[2] + z
    bm.to_mesh(proto.data)
    bm.free()
    proto.data.materials.append(stone)
    bev = proto.modifiers.new("bevel", "BEVEL")
    bev.width = 0.012
    bev.segments = 2
    proto.location = (0, -50, -10)  # out of view: the rows are linked copies
    for row in range(26):
        y = 4.0 + row * 2.7
        for col in list(range(-9, -1)) + list(range(2, 10)):
            x = col * 1.9 + random.uniform(-0.05, 0.05)
            o = proto.copy()
            o.data = proto.data
            scene.collection.objects.link(o)
            o.location = (x, y + random.uniform(-0.08, 0.08), 0.0)
            o.rotation_euler = (random.uniform(-0.02, 0.02), random.uniform(-0.03, 0.03), random.uniform(-0.04, 0.04))

    # ---- the foreground cross, a laurel wreath against it, the medal on the wreath
    fg = proto.copy()
    fg.data = proto.data
    scene.collection.objects.link(fg)
    fg.location = (-1.25, 2.6, 0.0)
    fg.rotation_euler = (0, 0, 0.18)
    fg.scale = (1.15, 1.15, 1.15)
    laurel = noisy(material("laurel", (0.06, 0.10, 0.04), 0.55), (0.14, 0.17, 0.06), 40.0, 0.8)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.30, minor_radius=0.07, major_segments=64, minor_segments=16,
                                     location=(-1.18, 2.47, 0.34), rotation=(math.radians(78), 0, 0.18))
    wreath = bpy.context.object
    wreath.data.materials.append(laurel)
    disp = wreath.modifiers.new("leaves", "DISPLACE")
    t = bpy.data.textures.new("leafnoise", "CLOUDS")
    t.noise_scale = 0.03
    disp.texture = t
    disp.strength = 0.05
    # the medal: an eight-pointed (Maltese) cross, blue enamel in gold, gold eagles between the arms, on its ribbon
    gold = material("gold", (0.85, 0.62, 0.22), 0.25, 1.0)
    enamel = material("enamel", (0.03, 0.08, 0.40), 0.12, 0.0)
    ribbon_black = material("ribbon_black", (0.02, 0.02, 0.02), 0.5)
    ribbon_white = material("ribbon_white", (0.80, 0.80, 0.78), 0.5)
    medal = bpy.data.objects.new("medal", None)
    scene.collection.objects.link(medal)

    def maltese(name, r_out, r_in, depth, mat, z):
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        pts = []
        for k in range(4):
            a = k * math.pi / 2
            for ang, rad in ((-0.10, r_in * 0.18), (-0.42, r_out), (0.0, r_out * 0.72), (0.42, r_out), (0.10, r_in * 0.18)):
                pts.append((math.sin(a + ang) * rad, math.cos(a + ang) * rad))
        verts = [bm.verts.new((x, y, z)) for x, y in pts]
        face = bm.faces.new(verts)
        ext = bmesh.ops.extrude_face_region(bm, geom=[face])
        for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
            v.co.z += depth
        bm.to_mesh(mesh)
        bm.free()
        o = bpy.data.objects.new(name, mesh)
        o.data.materials.append(mat)
        scene.collection.objects.link(o)
        o.parent = medal
        return o

    maltese("medal_gold", 0.075, 0.075, 0.006, gold, 0.0)
    maltese("medal_enamel", 0.066, 0.066, 0.004, enamel, 0.004)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(math.sin(a) * 0.032, math.cos(a) * 0.032, 0.005))
        e = bpy.context.object
        e.scale = (0.018, 0.012, 0.006)
        e.rotation_euler = (0, 0, -a)
        e.data.materials.append(gold)
        e.parent = medal
    for i, (w, mat) in enumerate(((0.036, ribbon_black), (0.006, ribbon_white), (0.006, ribbon_white))):
        x = 0.0 if i == 0 else (0.021 if i == 1 else -0.021)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, 0.16, 0.002))
        rb = bpy.context.object
        rb.scale = (w, 0.17, 0.002)
        rb.data.materials.append(mat)
        rb.parent = medal
    medal.location = (-1.16, 2.40, 0.40)
    medal.rotation_euler = (math.radians(-78), 0, math.radians(180 + 10))
    medal.scale = (1.6, 1.6, 1.6)

    # ---- poplars beyond, and along the sides
    leaf = noisy(material("poplar", (0.03, 0.05, 0.025), 0.8), (0.06, 0.07, 0.03), 3.0, 0.5)
    bark = material("bark", (0.06, 0.05, 0.04), 0.9)
    spots = [(x + random.uniform(-1.5, 1.5), 80.0 + random.uniform(-6, 10)) for x in range(-40, 44, 8)]
    spots += [(-24.0 + random.uniform(-1, 1), y) for y in range(10, 70, 9)]
    spots += [(25.0 + random.uniform(-1, 1), y) for y in range(14, 70, 9)]
    for x, y in spots:
        h = random.uniform(11, 21)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.25, depth=3, location=(x, y, 1.5))
        bpy.context.object.data.materials.append(bark)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, location=(x, y, 2.5 + h * 0.5))
        c = bpy.context.object
        c.scale = (random.uniform(1.6, 2.2), random.uniform(1.6, 2.2), h * 0.5)
        c.data.materials.append(leaf)

    # ---- sky: a sunset gradient by height, the sun low ahead; mist through the cemetery
    world = bpy.data.worlds.new("dusk")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    els = ramp.color_ramp.elements
    # (the world's Generated coordinate is the view direction: z 0 at the horizon, 1 straight up)
    els[0].position = 0.0
    els[0].color = (1.0, 0.55, 0.20, 1.0)
    els[1].position = 0.45
    els[1].color = (0.05, 0.04, 0.09, 1.0)
    mid = els.new(0.05)
    mid.color = (0.95, 0.33, 0.12, 1.0)
    mid2 = els.new(0.16)
    mid2.color = (0.40, 0.15, 0.17, 1.0)
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.6
    # mist: a bounded volume over the cemetery (a world volume would swallow the sky)
    mist = bpy.data.materials.new("mist")
    mist.use_nodes = True
    mn = mist.node_tree
    for n in list(mn.nodes):
        if n.type == "BSDF_PRINCIPLED":
            mn.nodes.remove(n)
    vol = mn.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Density"].default_value = 0.0018
    vol.inputs["Color"].default_value = (0.75, 0.55, 0.45, 1.0)
    mout = next(n for n in mn.nodes if n.type == "OUTPUT_MATERIAL")
    mn.links.new(vol.outputs[0], mout.inputs["Volume"])
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 60, 5))
    box_ = bpy.context.object
    box_.scale = (160, 150, 14)
    box_.data.materials.append(mist)

    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 2.6
    sun_data.color = (1.0, 0.62, 0.35)
    sun_data.angle = math.radians(3)
    sun = bpy.data.objects.new("sun", sun_data)
    scene.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(84), 0, math.radians(180 + 12))  # low, ahead and a little left: backlight
    fill_data = bpy.data.lights.new("fill", "AREA")
    fill_data.energy = 60.0
    fill_data.size = 4.0
    fill_data.color = (0.75, 0.70, 0.85)
    fill = bpy.data.objects.new("fill", fill_data)
    scene.collection.objects.link(fill)
    fill.location = (1.5, -1.5, 3.0)
    fill.rotation_euler = (math.radians(55), 0, math.radians(20))

    # ---- camera: low, looking down the rows to the sunset, the wreath and medal in the near left
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 32
    cam_data.dof.use_dof = True
    cam_data.dof.focus_distance = 3.2
    cam_data.dof.aperture_fstop = 5.6
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0.35, -0.2, 0.95)
    cam.rotation_euler = (math.radians(88), 0, math.radians(7))
    scene.camera = cam
    scene.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)
    print("rendered", out)


if __name__ == "__main__":
    if "--post" in sys.argv:
        post(sys.argv[sys.argv.index("--post") + 1])
    else:
        args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["/tmp/epilogue_render.png"]
        w, h, s = (int(a) for a in (args[1:4] if len(args) >= 4 else (1600, 1200, 96)))
        render(args[0], w, h, s)
