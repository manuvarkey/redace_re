class_name Particles
extends Node3D
## Billboard particle systems like the original "Dive - Renderware Particles" (decomp FUN_0044790a):
## smoke, cloth, hit, maroon and clod textures from objects/particles. Each particle has position,
## velocity, gravity, size growth and a colour that changes linearly; it dies when its alpha reaches 0.
## Emitters (decomp RedAce.c):
##   burst (FUN_004511f8 / FUN_00451f91, size s clamped 1..2): for 10 s, 20s streams with fixed velocities (x,z in
##     -20s..20s, y in 15s..45s, y falls by 15 t^2) each draw a dark head at age t, an orange trail 0.15 s apart behind it
##     and four core puffs; recomputed from the age every frame, not simulated;
##   smoke column (FUN_004510d2 / FUN_00451c5f, size s): never ends; puffs on a repeating lifetime u = 0..1 climb
##     (120..247) * s, spread 20s * u, grow to 20s * u, fade alpha 0.7 * (1 - u) and grey 1 - 0.7u, thinned by distance;
##   damage smoke (RedAce.c:31878), cloth on hits (FUN_0042eda0), hit / maroon puffs on bullet impacts
##     (FUN_0044cd2a) are emitted by their callers through puff().

const MAX_PER_SYSTEM := {"smoke": 700, "cloth": 60, "hit": 80, "maroon": 80, "clod": 120, "emitters": 2500}
const QUAD_SCALE := 2.0  # the exe draws one triangle whose texture square is 2 * size wide; the rest is the mask's empty edge (FUN_004517ef)
const MAX_COLUMNS := 400

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
		var p := Ini.data_path("objects/particles/%s.png" % ("smoke" if n == "emitters" else n))
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
	var streams := []
	for i in int(20.0 * size):
		streams.append(Vector3(randf_range(-20, 20) * size, randf_range(15, 45) * size, randf_range(-20, 20) * size))
	_bursts.append({"pos": pos, "s": size, "t": 0.0, "streams": streams,
		"weight": streams.size() * int(4.0 + size) * 1.5})


func smoke_column(pos: Vector3, size: float) -> void:
	var height := float(randi() % 128 + 120) * size
	var life := size * height * 0.05
	var jitter := PackedVector3Array()
	for i in 64:
		jitter.append(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)))
	_columns.append({"pos": pos, "s": size, "height": height, "life": life, "t": -life, "weight": int(25.0 * size),
		"jitter": jitter})
	if _columns.size() > MAX_COLUMNS:
		_columns.pop_front()


## Share of the effects budget for an emitter (FUN_00451409): by distance, nothing behind the camera or past far.
func _emitter_weight(pos: Vector3, weight: float, far: float, limit: float) -> float:
	var to := pos - camera.global_position
	if -camera.global_transform.basis.z.dot(to) <= 0.0 or to.length() >= limit:
		return -1.0
	return (far - to.length()) * weight * 2.0 / far


func _add_quad(list: Array, pos: Vector3, size: float, c: Color) -> void:
	list.append([pos, absf(size) * QUAD_SCALE, c])


func _emit_columns(list: Array, far: float) -> void:
	var total := 0.0
	var weights := []
	for c in _columns:
		var w := _emitter_weight(c.pos, c.weight, far, far)
		weights.append(w)
		total += maxf(w, 0.0)
	var share := minf(detail * 1000.0 * 0.4 / total, 1.5) if total > 0.0 else 0.0
	for i in _columns.size():
		var left := int(weights[i] * share)
		if left <= 0:
			continue
		var c: Dictionary = _columns[i]
		var jitter: PackedVector3Array = c.jitter
		var step := 0.5
		var n := 0
		while left > 0 and step > 0.0004:
			var f := step
			while f < 1.0 and left > 0:
				var u: float = c.t / c.life + f
				if c.t > 0.0:
					u = fmod(u, 1.0)
				left -= 1
				n += 1
				f += step * 2.0
				if u <= 0.0:
					continue
				var j: Vector3 = jitter[n % jitter.size()]
				var grey := 1.0 - u * 0.7
				_add_quad(list, c.pos + Vector3.UP * (u * c.height) + j * (u * 20.0 * c.s), u * 20.0 * c.s,
					Color(grey, grey, grey, (1.0 - u) * 0.7))
			step *= 0.5


func _emit_bursts(list: Array, far: float) -> void:
	var total := 0.0
	var weights := []
	for b in _bursts:
		var w := _emitter_weight(b.pos, b.weight, far, 600.0)
		weights.append(w)
		total += maxf(w, 0.0)
	var share := detail * 1000.0 * 0.6 / total if total > 0.0 else 1.0
	for i in _bursts.size():
		if weights[i] * share < 1.0:
			continue
		var b: Dictionary = _bursts[i]
		var s: float = b.s
		var trail := int(4.0 + s) * 3 / 2
		var streams: int = b.streams.size()
		var budget := maxi(int(weights[i] * share), 20)
		while streams * trail > budget and streams > 0:
			streams -= 1
		var samples := trail / 3 * 2
		for k in streams:
			var v: Vector3 = b.streams[k]
			var at: float = b.t
			_add_quad(list, _on_path(b.pos, v, at), 2.0 * s, Color(0.1, 0.1, 0.1, 0.9))
			at = maxf(at - 0.15, 0.0)
			for j in range(1, samples):
				var p := _on_path(b.pos, v, at)
				at -= 0.15
				if at >= 0.0:
					_add_quad(list, p, -at * 0.5 * s + 2.0 * s,
						Color(0.9 - j * 0.08, 0.6 - j * 0.08, 0.4 - j * 0.05, 0.8 - j * 0.05))
			at = 0.15 * b.t * 2.5
			var size := 2.0 * s * 2.5
			for j in 4:
				var p: Vector3 = b.pos + v * (at * 0.5) + Vector3.DOWN * 15.0 * 0.5 * (at * at + b.t * b.t)
				at += 0.15 * b.t * 2.5
				size *= 0.75
				var d := float(3 - j) * 2.0
				_add_quad(list, p, size * 1.5, Color(0.9 - d * 0.08, 0.6 - d * 0.08, 0.4 - d * 0.05, 0.8))


static func _on_path(from: Vector3, v: Vector3, t: float) -> Vector3:
	return from + v * t + Vector3.DOWN * 15.0 * t * t


func _process(dt: float) -> void:
	for b in _bursts:
		b.t += dt
	_bursts = _bursts.filter(func(b): return b.t <= 10.0)
	for c in _columns:
		c.t += dt
	var quads := []
	if camera:
		_emit_columns(quads, camera.far)
		_emit_bursts(quads, camera.far)
	var emm: MultiMesh = _systems["emitters"].mm
	var emit_basis := camera.global_transform.basis if camera else Basis.IDENTITY
	emm.visible_instance_count = mini(quads.size(), MAX_PER_SYSTEM["emitters"])
	for i in emm.visible_instance_count:
		var q: Array = quads[i]
		emm.set_instance_transform(i, Transform3D(emit_basis * Basis.from_scale(Vector3.ONE * q[1]), q[0]))
		emm.set_instance_color(i, Color(clampf(q[2].r, 0, 1), clampf(q[2].g, 0, 1), clampf(q[2].b, 0, 1), clampf(q[2].a, 0, 1)))

	var cam_basis := camera.global_transform.basis if camera else Basis.IDENTITY
	for n in _systems:
		if n == "emitters":
			continue
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
