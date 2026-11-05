extends Node3D
## Britain-only scenery and sea effects. No screen/depth textures or terrain material edits.
## The exported Dover coast retains the seabed at -12; this owns the surface at y = 0.

const MAP_SIZE := 6000.0
const CAMERA_DISTANCE_SCALE := 0.65
# Centre x/z, width/depth, matching Blender's harbour boxes (including their edges).
const HARBOUR := [
	Rect2(2575.0, 1322.5, 650.0, 55.0),
	Rect2(2665.0, 2172.5, 850.0, 55.0),
	Rect2(3452.5, 1445.0, 55.0, 770.0),
	Rect2(2635.0, 1410.0, 170.0, 580.0),
]
const MAX_CRASHES := 12
const CRASH_LIFETIME := 24.0
var camera_distance_scale := CAMERA_DISTANCE_SCALE
var _crashes: Array[Dictionary] = []
var _water_detail := 1
var _cloud_detail := 1
var _sky_material_ref: ShaderMaterial
var _water_material_ref: ShaderMaterial

const NOISE := """
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), u.x),
		mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), u.x), u.y);
}
float cloud_noise(vec2 p) {
	return noise2(p) * 0.55 + noise2(p * 2.03) * 0.28 + noise2(p * 4.07) * 0.17;
}
"""

# Same analytic boundary as coast(). Shared by the surface and expanding crash rings.
const SEA_DOMAIN := """
float coast(float z) {
	return 3050.0 + 240.0 * sin(z / 540.0) + 110.0 * sin(z / 173.0)
		- 410.0 * exp(-pow((z - 1750.0) / 500.0, 2.0));
}
bool quay(vec2 p, vec2 centre, vec2 half_size) {
	return all(lessThanEqual(abs(p - centre), half_size));
}
bool sea(vec2 p) {
	return p.x > coast(p.y) && p.x <= 6000.0 && p.y >= 0.0 && p.y <= 6000.0
		&& !quay(p, vec2(2900, 1350), vec2(325, 27.5))
		&& !quay(p, vec2(3090, 2200), vec2(425, 27.5))
		&& !quay(p, vec2(3480, 1830), vec2(27.5, 385))
		&& !quay(p, vec2(2720, 1700), vec2(85, 290));
}
"""


static func coast(z: float) -> float:
	return 3050.0 + 240.0 * sin(z / 540.0) + 110.0 * sin(z / 173.0) \
		- 410.0 * exp(-pow((z - 1750.0) / 500.0, 2.0))


func is_sea(pos: Vector3) -> bool:
	if not pos.is_finite() or pos.x < 0.0 or pos.x > MAP_SIZE or pos.z < 0.0 or pos.z > MAP_SIZE:
		return false
	if pos.x <= coast(pos.z):
		return false
	for rect: Rect2 in HARBOUR:
		if pos.x >= rect.position.x and pos.x <= rect.end.x and pos.z >= rect.position.y and pos.z <= rect.end.y:
			return false
	return true


func setup(base_environment: Environment, water_detail := 1, cloud_detail := 1) -> void:
	_water_detail = water_detail
	_cloud_detail = cloud_detail
	name = "BritainEnvironment"
	base_environment.sky = Sky.new()
	_sky_material_ref = _sky_material(base_environment.fog_light_color, _cloud_detail)
	base_environment.sky.sky_material = _sky_material_ref
	base_environment.sky.radiance_size = Sky.RADIANCE_SIZE_64
	_build_water()
	set_process(false)


func _sky_material(horizon: Color, detail := 1) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type sky;
uniform vec3 horizon : source_color;
""" + NOISE + """
void sky() {
	vec3 e = normalize(EYEDIR);
	float altitude = max(e.y, 0.0);
	vec3 colour = mix(horizon, vec3(0.24, 0.43, 0.66), pow(altitude, 0.55));
	vec3 sun_dir = normalize(vec3(-0.48, 0.66, -0.57));
	float sun = max(dot(e, sun_dir), 0.0);
	colour += vec3(1.0, 0.87, 0.64) * (0.15 * pow(sun, 12.0) + 0.6 * pow(sun, 700.0));
	// A projected high cloud deck with a second, finer moving layer; fade at the horizon.
	vec2 p = e.xz / max(e.y + 0.12, 0.12) * 2.6;
	vec2 wind = vec2(TIME * 0.003, TIME * 0.0012);
	float cloud = cloud_noise(p + wind);
	float wisps = cloud_noise(p * 2.8 - wind * 0.65);
	float cover = smoothstep(0.44, 0.7, cloud + wisps * 0.12) * smoothstep(0.0, 0.18, e.y);
	vec3 cloud_colour = mix(vec3(0.60, 0.68, 0.75), vec3(0.97, 0.97, 0.94), smoothstep(0.43, 0.78, cloud));
	COLOR = mix(colour, cloud_colour, cover * 0.92);
}
"""
	if detail == 0:
		# Retain the same broad cloud scales and mean coverage; omit fine noise/wisps.
		shader.code = shader.code.replace("noise2(p * 4.07) * 0.17", "0.085")
		shader.code = shader.code.replace("float wisps = cloud_noise(p * 2.8 - wind * 0.65);", "float wisps = 0.5;")
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("horizon", Vector3(horizon.r, horizon.g, horizon.b))
	return material


func _water_material(detail := 1) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, fog_disabled;
global uniform vec3 ra_fog_colour;
global uniform float ra_fog_far;
varying vec3 world_pos;
varying float eye_depth;
""" + NOISE + SEA_DOMAIN + """
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float shore = smoothstep(0.0, 35.0, world_pos.x - coast(world_pos.z));
	VERTEX.y += shore * (sin(world_pos.x * 0.039 + world_pos.z * 0.028 + TIME * 1.15) * 0.28
		+ sin(world_pos.z * 0.073 - world_pos.x * 0.018 - TIME * 1.65) * 0.12);
	world_pos.y = VERTEX.y;
	eye_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}
void fragment() {
	if (!sea(world_pos.xz)) { discard; }
	vec2 broad = world_pos.xz * 0.026 + vec2(TIME * 0.045, -TIME * 0.023);
	vec2 fine = world_pos.xz * 0.19 + vec2(-TIME * 0.13, TIME * 0.075);
	// Independent moving ripple scales give a world-space normal without imported textures.
	vec2 slope = vec2(noise2(broad + vec2(0.1, 0)) - noise2(broad - vec2(0.1, 0)),
		noise2(broad + vec2(0, 0.1)) - noise2(broad - vec2(0, 0.1))) * 1.5;
	slope += vec2(noise2(fine + vec2(0.12, 0)) - noise2(fine - vec2(0.12, 0)),
		noise2(fine + vec2(0, 0.12)) - noise2(fine - vec2(0, 0.12))) * 0.65;
	vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 4.0);
	float shore_distance = max(world_pos.x - coast(world_pos.z), 0.0);
	// Analytic depth proxy: translucent pale shallows, darker offshore over the -12 seabed.
	float depth = smoothstep(0.0, 160.0, shore_distance);
	vec3 water = mix(vec3(0.19, 0.47, 0.43), vec3(0.055, 0.22, 0.31), depth);
	water = mix(water, vec3(0.52, 0.66, 0.75), fresnel * 0.7);
	float glint = pow(max(dot(reflect(-normalize(vec3(-0.48, 0.66, -0.57)), n), view_dir), 0.0), 90.0);
	water += vec3(0.85, 0.85, 0.68) * glint * 0.55;
	float broken = noise2(world_pos.xz * 0.24 + vec2(TIME * 0.12, -TIME * 0.18));
	float band = 0.5 + 0.5 * sin(shore_distance * 1.1 - TIME * 2.0 + broken * 4.0);
	float foam = (1.0 - smoothstep(1.0, 12.0, shore_distance)) * smoothstep(0.3, 0.75, band + broken * 0.22);
	water = mix(water, vec3(0.88, 0.94, 0.90), foam * 0.85);
	float fog = clamp(((eye_depth - 5.0) / max(ra_fog_far - 5.0, 1.0) - 0.25) / 0.75, 0.0, 1.0);
	ALBEDO = mix(water, ra_fog_colour, fog);
	ALPHA = mix(mix(0.64, 0.87, depth), 0.97, max(foam, fog));
}
"""
	if detail == 0:
		# Keep waves, broad ripples, Fresnel, glints and foam. Remove only fine normals.
		var fine := """	slope += vec2(noise2(fine + vec2(0.12, 0)) - noise2(fine - vec2(0.12, 0)),
		noise2(fine + vec2(0, 0.12)) - noise2(fine - vec2(0, 0.12))) * 0.65;"""
		shader.code = shader.code.replace(fine, "")
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func set_quality(water: int, cloud: int) -> void:
	if water != _water_detail and _water_material_ref != null:
		_water_detail = water
		_water_material_ref.shader = _water_material(water).shader
	if cloud != _cloud_detail and _sky_material_ref != null:
		_cloud_detail = cloud
		var horizon: Vector3 = _sky_material_ref.get_shader_parameter("horizon")
		_sky_material_ref.shader = _sky_material(Color(horizon.x, horizon.y, horizon.z), cloud).shader
		_sky_material_ref.set_shader_parameter("horizon", horizon)


func _build_water() -> void:
	# Short coastline chords; insert every harbour edge so no collider triangle spans a quay.
	# Tiny clearance excludes shared triangle edges from rays exactly on the closed quay boundary.
	var cutouts: Array[Rect2] = []
	for rect: Rect2 in HARBOUR:
		cutouts.append(rect.grow(0.02))
	var rows: Array[float] = []
	for z in range(0, 6001, 10):
		rows.append(float(z))
	for rect in cutouts:
		for z: float in [rect.position.y, rect.end.y]:
			if not rows.has(z):
				rows.append(z)
	rows.sort()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rows.size() - 1):
		var z0 := rows[row]
		var z1 := rows[row + 1]
		var middle := (z0 + z1) * 0.5
		var spans: Array[Vector2] = [Vector2(0.0, MAP_SIZE)]
		for rect in cutouts:
			if middle < rect.position.y or middle > rect.end.y:
				continue
			var clipped: Array[Vector2] = []
			for span in spans:
				if rect.end.x <= span.x or rect.position.x >= span.y:
					clipped.append(span)
				else:
					if rect.position.x > span.x:
						clipped.append(Vector2(span.x, rect.position.x))
					if rect.end.x < span.y:
						clipped.append(Vector2(rect.end.x, span.y))
			spans = clipped
		for span in spans:
			var left0 := clampf(coast(z0), span.x, span.y)
			var left1 := clampf(coast(z1), span.x, span.y)
			var steps := ceili((span.y - minf(left0, left1)) / 65.0)
			for step in range(steps):
				var t0 := float(step) / steps
				var t1 := float(step + 1) / steps
				var a := Vector3(lerpf(left0, span.y, t0), 0, z0)
				var b := Vector3(lerpf(left0, span.y, t1), 0, z0)
				var c := Vector3(lerpf(left1, span.y, t1), 0, z1)
				var d := Vector3(lerpf(left1, span.y, t0), 0, z1)
				for vertex: Vector3 in [a, b, c, a, c, d]:
					surface.set_normal(Vector3.UP)
					surface.add_vertex(vertex)
	surface.index()
	var mesh := surface.commit()
	# Never pass this mesh through World.apply_lighting, even if a caller lights the whole level.
	mesh.set_meta("rw_lit", true)
	var water := MeshInstance3D.new()
	water.name = "SeaSurface"
	water.mesh = mesh
	_water_material_ref = _water_material(_water_detail)
	water.material_override = _water_material_ref
	water.extra_cull_margin = 1.0
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	var body := StaticBody3D.new()
	body.name = "SeaCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)


func sea_crash(pos: Vector3) -> void:
	if not is_sea(pos):
		return
	if _crashes.size() >= MAX_CRASHES:
		var oldest: Dictionary = _crashes.pop_front()
		oldest.root.queue_free()
	var effect := Node3D.new()
	effect.name = "SeaCrash"
	add_child(effect)
	effect.global_position = Vector3(pos.x, 0.2, pos.z)
	var spray := CPUParticles3D.new()
	spray.name = "Splash"
	spray.amount = 80
	spray.lifetime = 2.8
	spray.one_shot = true
	spray.explosiveness = 0.96
	spray.direction = Vector3.UP
	spray.spread = 62.0
	spray.initial_velocity_min = 12.0
	spray.initial_velocity_max = 29.0
	spray.gravity = Vector3(0, -20, 0)
	spray.scale_amount_min = 0.25
	spray.scale_amount_max = 0.85
	var droplet := SphereMesh.new()
	droplet.radius = 0.5
	droplet.height = 1.8
	droplet.radial_segments = 6
	droplet.rings = 3
	droplet.material = _effect_material(Color(0.78, 0.9, 0.95))
	spray.mesh = droplet
	var colours := Gradient.new()
	colours.colors = PackedColorArray([Color(0.9, 0.97, 1, 0.9), Color(0.7, 0.87, 0.95, 0)])
	spray.color_ramp = colours
	effect.add_child(spray)
	spray.emitting = true
	var ring_shader := Shader.new()
	ring_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float age = 0.0;
varying vec2 world_xz;
""" + SEA_DOMAIN + """
void vertex() { world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz; }
void fragment() {
	if (!sea(world_xz)) { discard; }
	float radius = length(UV - vec2(0.5)) * 2.0;
	float rings = pow(0.5 + 0.5 * cos(radius * 52.0 - age * 2.5), 14.0);
	ALBEDO = vec3(0.77, 0.91, 0.94);
	ALPHA = rings * smoothstep(0.15, 0.35, radius) * (1.0 - smoothstep(0.8, 1.0, radius))
		* max(1.0 - age / 10.0, 0.0) * 0.65;
}
"""
	var ring_material := ShaderMaterial.new()
	ring_material.shader = ring_shader
	var rings := MeshInstance3D.new()
	rings.name = "Ripples"
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 2.0
	rings.mesh = plane
	rings.material_override = ring_material
	rings.position.y = 0.3
	rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect.add_child(rings)
	# Recognisable torn wings, fuselage and tail. Visual fragments never enter gameplay collisions.
	var pieces: Array[Dictionary] = []
	var wreck := _aircraft_wreck(pos)
	if not wreck.is_empty():
		effect.add_child(wreck.node)
		pieces.append({"node": wreck.node, "material": wreck.material, "phase": 0.0,
			"drift": Vector3(0.12, 0, 0.08)})
	for i in range(6):
		var piece := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = [Vector3(7, 0.18, 2.5), Vector3(5, 0.22, 2), Vector3(1.8, 1, 5.5),
			Vector3(3, 0.15, 1.7), Vector3(0.2, 1.8, 1.7), Vector3(1, 0.5, 2)][i]
		piece.mesh = shape
		var material := _effect_material(Color(0.22 + i * 0.025, 0.27 + i * 0.02, 0.20))
		piece.material_override = material
		piece.rotation = Vector3(randf_range(-0.18, 0.18), randf() * TAU, randf_range(-0.12, 0.12))
		effect.add_child(piece)
		pieces.append({"node": piece, "material": material, "phase": randf() * TAU,
			"drift": Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))})
	_crashes.append({"root": effect, "age": 0.0, "rings": rings, "material": ring_material, "pieces": pieces})
	set_process(true)


func _effect_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.78
	return material


func _process(dt: float) -> void:
	for index in range(_crashes.size() - 1, -1, -1):
		var crash := _crashes[index]
		crash.age += dt
		var age: float = crash.age
		if age >= CRASH_LIFETIME:
			crash.root.queue_free()
			_crashes.remove_at(index)
			continue
		var radius := 4.0 + age * 4.0
		crash.rings.scale = Vector3(radius, 1, radius)
		crash.material.set_shader_parameter("age", age)
		crash.rings.visible = age < 10.0
		for piece: Dictionary in crash.pieces:
			var node: Node3D = piece.node
			var drift: Vector3 = piece.drift * dt
			if is_sea(node.global_position + drift):
				node.position += drift
			node.position.y = 0.15 + sin(age * 1.7 + piece.phase) * 0.16 - maxf(age - 12.0, 0.0) * 0.6
			node.rotation.z = sin(age * 1.3 + piece.phase) * 0.12
			var material: StandardMaterial3D = piece.material
			material.albedo_color.a = 1.0 - smoothstep(14.0, CRASH_LIFETIME, age)
	if _crashes.is_empty():
		set_process(false)


func create_aircraft() -> Aircraft:
	return load("res://mods/britain/aircraft.gd").new()


func configure_aircraft(plane: Aircraft, section: Dictionary) -> void:
	if plane.plane_name == "bf109":
		plane.set("escort_leader_id", int(Ini.num(section, "escortleader", 0)))


func _aircraft_wreck(pos: Vector3) -> Dictionary:
	var level := get_parent()
	var world := level.get_parent() as World if level else null
	if world == null:
		return {}
	for aircraft in world.planes:
		if aircraft.state != Aircraft.State.DEAD or aircraft.global_position.distance_to(pos) > 30.0:
			continue
		var path := "objects/planes/%s/wreck.gltf" % aircraft.plane_name
		if not ResourceLoader.exists(Ini.data_path(path)):
			continue
		var model := World.load_model(path)
		var material := _effect_material(Color(0.35, 0.33, 0.29))
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var source := mesh.mesh.surface_get_material(0)
			if source is BaseMaterial3D:
				material.albedo_texture = source.albedo_texture
			elif source is ShaderMaterial:
				material.albedo_texture = source.get_shader_parameter("tex")
			mesh.material_override = material
		model.basis = Basis(Vector3.UP, atan2(aircraft.flight_basis.z.x, aircraft.flight_basis.z.z))
		return {"node": model, "material": material}
	return {}
