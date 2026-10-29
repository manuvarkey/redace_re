class_name Particles
extends Node3D
## Billboard particle systems like the original "Dive - Renderware Particles" (decomp FUN_0044790a):
## smoke, cloth, hit, maroon and clod textures from objects/particles. Each particle has position,
## velocity, gravity, size growth and a colour that changes linearly; it dies when its alpha reaches 0.
## Emitters (decomp RedAce.c):
##   burst (FUN_004511f8, size s clamped 1..2): ~1 s of fiery puffs, velocity x,z in -20s..20s,
##     y in 15s..45s, gravity -15, size 2s, colour 0.9/0.9/0.6 fading;
##   smoke column (FUN_004510d2, size s): burns (rand(0..127) + 120) * s seconds, grey puffs rising;
##   damage smoke (RedAce.c:31878), cloth on hits (FUN_0042eda0), hit / maroon puffs on bullet impacts
##     (FUN_0044cd2a) are emitted by their callers through puff().

const MAX_PER_SYSTEM := {"smoke": 700, "cloth": 60, "hit": 80, "maroon": 80, "clod": 120}

var camera: Camera3D
var detail := 0.7  # options "Effects Detail" 0..1; thins out smoke and debris
var _systems := {}  # name -> {mm, parts: Array[Dictionary]}
var _bursts: Array[Dictionary] = []
var _columns: Array[Dictionary] = []


func _ready() -> void:
	for n in MAX_PER_SYSTEM:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var p := Ini.data_path("objects/particles/%s.png" % n)
		if ResourceLoader.exists(p):
			mat.albedo_texture = load(p)
		quad.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = MAX_PER_SYSTEM[n]
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.extra_cull_margin = 100000.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_systems[n] = {"mm": mm, "parts": []}


## One particle. color_rate is added per second to rgba; size_rate per second to the size.
func puff(system: String, pos: Vector3, vel: Vector3, size: float, color: Color, color_rate := Color(0, 0, 0, -1),
		size_rate := 0.0, gravity := 0.0) -> void:
	var sys: Dictionary = _systems.get(system, {})
	if sys.is_empty() or randf() > 0.3 + detail:
		return
	var parts: Array = sys.parts
	if parts.size() >= MAX_PER_SYSTEM[system]:
		parts.pop_front()
	parts.append({"pos": pos, "vel": vel, "size": size, "col": color, "dcol": color_rate,
		"dsize": size_rate, "g": gravity, "rot": randf() * TAU})


func burst(pos: Vector3, size: float) -> void:
	size = clampf(size, 1.0, 2.0)
	_bursts.append({"pos": pos, "s": size, "t": 0.0, "acc": 0.0})


func smoke_column(pos: Vector3, size: float) -> void:
	_columns.append({"pos": pos, "s": size, "life": (randi() % 128 + 120) * size, "acc": 0.0})


func _process(dt: float) -> void:
	for b in _bursts:
		b.t += dt
		b.acc += dt * 40.0 * b.s
		var s: float = b.s
		while b.acc >= 1.0:
			b.acc -= 1.0
			var v := Vector3(randf_range(-20, 20) * s, randf_range(15, 45) * s, randf_range(-20, 20) * s)
			puff("smoke", b.pos, v, 2.0 * s * 3.0, Color(0.9, 0.9, 0.6, 0.8), Color(-0.8, -0.8, -0.5, -0.6),
				6.0 * s, -15.0)
			if randf() < 0.3:
				puff("clod", b.pos, v * 1.5, 1.5, Color(0.4, 0.35, 0.3, 1.0), Color(0, 0, 0, -0.5), 0.0, -40.0)
	_bursts = _bursts.filter(func(b): return b.t < 1.0)

	var cam_pos := camera.global_position if camera else Vector3.ZERO
	for c in _columns:
		c.life -= dt
		# the original spreads a fixed particle budget over visible columns by distance
		var d: float = cam_pos.distance_to(c.pos)
		if d > 2500.0:
			continue
		c.acc += dt * (6.0 if d < 800.0 else 2.0)
		while c.acc >= 1.0:
			c.acc -= 1.0
			puff("smoke", c.pos + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)),
				Vector3(randf_range(-2, 2), randf_range(12, 18), randf_range(-2, 2)), 6.0 * c.s,
				Color(0.35, 0.35, 0.35, 0.7), Color(0.08, 0.08, 0.08, -0.09), 2.5 * c.s, 0.0)
	_columns = _columns.filter(func(c): return c.life > 0.0)

	var cam_basis := camera.global_transform.basis if camera else Basis.IDENTITY
	for n in _systems:
		var sys: Dictionary = _systems[n]
		var parts: Array = sys.parts
		var alive := []
		for p in parts:
			p.vel.y += p.g * dt
			p.pos += p.vel * dt
			p.size += p.dsize * dt
			p.col += p.dcol * dt
			if p.col.a > 0.0 and p.size > 0.0:
				alive.append(p)
		sys.parts = alive
		var mm: MultiMesh = sys.mm
		mm.visible_instance_count = alive.size()
		for i in alive.size():
			var p: Dictionary = alive[i]
			var b := cam_basis * Basis(Vector3.BACK, p.rot)
			mm.set_instance_transform(i, Transform3D(b * Basis.from_scale(Vector3.ONE * p.size), p.pos))
			var c: Color = p.col
			mm.set_instance_color(i, Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1), clampf(c.a, 0, 1)))
