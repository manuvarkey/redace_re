class_name World
extends Node3D
## Loads one original mission (missions/<n>/mission.ini) with its map, objects and aircraft,
## and runs ordnance, hits, AA guns, mission rules, camera, HUD and music.
##
## Mission rules (decomp/RedAce.c:37270 reads [mission] Group0..Group63 and timelimit):
##   every object has a "groups" bitmask; GroupN = -P means destroy P % of group N to win,
##   GroupN = +P means keep P % of group N alive. timelimit is in seconds.

const ALLIED_GROUP_BIT := 0x100
const PLAYER_GROUP_BIT := 0x2
const BULLET_LIFE := 1.6
const MAX_BULLETS := 4096
const AA_RANGE := 750.0
const MISSIONS := [-3, -2, -1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]
const SETTINGS_PATH := "user://settings.cfg"

signal finished(result: String, score: int)  # result: won, death, defence, time
signal pause_requested

var standalone := true  # false when started by the menus (Game); true for --mission debug runs
# cheat options (Menus/cheatoptions.html)
var cheat_boost := false
var cheat_infinite := false
var cheat_invulnerable := false
var enemy_endurance := 1.0
var strings := {}
var _edge_warned := false
var _was_captured := false

static var _scene_cache := {}

var mission_id := 1
var player: Aircraft
var planes: Array[Aircraft] = []
var targets: Array[Dictionary] = []  # ground objects: {node, health, radius, center, models, name, dead, groups, id, turret}
var objects_by_id := {}
var ordnance := {}  # ordinance.ini entries by index: 1 bullet, 2 bomb, 3 rocket, 4 aafire
var bullets: Array[Dictionary] = []
var shells: Array[Dictionary] = []  # bombs and rockets (model per projectile)
var rules: Array[Dictionary] = []  # {group, percent, total, lost}
var time_limit := 0.0
var mission_time := 0.0
var mission_over := false
var map_bounds := Rect2()

var camera: Camera3D
var hud_label: Label
var goal_label: Label
var brief_label: Label
var message_label: Label
var hud: Hud
var particles: Particles
var show_objectives := false  # Tab; the original HUD has no objective text
var music: AudioStreamPlayer
var brief_time := 10.0
var controls: Controls  # player bindings; Game passes its own, debug runs load the saved ones
var view_distance := 2600.0  # options "View Distance" (clip plane); fog end
var effects_detail := 0.7  # options "Effects Detail"
var camera_mode := 1  # original camera modes: 1 chase, 4 behind, 6 left, 7 right, 8 above
var _mouse_dx := 0.0
var _mouse_dy := 0.0
var autopilot := false
var forced_view := 0  # debug: --view=N holds a camera mode

var _bullets_mi: MeshInstance3D
var _bullets_mesh: ImmediateMesh
var _level: Node3D
var _blast_sound: AudioStream
# world sounds (decomp RedAce.c:42392): bullet into the ground, bomb blast, rocket blast
var _bullet_ground_sound: AudioStream
var _bomb_blast_sound: AudioStream
var _rocket_blast_sound: AudioStream
var _bullet_sound_time := 0.0
var _last_damage_source := ""


var _perf := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mission="):
			mission_id = int(a.get_slice("=", 1))
		elif a == "--autopilot":
			autopilot = true
		elif a.begins_with("--view="):
			forced_view = int(a.get_slice("=", 1))
		elif a == "--perf":
			_perf = true
			var t := Timer.new()
			t.wait_time = 3.0
			t.autostart = true
			t.timeout.connect(func() -> void: print(_perf_line()))
			add_child(t)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('mission')")
		if q != null and str(q).is_valid_int():
			mission_id = int(q)
	var cfg := Ini.load_file(Ini.data_path("redace.ini"))
	if controls == null:
		controls = Controls.load_saved()
	var ord := Ini.load_file(Ini.data_path("objects/ordinance/ordinance.ini"))
	for sec in ord:
		if sec.begins_with("ordinance"):
			ordnance[int(sec.substr(9))] = ord[sec]
	_blast_sound = load_sound("planecrash.wav")
	_bullet_ground_sound = load_sound("bulletground1.wav")
	_bomb_blast_sound = load_sound("explosionmedium2.wav")
	_rocket_blast_sound = load_sound("explosionsmall.wav")
	strings = Ini.load_file(Ini.data_path("language/english/strings.ini")).get("strings", {})
	_build_ui()
	if standalone:
		load_mission(mission_id)


# ---------------------------------------------------------------- asset helpers

## A ground object's model file; four objects name a model that lives in another object's folder
## (aagun2-4 -> aagunruin/aagunruin.dff, oildrum -> oilrig/oilrigburn.dff): look there too.
func _ground_model(dir: String, file: String) -> String:
	var rel := dir + file.get_basename() + ".gltf"
	if ResourceLoader.exists(Ini.data_path(rel)):
		return rel
	var name := file.get_basename().to_lower() + ".gltf"
	var root := Ini.data_path("objects/ground/")
	var d := DirAccess.open(root)
	if d:
		for sub in d.get_directories():
			if ResourceLoader.exists(root + sub + "/" + name):
				return "objects/ground/" + sub + "/" + name
	return rel


static func load_model(rel: String) -> Node3D:
	var path := Ini.data_path(rel)
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path) if ResourceLoader.exists(path) else null
		if _scene_cache[path] == null:
			push_warning("model missing: " + path)
	var ps: PackedScene = _scene_cache[path]
	return ps.instantiate() as Node3D if ps else null


static func load_sound(file_name: String) -> AudioStream:
	if file_name.is_empty():
		return null
	var base := Ini.data_path("sound/" + file_name.get_basename())
	for ext in [".wav", ".mp3"]:
		if ResourceLoader.exists(base + ext):
			return load(base + ext)
	return null


# ---------------------------------------------------------------- mission loading

func load_mission(id: int) -> void:
	mission_id = id
	if _level:
		_level.queue_free()
	planes.clear()
	targets.clear()
	objects_by_id.clear()
	bullets.clear()
	shells.clear()
	rules.clear()
	player = null
	mission_time = 0.0
	mission_over = false
	_fade_in = 0.0
	_dead_time = 0.0
	_end_time = -1.0
	_flashes.clear()
	if _fade:
		_fade.visible = false
		_end_label.visible = false
	_level = Node3D.new()
	_level.name = "Level"
	add_child(_level)
	_make_bullet_multimesh()
	particles = Particles.new()
	particles.detail = effects_detail
	_level.add_child(particles)

	var m := Ini.load_file(Ini.data_path("missions/%d/mission.ini" % id))
	if m.is_empty():
		message_label.text = "Mission %d not found" % id
		return
	var map_name: String = m.get("map", {}).get("map", "country")
	_load_map(map_name.to_lower())

	for sec_name in m.keys():
		if sec_name.begins_with("ground") or sec_name.begins_with("vehicle"):
			# [groundN] makes a plain ground object, [vehicleN] a vehicle with the turret AI (exe classes
			# at RedAce.c:37294 / 37355): the 94 placed "aagunruin" wrecks are scenery and never fire
			_spawn_ground(m[sec_name], sec_name.begins_with("vehicle"))
	for sec_name in m.keys():
		if sec_name.begins_with("air") and not sec_name.contains("goal"):
			_spawn_plane(sec_name, m)
	if player == null and not planes.is_empty():
		player = planes[0]
		player.is_player = true
	if player:
		player.autopilot = autopilot

	var ms: Dictionary = m.get("mission", {})
	time_limit = Ini.num(ms, "timelimit", 0.0)
	for k in ms:
		if k.begins_with("group"):
			rules.append({"group": int(k.substr(5)), "percent": float(ms[k]), "total": 0, "lost": 0})
	_count_rule_members()
	_build_grid()

	_setup_camera()
	_play_music(int(Ini.num(m.get("music", {}), "track", 3)))
	if standalone:
		_show_briefing(id)
	message_label.text = ""
	_edge_warned = false
	for p in planes:
		if not p.allied:
			p.endurance *= enemy_endurance
			p.health = p.endurance


## Bullets as the exe draws them (FUN_0044c4fe): a camera-facing ribbon of the ordinance raster
## (bullet.bmp + mask), from the round 20 units forward along its flight, half as wide as
## ordinance.ini size (0.3 guns, 0.5 AA fire), white at alpha 0xc4.
func _make_bullet_multimesh() -> void:
	_bullets_mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	var tp := Ini.data_path("objects/ordinance/bullet.png")
	if ResourceLoader.exists(tp):
		mat.albedo_texture = load(tp)
	_bullets_mi = MeshInstance3D.new()
	_bullets_mi.mesh = _bullets_mesh
	_bullets_mi.material_override = mat
	_bullets_mi.extra_cull_margin = 100000.0
	_bullets_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_level.add_child(_bullets_mi)


func _draw_bullets() -> void:
	_bullets_mesh.clear_surfaces()
	if bullets.is_empty() or camera == null:
		return
	var eye := camera.global_position
	var col := Color(1, 1, 1, 0xc4 / 255.0)
	_bullets_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in bullets:
		var p: Vector3 = b.pos
		var d: Vector3 = (b.vel as Vector3).normalized()
		var tip := p + d * BULLET_STREAK
		var side := (eye - p).cross(d)
		if side.length_squared() < 1e-8:
			continue
		side = side.normalized() * (0.5 if b.aa else 0.3)
		var q := [p + side, tip + side, tip - side, p - side]
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for k in [0, 1, 2, 0, 2, 3]:
			_bullets_mesh.surface_set_color(col)
			_bullets_mesh.surface_set_uv(uv[k])
			_bullets_mesh.surface_add_vertex(q[k])
	_bullets_mesh.surface_end()


func _load_map(map_name: String) -> void:
	var dir := "maps/%s/" % map_name
	var ini := Ini.load_file(Ini.data_path(dir + "map.ini"))
	var app: Dictionary = ini.get("appearance", {})
	var terrain := load_model(dir + str(app.get("bsp", "thelandscape2")) + ".gltf")
	if terrain:
		_level.add_child(terrain)
		var box := AABB()
		var first := true
		for mi in terrain.find_children("*", "MeshInstance3D", true, false):
			var vi := mi as MeshInstance3D
			vi.create_trimesh_collision()
			var b := vi.global_transform * vi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		map_bounds = Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	var map_png := Ini.data_path(dir + "map.png")
	hud.map_texture = Hud.with_mipmaps(load(map_png)) if ResourceLoader.exists(map_png) else null

	var fog_parts: PackedStringArray = str(app.get("fogcolour", "227 241 248 255")).split(" ", false)
	var fog := Color8(int(fog_parts[0]), int(fog_parts[1]), int(fog_parts[2]))
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = _make_sky_material(dir, fog)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.75)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = fog
	env.fog_depth_begin = view_distance * 0.27
	env.fog_depth_end = view_distance
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	_level.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.8
	_level.add_child(sun)


func _make_sky_material(dir: String, fog: Color) -> ShaderMaterial:
	# Five skybox faces seen from inside. Model space: +Z = front, +X = left (RenderWare axes).
	var sh := Shader.new()
	sh.code = """
shader_type sky;
uniform sampler2D sky_front : source_color, filter_linear, repeat_disable;
uniform sampler2D sky_back : source_color, filter_linear, repeat_disable;
uniform sampler2D sky_left : source_color, filter_linear, repeat_disable;
uniform sampler2D sky_right : source_color, filter_linear, repeat_disable;
uniform sampler2D sky_up : source_color, filter_linear, repeat_disable;
uniform vec3 fog_color : source_color;

vec2 face_uv(vec3 e, vec3 d, vec3 r, vec3 u) {
	float k = abs(dot(e, d));
	return vec2(0.5 + 0.5 * dot(e, r) / k, 0.5 - 0.5 * dot(e, u) / k);
}

void sky() {
	vec3 e = EYEDIR;
	vec3 a = abs(e);
	vec3 c;
	if (a.y >= a.x && a.y >= a.z) {
		c = e.y > 0.0 ? texture(sky_up, face_uv(e, vec3(0, 1, 0), vec3(-1, 0, 0), vec3(0, 0, -1))).rgb : fog_color;
	} else if (a.z >= a.x) {
		c = e.z > 0.0 ? texture(sky_front, face_uv(e, vec3(0, 0, 1), vec3(-1, 0, 0), vec3(0, 1, 0))).rgb
					  : texture(sky_back, face_uv(e, vec3(0, 0, -1), vec3(1, 0, 0), vec3(0, 1, 0))).rgb;
	} else {
		c = e.x > 0.0 ? texture(sky_left, face_uv(e, vec3(1, 0, 0), vec3(0, 0, 1), vec3(0, 1, 0))).rgb
					  : texture(sky_right, face_uv(e, vec3(-1, 0, 0), vec3(0, 0, -1), vec3(0, 1, 0))).rgb;
	}
	COLOR = mix(c, fog_color, clamp(-e.y * 4.0, 0.0, 1.0));
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	for f in ["front", "back", "left", "right", "up"]:
		var p := Ini.data_path(dir + "sky_%s.png" % f)
		if ResourceLoader.exists(p):
			mat.set_shader_parameter("sky_" + f, load(p))
	mat.set_shader_parameter("fog_color", fog)
	return mat


func _basis_from(sec: Dictionary) -> Basis:
	var up := Ini.vec3(sec, "up", Vector3.UP)
	var at := Ini.vec3(sec, "at")
	if at.length_squared() < 0.01 or up.length_squared() < 0.01:
		return Basis.IDENTITY
	at = at.normalized()
	up = up.normalized()
	var x := up.cross(at).normalized()
	return Basis(x, at.cross(x).normalized(), at)


func _spawn_ground(sec: Dictionary, vehicle := true) -> void:
	var obj: String = str(sec.get("name", "")).to_lower()
	if obj.is_empty():
		return
	var dir := "objects/ground/%s/" % obj
	var ini := Ini.load_file(Ini.data_path(dir + "ground.ini"))
	var app: Dictionary = ini.get("appearance", {})
	if app.is_empty():
		return
	# damage models (exe loader at 0x42b412): deaddff = the wreck as stage 1 of 2; damagedff1.. append stages
	var models: Array[String] = [_ground_model(dir, str(app.get("dff", obj)))]
	if app.has("deaddff"):
		models.append(_ground_model(dir, str(app["deaddff"])))
	for i in range(1, 6):
		if app.has("damagedff%d" % i):
			if models.size() > i:
				models[i] = _ground_model(dir, str(app["damagedff%d" % i]))
			else:
				models.append(_ground_model(dir, str(app["damagedff%d" % i])))
	var root := Node3D.new()
	root.name = obj
	var model := load_model(models[0])
	if model == null:
		return
	root.add_child(model)
	_level.add_child(root)
	root.global_transform = Transform3D(_basis_from(sec), Ini.vec3(sec, "pos"))
	var aabb := _aabb_of(model)
	var groups := int(Ini.num(sec, "groups", 0))
	var arm: Dictionary = ini.get("armaments", {})
	var t := {"node": root, "health": Ini.num(ini.get("physics", {}), "endurance", 50.0),
		"radius": maxf(aabb.size.length() * 0.45, 2.0), "center": aabb.get_center(), "models": models,
		"name": obj, "dead": false, "groups": groups, "id": int(Ini.num(sec, "id", 0)), "model_index": 0,
		"endurance": maxf(Ini.num(ini.get("physics", {}), "endurance", 50.0), 1.0), "hit_time": 0.0,
		"allied": (groups & ALLIED_GROUP_BIT) != 0,
		"turret": vehicle and str(ini.get("ai", {}).get("turret", "")) == "antiaircraft",
		"fire_rate": Ini.num(arm, "firerate", 10.0), "fire_on": Ini.num(arm, "fireon", 3.0),
		"fire_off": Ini.num(arm, "fireoff", 1.0), "fire_time": randf() * 3.0, "shots": 0.0,
		# exe defaults when [sound] leaves them out (RedAce.c:29418)
		"hit_sound": load_sound(str(ini.get("sound", {}).get("hitsound", "bulletbuilding1.wav"))),
		"explosion_sound": load_sound(str(ini.get("sound", {}).get("explosion", "explosionsmall.wav"))),
		"break_sound": load_sound(str(ini.get("sound", {}).get("breakage", "explosionsmall.wav"))),
		# collision (FUN_00430199): the model's box; [physics] soft = 1 (trees, scrub) wears planes down
		"aabb": aabb, "soft": int(Ini.num(ini.get("physics", {}), "soft", 0)) == 1}
	targets.append(t)
	objects_by_id[t.id] = t


func _aabb_of(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var vi := mi as MeshInstance3D
		var b := n.global_transform.affine_inverse() * vi.global_transform * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _spawn_plane(sec_name: String, m: Dictionary) -> void:
	var sec: Dictionary = m[sec_name]
	var p := Aircraft.new()
	p.setup(str(sec.get("name", "sopwithcamel")), self)
	p.object_id = int(Ini.num(sec, "id", 0))
	p.groups = int(Ini.num(sec, "groups", 0))
	p.is_player = int(Ini.num(sec, "player", 0)) == 1
	p.allied = (p.groups & (ALLIED_GROUP_BIT | PLAYER_GROUP_BIT)) != 0 or p.is_player
	var otype := int(Ini.num(sec, "ordinancetype", 0))
	var count := int(Ini.num(sec, "numordinance", 0))
	if otype in [1, 2] and count > 0 and count < 1000:
		p.ordnance_type = otype
		p.ordnance_left = count
	var k := 0
	while m.has("%sgoal%d" % [sec_name, k]):
		var g: Dictionary = m["%sgoal%d" % [sec_name, k]]
		# the original builds goals by exact type and drops anything else (decomp RedAce.c:34449)
		var gtype := int(Ini.num(g, "type", 0))
		if gtype in Aircraft.GOAL_TYPES:
			p.goals.append({"type": gtype, "targetid": int(Ini.num(g, "targetid", 0)),
				"pos": Ini.vec3(g, "pos"), "radius": Ini.num(g, "real", 50.0)})
		k += 1
	# a mission entry may override the plane's endurance and top speed (decomp RedAce.c:37560)
	if sec.has("endurance"):
		p.endurance = Ini.num(sec, "endurance", p.endurance)
		p.health = p.endurance
	if sec.has("highspeed"):
		p.high_speed = Ini.num(sec, "highspeed", p.high_speed)
	_level.add_child(p)
	p.place(Transform3D(_basis_from(sec), Ini.vec3(sec, "pos")))
	p.destroyed.connect(_on_plane_destroyed)
	planes.append(p)
	objects_by_id[p.object_id] = p
	if p.is_player:
		player = p


# ---------------------------------------------------------------- world queries

func ground_height(pos: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(pos.x, 5000.0, pos.z), Vector3(pos.x, -5000.0, pos.z))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else -1000.0


func ground_normal(pos: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(Vector3(pos.x, 5000.0, pos.z), Vector3(pos.x, -5000.0, pos.z))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return (hit.normal as Vector3).normalized() if hit and hit.normal.y > 0.0 else Vector3.UP


## Fraction along from..to where the segment first meets the terrain or an object, 0 when clear.
func ground_hit_fraction(from: Vector3, to: Vector3) -> float:
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	return from.distance_to(hit.position) / maxf(from.distance_to(to), 0.001) if hit else 0.0


func height_above_ground(pos: Vector3) -> float:
	return pos.y - ground_height(pos)


func object_by_id(id: int) -> Variant:
	return objects_by_id.get(id) if id > 0 else null


func _perf_line() -> String:
	var line := "t=%.0f fps=%d physics=%.1fms process=%.1fms bullets=%d shells=%d" % [
		mission_time, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, bullets.size(), shells.size()]
	if player:
		var o := nearest_objective(player.global_position)
		var od: float = o.node.global_position.distance_to(player.global_position) if not o.is_empty() else -1.0
		line += " | player state=%d alt=%.0f hp=%.0f ord=%d goal=%d/%d obj_dist=%.0f enemies=%d" % [
			player.state, height_above_ground(player.global_position), player.health, player.ordnance_left,
			player.goal_index, player.goals.size(), od, _enemies_left()]
	return line


const BOMB_GRAVITY := 9.81 * 4.0


## Where a bomb released now would hit the ground (same integration as _update_shells, 0.05 s steps).
func bomb_impact(pos: Vector3, vel: Vector3) -> Vector3:
	var maxspeed := Ini.num(ordnance.get(2, {}), "maxspeed", 200.0)
	for i in 400:
		vel += Vector3.DOWN * BOMB_GRAVITY * 0.05
		if vel.length() > maxspeed:
			vel = vel.normalized() * maxspeed
		pos += vel * 0.05
		if pos.y <= ground_height(pos):
			return pos
	return pos


func in_bounds(pos: Vector3, margin: float) -> bool:
	return map_bounds.grow(-margin).has_point(Vector2(pos.x, pos.z))


func map_center(height: float) -> Vector3:
	var c := map_bounds.get_center()
	return Vector3(c.x, maxf(height, ground_height(Vector3(c.x, 0, c.y)) + 200.0), c.y)


## Ground object for an attack goal: a specific id, or the nearest live member of group -id
## (group n = bit n of the groups field; decomp FUN_0044a881).
func ground_for_goal(id: int, from: Vector3) -> Dictionary:
	if id > 0:
		var o = objects_by_id.get(id)
		return o if o is Dictionary and not o.dead else {}
	var best := {}
	var best_d := INF
	for t in targets:
		if not t.dead and (int(t.groups) & (1 << -id)):
			var d: float = t.node.global_position.distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = t
	return best


func aircraft_for_goal(id: int, me: Aircraft) -> Aircraft:
	if id > 0:
		var o = objects_by_id.get(id)
		return o if o is Aircraft and o.present() and o.allied != me.allied else null
	var best: Aircraft = null
	var best_d := INF
	for p in planes:
		if p.present() and p.allied != me.allied and (p.groups & (1 << -id)):
			var d := p.global_position.distance_squared_to(me.global_position)
			if d < best_d:
				best_d = d
				best = p
	return best


## Object a script goal refers to (decomp FUN_0044a881): id > 0 that object if it is in the world,
## else the member of group -id nearest to me (aircraft or ground object, either side).
func object_for_goal(id: int, me: Aircraft) -> Variant:
	if id > 0:
		var o = objects_by_id.get(id)
		if o is Aircraft:
			return o if o.present() else null
		return o if o is Dictionary and not o.dead else null
	var best = null
	var best_d := INF
	var bit := 1 << -id
	for p in planes:
		if p.present() and (p.groups & bit):
			var d := p.global_position.distance_squared_to(me.global_position)
			if d > 0.1 and d < best_d:
				best_d = d
				best = p
	for t in targets:
		if not t.dead and (int(t.groups) & bit):
			var d: float = t.node.global_position.distance_squared_to(me.global_position)
			if d > 0.1 and d < best_d:
				best_d = d
				best = t
	return best


func nearest_objective(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for t in targets:
		if t.dead or not _is_objective(t):
			continue
		var d: float = t.node.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = t
	return best


func nearest_enemy(me: Aircraft) -> Aircraft:
	var best: Aircraft = null
	var best_d := INF
	for p in planes:
		if p == me or p.allied == me.allied or not p.present():
			continue
		var d := p.global_position.distance_squared_to(me.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


# ---------------------------------------------------------------- ordnance and effects

## kind = ordinance.ini index: 1 bullet, 2 bomb, 3 rocket, 4 aafire.
func spawn_ordnance(owner_obj, kind: int, pos: Vector3, base_vel: Vector3, dir := Vector3.ZERO) -> void:
	var o: Dictionary = ordnance.get(kind, {})
	var jitter := Ini.num(o, "jitter", 0.0)
	var allied: bool = owner_obj.allied
	if kind == 1 or kind == 4:
		if bullets.size() >= MAX_BULLETS:
			return
		var d := (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * jitter).normalized()
		var vel := base_vel + d * Ini.num(o, "releasespeed", 250.0)
		bullets.append({"pos": pos, "vel": vel, "owner": owner_obj, "allied": allied, "life": BULLET_LIFE,
			"damage": Ini.num(o, "damage", 1.0), "aa": kind == 4, "ground": _ground_filter(owner_obj)})
		return
	var node := load_model("objects/ordinance/%s.gltf" % str(o.get("clump", "bomb")).to_lower())
	if node == null:
		node = Node3D.new()
	_level.add_child(node)
	node.global_position = pos
	shells.append({"node": node, "pos": pos, "vel": base_vel + base_vel.normalized() * Ini.num(o, "releasespeed", 0.0),
		"owner": owner_obj, "allied": allied, "life": 20.0, "kind": kind, "ground": _ground_filter(owner_obj),
		"accel": Ini.num(o, "accel", 0.0), "maxspeed": Ini.num(o, "maxspeed", 200.0),
		"damage": Ini.num(o, "damage", 50.0), "blast": Ini.num(o, "blast", 20.0)})


## Explosion as the original draws it: a burst of fiery particles (FUN_004511f8) and a sound.
func spawn_explosion(pos: Vector3, size := 12.0, sound: AudioStream = null) -> void:
	particles.burst(pos, size / 8.0)
	play_at(pos, sound if sound else _blast_sound)


## Hit flash (decomp FUN_0042c2b6 / FUN_0044a1bc): an object hit within the last 0.25 s is drawn
## through a red fog at half strength (fog table 0x80, fog colour 0xffff0000).
var _flashes := {}  # Node3D -> seconds left
var _flash_mat: StandardMaterial3D


func flash(node: Node3D, seconds := 0.25) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.albedo_color = Color(1, 0, 0, 0.5)
	if not _flashes.has(node):
		_set_overlay(node, _flash_mat)
	_flashes[node] = seconds


func _set_overlay(node: Node3D, mat: Material) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = mat


func _update_flashes(dt: float) -> void:
	for node in _flashes.keys():
		if not is_instance_valid(node):
			_flashes.erase(node)
			continue
		_flashes[node] -= dt
		if _flashes[node] <= 0.0:
			_set_overlay(node, null)
			_flashes.erase(node)


func play_at(pos: Vector3, stream: AudioStream, volume_db := 0.0) -> void:
	if stream == null or _level == null:
		return
	var a := AudioStreamPlayer3D.new()
	a.stream = stream
	a.volume_db = volume_db
	a.unit_size = 60.0
	a.bus = "Effects"
	_level.add_child(a)
	a.global_position = pos
	a.finished.connect(a.queue_free)
	a.play()


func _physics_process(dt: float) -> void:
	if _level == null:
		return
	if player and player.state != Aircraft.State.DEAD and not autopilot:
		_player_input(dt)
	if not mission_over:
		mission_time += dt
	_update_turrets(dt)
	var space := get_world_3d().direct_space_state
	var i := bullets.size() - 1
	while i >= 0:
		var b: Dictionary = bullets[i]
		var from: Vector3 = b.pos
		var to: Vector3 = from + b.vel * dt
		b.life -= dt
		if b.life <= 0.0 or _bullet_hits(b, from, to, space):
			bullets[i] = bullets[bullets.size() - 1]
			bullets.pop_back()
		else:
			b.pos = to
		i -= 1
	_draw_bullets()
	_update_shells(dt, space)
	_check_rules()


func _update_shells(dt: float, space: PhysicsDirectSpaceState3D) -> void:
	var i := shells.size() - 1
	while i >= 0:
		var s: Dictionary = shells[i]
		var vel: Vector3 = s.vel
		if s.kind == 3:  # rocket: accelerates along its flight path
			vel += vel.normalized() * s.accel * dt
		else:  # bomb: falls (ordinance.ini accel -1 = gravity)
			vel += Vector3.DOWN * BOMB_GRAVITY * dt
		if vel.length() > s.maxspeed:
			vel = vel.normalized() * s.maxspeed
		var from: Vector3 = s.pos
		var to := from + vel * dt
		s.vel = vel
		s.life -= dt
		# smoke trail (RedAce.c:43373): 20 puffs/s for bombs, 30 for rockets; grey 0.9 at alpha 0.7
		# fading 0.3/s, size 0.75 (rockets) or 0.1 (bombs) growing 2/s, drifting up 15/s
		s.smoke = s.get("smoke", 0.0) + dt * (30.0 if s.kind == 3 else 20.0)
		while s.smoke >= 1.0:
			s.smoke -= 1.0
			particles.puff("smoke", from, Vector3(randf_range(-5.0, 0.0), 15.0, randf_range(-5.0, 0.0)),
				0.75 if s.kind == 3 else 0.1, Color(0.9, 0.9, 0.9, 0.7), Color(-0.1, -0.1, -0.1, -0.3), 2.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
		var direct := _hit_target_on_segment(s, from, to)
		if not hit.is_empty() or direct or s.life <= 0.0:
			var at: Vector3 = hit.position if not hit.is_empty() else to
			# ordinance 2 = bomb: ExplosionMedium2, 3 = rocket: ExplosionSmall (RedAce.c:43351)
			_blast(at, s.blast, s.damage, s.owner, s.allied, s.ground,
				_bomb_blast_sound if int(s.kind) == 2 else _rocket_blast_sound)
			s.node.queue_free()
			shells.remove_at(i)
		else:
			s.pos = to
			s.node.global_transform = Transform3D(_look(vel), to)
		i -= 1


## Which ground objects a projectile may damage: the player's hit everything (true), an AI plane's
## only its assigned ground target, AA fire none. Keeps stray AI fire off protected civilian groups.
func _ground_filter(owner_obj) -> Variant:
	if owner_obj is Aircraft:
		return true if owner_obj.is_player else owner_obj.ground_target
	return false


func _may_damage(filter, t: Dictionary) -> bool:
	if filter is bool:
		return filter
	return is_same(filter, t)


func _hit_target_on_segment(s: Dictionary, from: Vector3, to: Vector3) -> bool:
	for p in planes:
		if not is_same(p, s.owner) and p.present() and _seg_dist(p.global_position, from, to) < p.radius:
			return true
	for t in _targets_near(to):
		if not t.dead and _seg_dist(t.node.global_transform * t.center, from, to) < t.radius:
			return true
	return false


## Blast damage as the original (decomp FUN_0044cf81): (blast radius - distance) * damage,
## times 0.05 for the thrower's own side. Debris burst sized blast * 0.03 (FUN_0044ced8).
func _blast(at: Vector3, radius: float, damage: float, owner_obj, allied: bool, ground_filter,
		sound: AudioStream = null) -> void:
	particles.burst(at, radius * 0.03)
	for i in 12:
		particles.puff("clod", at, Vector3(randf_range(-25, 25), randf_range(20, 50), randf_range(-25, 25)),
			1.5, Color(0.45, 0.38, 0.3, 1.0), Color(0, 0, 0, -0.6), 0.0, -40.0)
	play_at(at, sound if sound else _blast_sound)
	for t in targets:
		if t.dead or not _may_damage(ground_filter, t):
			continue
		_last_damage_source = "blast from " + (owner_obj.plane_name if owner_obj is Aircraft else "?")
		var d: float = maxf((t.node.global_transform * t.center).distance_to(at) - t.radius, 0.0)
		if d < radius:
			_damage_target(t, (radius - d) * damage * (0.05 if t.allied == allied and t.groups != 0 else 1.0))
	for p in planes:
		if is_same(p, owner_obj) or not p.present():
			continue
		var d := maxf(p.global_position.distance_to(at) - p.radius, 0.0)
		if d < radius:
			p.take_damage((radius - d) * damage * (0.05 if p.allied == allied else 1.0), owner_obj)


func _bullet_hits(b: Dictionary, from: Vector3, to: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	for p in planes:
		if is_same(p, b.owner) or not p.present() or p.allied == b.allied:
			continue
		if _seg_dist(p.global_position, from, to) < p.radius:
			# guns reach aircraft by proximity (FUN_0044d311): only the plane's own hit effects
			# (cloth scrap, knock sound, red flash in FUN_0042eda0), no impact puff
			p.take_damage(b.damage, b.owner)
			return true
	if not b.aa:
		for t in _targets_near(to):
			if t.dead or not _may_damage(b.ground, t):
				continue
			_last_damage_source = "bullet from " + (b.owner.plane_name if b.owner is Aircraft else "gun")
			var c: Vector3 = t.node.global_transform * t.center
			if _seg_dist(c, from, to) < t.radius:
				_damage_target(t, b.damage)
				particles.puff("hit", to - b.vel * 0.02, Vector3.ZERO, 4.0, Color(1, 1, 1, 0.5), Color(0, 0, 0, -1.0), 4.0)
				return true
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return false
	# bullet in the ground: maroon dust puff 8 above the impact (FUN_0044cd2a)
	particles.puff("maroon", hit.position + Vector3.UP * 8.0, Vector3(0, 4, 0), 4.0, Color(1, 1, 1, 0.5),
		Color(0, 0, 0, -0.8), 6.0)
	# BulletGround1 (the exe gives it 4 voices); here at most 8 per second
	if mission_time - _bullet_sound_time > 0.125:
		_bullet_sound_time = mission_time
		play_at(hit.position, _bullet_ground_sound)
	return true


## Basis whose +Z (RenderWare forward) points along dir; safe for vertical directions.
func _look(dir: Vector3) -> Basis:
	var d := dir.normalized()
	if d.is_zero_approx():
		return Basis.IDENTITY
	var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.FORWARD
	return Basis.looking_at(-d, up)


const BULLET_STREAK := 20.0  # exe: dt * 150, at least 20
const GRID := 100.0
var _grid := {}


func _grid_key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / GRID), floori(z / GRID))


func _build_grid() -> void:
	_grid.clear()
	for t in targets:
		var c: Vector3 = t.node.global_transform * t.center
		var k := _grid_key(c.x, c.z)
		if not _grid.has(k):
			_grid[k] = []
		_grid[k].append(t)


## Ground objects whose cell is within one cell of pos (object radii stay below the cell size).
func _targets_near(pos: Vector3) -> Array:
	var k := _grid_key(pos.x, pos.z)
	var out := []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var cell = _grid.get(k + Vector2i(dx, dz))
			if cell:
				out.append_array(cell)
	return out


## Slab test: does segment a..b meet the box lo..hi?
static func segment_hits_box(a: Vector3, b: Vector3, lo: Vector3, hi: Vector3) -> bool:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for i in 3:
		if absf(d[i]) < 1e-6:
			if a[i] < lo[i] or a[i] > hi[i]:
				return false
			continue
		var ta := (lo[i] - a[i]) / d[i]
		var tb := (hi[i] - a[i]) / d[i]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true


## Plane against other planes and ground objects, as the exe does it (FUN_00431607 probes, callback
## FUN_00430199 for each object whose geometry a probe meets, other than the plane itself):
##   the object takes 2 * dt * plane endurance * (0.2 for aircraft, 15 for ground objects);
##   the plane takes endurance + 1 (destroyed) from anything solid, or 2 * dt * object endurance * k
##   from soft objects ([physics] soft = 1). Aircraft are never soft (mission flags 0x400 / 0x600).
func collide(p: Aircraft, prev: Vector3, dt: float) -> void:
	if p.hidden:
		return
	var segs := p.probe_segments(prev)
	var reach := p.global_position.distance_to(prev) + maxf(p.radius, p.front_length) + 20.0
	for q in planes:
		if q == p or not q.present() or q.global_position.distance_to(p.global_position) > reach + q.radius:
			continue
		for sg in segs:
			if q.box_hit(sg[0], sg[1]):
				q.take_damage(2.0 * dt * p.endurance * 0.2, p)
				p.take_damage(p.endurance + 1.0, p)
				if _perf:
					print("collision %s %d with %s %d" % [p.plane_name, p.object_id, q.plane_name, q.object_id])
				return
	for t in _targets_near(p.global_position):
		if t.dead:
			continue
		var node: Node3D = t.node
		if node.global_position.distance_to(p.global_position) > reach + float(t.radius) * 2.0:
			continue
		var inv := node.global_transform.affine_inverse()
		var box: AABB = t.aabb
		for sg in segs:
			var a: Vector3 = inv * sg[0]
			var b: Vector3 = inv * sg[1]
			if segment_hits_box(a, b, box.position, box.end) and _segment_hits_faces(t, a, b):
				_last_damage_source = "collision with " + p.plane_name
				_damage_target(t, 2.0 * dt * p.endurance * 15.0)
				if t.soft:
					p.take_damage(2.0 * dt * float(t.endurance) * 15.0, t)
				else:
					p.take_damage(p.endurance + 1.0, p)
				if _perf and not t.soft:
					print("collision %s %d with %s" % [p.plane_name, p.object_id, t.name])
				return


## The exe tests the probe against the object's geometry, not its box (FUN_00430295): triangles of the
## object's current model in its local space, cached per damage model.
func _segment_hits_faces(t: Dictionary, a: Vector3, b: Vector3) -> bool:
	if t.get("faces_model", -1) != t.model_index:
		var faces := PackedVector3Array()
		var node: Node3D = t.node
		var inv := node.global_transform.affine_inverse()
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			if (mi as Node).is_queued_for_deletion() or (mi as MeshInstance3D).mesh == null:
				continue
			var xf: Transform3D = inv * (mi as MeshInstance3D).global_transform
			for v in (mi as MeshInstance3D).mesh.get_faces():
				faces.append(xf * v)
		t.faces = faces
		t.faces_model = t.model_index
	var f: PackedVector3Array = t.faces
	for i in range(0, f.size() - 2, 3):
		if Geometry3D.segment_intersects_triangle(a, b, f[i], f[i + 1], f[i + 2]) != null:
			return true
	return false


func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Ground object damage (decomp FUN_0042c00e): damage accumulates; the shown model steps through
## the damagedff models by damage fraction; each hit plays the hit sound at 0.75 volume; destruction
## makes a debris burst (endurance * 0.03), a smoke column and the breakage sound.
func _damage_target(t: Dictionary, amount: float) -> void:
	t.health -= amount
	var models: Array = t.models
	# stage = trunc(damage / endurance * (stages - 1)) (FUN_0042c00e): the last model only when destroyed
	var frac := clampf(1.0 - t.health / t.endurance, 0.0, 1.0)
	var idx := mini(int(frac * (models.size() - 1)), models.size() - 1)
	if t.health <= 0.0:
		idx = models.size() - 1
	if idx != t.model_index:
		# next damage model, with the breakage sound (FUN_0042c323)
		t.model_index = idx
		var node: Node3D = t.node
		var m := load_model(models[idx])
		if m:
			_flashes.erase(node)
			for c in node.get_children():
				c.queue_free()
			node.add_child(m)
		play_at(node.global_position, t.break_sound)
	# mission targets (group 7) flash red when hit (RedAce.c:29655)
	if int(t.groups) & (1 << 7):
		flash(t.node)
	if t.health > 0.0:
		# hitsound at 0.75 volume (RedAce.c:29644)
		if t.hit_sound and mission_time - t.hit_time > 0.15:
			t.hit_time = mission_time
			play_at(t.node.global_position, t.hit_sound, linear_to_db(0.75))
		return
	t.dead = true
	_log_loss(t.name, t.groups, _last_damage_source)
	# destroyed: smoke column, burst sized endurance * 0.03, explosion sound (RedAce.c:29647)
	var at: Vector3 = t.node.global_transform * t.center
	particles.smoke_column(at, 1.0)
	particles.burst(at, t.endurance * 0.03)
	play_at(at, t.explosion_sound if t.explosion_sound else _blast_sound)
	if _is_objective(t):
		print("objective destroyed: %s at %.1f s" % [t.name, mission_time])
	_count_rule_members()


func _update_turrets(dt: float) -> void:
	for t in targets:
		if not t.turret or t.dead:
			continue
		var pos: Vector3 = t.node.global_transform * t.center + Vector3.UP * 2.0
		var best: Aircraft = null
		var best_d := AA_RANGE
		for p in planes:
			if not p.present() or p.allied == t.allied:
				continue
			var d := p.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = p
		if best == null:
			t.fire_time = 0.0
			continue
		var cycle: float = t.fire_on + t.fire_off
		var phase := fmod(t.fire_time, cycle)
		t.fire_time += dt
		if phase >= t.fire_on:
			continue
		t.shots += dt * t.fire_rate
		var shell_speed := Ini.num(ordnance.get(4, {}), "releasespeed", 200.0)
		var lead := best.global_position + best.velocity * (best_d / shell_speed)
		while t.shots >= 1.0:
			t.shots -= 1.0
			spawn_ordnance(t, 4, pos, Vector3.ZERO, (lead - pos).normalized())


# ---------------------------------------------------------------- mission rules

func _log_loss(what: String, groups: int, cause: String) -> void:
	for r in rules:
		if r.percent > 0.0 and groups & (1 << int(r.group)):
			print("protected %s lost at %.1f s (%s)" % [what, mission_time, cause])


func _count_rule_members() -> void:
	for r in rules:
		var bit := 1 << int(r.group)
		var total := 0
		var lost := 0
		for p in planes:
			if p.groups & bit:
				total += 1
				lost += int(p.state == Aircraft.State.DEAD)
		for t in targets:
			if t.groups & bit:
				total += 1
				lost += int(t.dead)
		r.total = total
		r.lost = lost


func _check_rules() -> void:
	if mission_over or player == null:
		return
	# plane destroyed once the player's plane is down (a shot-down plane first spins to the ground)
	if player.state == Aircraft.State.DEAD:
		_dead_time += get_physics_process_delta_time()
		if not player.falling or _dead_time > 15.0:
			_end_mission(false, "death")
		return
	if time_limit > 0.0 and mission_time > time_limit:
		_end_mission(false, "time")
		return
	var won := true
	var has_goal := false
	for r in rules:
		if r.total == 0:
			continue
		var pct_lost: float = 100.0 * r.lost / r.total
		if r.percent < 0.0:
			has_goal = true
			won = won and pct_lost >= -r.percent - 0.01
		elif pct_lost > 100.0 - r.percent + 0.01:
			_end_mission(false, "defence")
			return
	if not has_goal:
		won = _enemies_left() == 0
	if won:
		_end_mission(true, "won")


## Mission score as the original (decomp FUN_00446aa1): 500 for a win, plus for each rule group
## 100 - % surviving (destroy groups) or % surviving (protect groups).
func mission_score(won: bool) -> int:
	var score := 500 if won else 0
	for r in rules:
		if r.total == 0 or r.group > 9:
			continue
		var alive: float = 100.0 * (r.total - r.lost) / r.total
		score += int(alive if r.percent > 0.0 else 100.0 - alive)
	return score


func _end_mission(won: bool, result: String) -> void:
	mission_over = true
	var text: String = strings.get("missionaccomplished", "Mission Accomplished") if won else \
		strings.get("missionfailed", "Mission Failed") + "\n" + strings.get(
			{"death": "planedestroyed", "defence": "missioncritical", "time": "outoftime"}.get(result, ""), "")
	print("mission %d end after %.1f s: %s" % [mission_id, mission_time, text.replace("\n", " - ")])
	if standalone:
		message_label.text = text + "\n" + ("Press N for the next mission" if won else "Press R to retry")
		return
	_start_end_fade(result, mission_score(won))


## Pause page "Abort Mission": the same fade with "Mission Aborted", then the defeat page (end code 0x30).
func abort_mission() -> void:
	if mission_over:
		return
	mission_over = true
	print("mission %d aborted after %.1f s" % [mission_id, mission_time])
	_start_end_fade("abort", 0)


## End of a flight as the exe plays it (RedAce.c:51041, overlay FUN_0045db9e): the world keeps running
## for 2.5 s while the screen fades to black (alpha = ms / 10), music and effects fade out and one line
## is shown 20 px above the centre: missionaccomplished, planedestroyed, missioncritical, outoftime or
## missionaborted. A key press skips the rest.
const END_FADE := 2.5
var _fade_in := 1.0
var _dead_time := 0.0
var _end_time := -1.0
var _end_result := ""
var _end_score := 0
var _fade: ColorRect
var _end_label: Label


func _start_end_fade(result: String, score: int) -> void:
	_end_result = result
	_end_score = score
	_end_time = 0.0
	message_label.text = ""
	var key: String = {"won": "missionaccomplished", "death": "planedestroyed", "defence": "missioncritical",
		"time": "outoftime", "abort": "missionaborted"}.get(result, "missionfailed")
	var fallback: String = {"missionaccomplished": "Mission Accomplished", "planedestroyed": "Plane Destroyed",
		"missioncritical": "Mission Critical Object Destroyed", "outoftime": "Out of Time",
		"missionaborted": "Mission Aborted", "missionfailed": "Mission Failed"}[key]
	_end_label.text = strings.get(key, fallback)
	_fade.visible = true
	_fade.color = Color(0, 0, 0, 0)
	_end_label.visible = true


func _update_end_fade(dt: float) -> void:
	if _end_time < 0.0:
		return
	_end_time += dt
	var t := minf(_end_time / END_FADE, 1.0)
	_fade.color = Color(0, 0, 0, minf(_end_time * 100.0, 255.0) / 255.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(1.0 - t, 0.0001)))
	var h := get_viewport().get_visible_rect().size.y
	_end_label.add_theme_font_size_override("font_size", int(28.0 * h / 480.0))
	_end_label.position.y = h * 0.5 - 20.0 * h / 480.0
	if _end_time >= END_FADE:
		_end_time = -1.0
		finished.emit(_end_result, _end_score)


func _exit_tree() -> void:
	AudioServer.set_bus_volume_db(0, 0.0)


func _objective_text() -> String:
	var lines: PackedStringArray = []
	for r in rules:
		if r.total == 0:
			continue
		var what := "enemy aircraft" if r.group == 9 else ("allied aircraft" if r.group == 8 else "targets")
		if r.percent < 0.0:
			lines.append("Destroy %d%% of %s: %d / %d" % [int(-r.percent), what, r.lost, r.total])
		else:
			lines.append("Protect %s: %d / %d lost" % [what, r.lost, r.total])
	if time_limit > 0.0:
		lines.append("Time left: %d s" % maxi(int(time_limit - mission_time), 0))
	return "\n".join(lines)


func _is_objective(t: Dictionary) -> bool:
	for r in rules:
		if r.percent < 0.0 and (int(t.groups) & (1 << int(r.group))):
			return true
	return false


func _on_plane_destroyed(p: Aircraft) -> void:
	if _perf:
		print("loss %s %d (%s) at %.1f s goal=0x%x" % [p.plane_name, p.object_id, "crashed" if p.crashed else "shot down",
			mission_time, int(p.current_goal().get("type", 0))])
	_log_loss(p.plane_name, p.groups, "crashed" if p.crashed else "shot down")
	_count_rule_members()


func _enemies_left() -> int:
	var n := 0
	for p in planes:
		if not p.allied and p.state != Aircraft.State.DEAD:
			n += 1
	return n


# ---------------------------------------------------------------- player, camera, HUD

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_dx += event.relative.x
		_mouse_dy += event.relative.y
	elif event is InputEventKey and event.pressed and not event.echo:
		if _end_time >= 0.0:
			_end_time = END_FADE  # any key ends the fade (RedAce.c:51044)
			get_viewport().set_input_as_handled()
			return
		match event.physical_keycode:
			KEY_ESCAPE, KEY_P:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				if not standalone and not mission_over:
					_was_captured = false
					get_viewport().set_input_as_handled()  # Game must not see this Esc as "resume"
					pause_requested.emit()
			KEY_R when standalone:
				load_mission(mission_id)
			KEY_N when standalone:
				var idx := MISSIONS.find(mission_id)
				load_mission(MISSIONS[(idx + 1) % MISSIONS.size()])
			KEY_TAB:
				show_objectives = not show_objectives
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				_nudge_sensitivity("roll", 0.1 if event.physical_keycode == KEY_BRACKETRIGHT else -0.1)
			KEY_MINUS, KEY_EQUAL:
				_nudge_sensitivity("pitch", 0.1 if event.physical_keycode == KEY_EQUAL else -0.1)


## In-flight shortcut for the Controls page sensitivity bars.
func _nudge_sensitivity(action: String, d: float) -> void:
	var b: Dictionary = controls.bind[action]
	b.sensitivity = snappedf(clampf(b.sensitivity + d, 0.0, 1.0), 0.1)
	controls.save()
	message_label.text = "%s sensitivity %.1f" % [action.capitalize(), b.sensitivity]
	get_tree().create_timer(1.5).timeout.connect(_clear_message)


func _clear_message() -> void:
	if not mission_over:
		message_label.text = ""


func _key(k: Key) -> float:
	return 1.0 if Input.is_physical_key_pressed(k) else 0.0


## Controls as in the original control files: mousekeys.ini (default) or keyboard.ini.
## Controls as bound in the options (Controls page; defaults from redace.ini = mousekeys.ini).
func _player_input(dt: float) -> void:
	controls.drive(player, Vector2(_mouse_dx, _mouse_dy), dt)
	_mouse_dx = 0.0
	_mouse_dy = 0.0
	player.boost = cheat_boost and controls.pressed("special")  # "special" = turbo boost cheat


func _camera_keys() -> int:
	# views are held, snapping back to the chase view on release (manual: "How to play")
	if controls.pressed("camabove"):
		return 8
	if controls.pressed("camleft"):
		return 6
	if controls.pressed("camright"):
		return 7
	if controls.pressed("cambehind"):
		return 4
	return 1


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.far = maxf(view_distance * 1.6, 2000.0)
	camera.near = 0.5
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 90.0  # original view window 1.333 x 1.0 (FUN_00436c50)
	_level.add_child(camera)
	camera.make_current()
	particles.camera = camera
	_camera_pos = Vector3.INF


var _camera_pos := Vector3.INF


## Original chase camera (decomp FUN_00435c19 / FUN_0043572b): d = forward with its vertical part
## halved; look point and camera offset per mode; distance 30 (more below y 200), x1.5 behind, x2 above;
## camera eases toward its spot at 4 * dt (dt <= 0.25) and snaps when 200 away; horizon stays level.
func _update_camera(dt: float) -> void:
	var m := player.flight_basis
	var pos := player.global_position
	var d := Vector3(m.z.x, m.z.y * 0.5, m.z.z).normalized()
	var look := Vector3.ZERO
	var off := Vector3.ZERO
	var k := 1.0
	camera_mode = forced_view if forced_view > 0 else _camera_keys()
	match camera_mode:
		4:
			look = -d * 15.0
			off = d * 15.0
			k = 1.5
		6:
			look = m.x * 15.0
			off = -m.x * 10.0
		7:
			look = -m.x * 15.0
			off = m.x * 10.0
		8:
			look = Vector3.DOWN * 15.0
			off = Vector3.UP * 40.0 - d * 20.0
			k = 2.0
		_:
			look = d * 15.0
			off = -d * 10.0
	off.y += 5.0
	var dist := 30.0 if pos.y >= 200.0 else (200.0 - pos.y) * 0.1 + 30.0
	var want := pos + off.normalized() * dist * k
	if _camera_pos == Vector3.INF or _camera_pos.distance_to(want) >= 200.0:
		_camera_pos = want
	else:
		_camera_pos += (want - _camera_pos) * minf(dt, 0.25) * 4.0
	var target := pos + look
	var dir := (target - _camera_pos).normalized()
	if camera_mode != 8 and absf(dir.y) > 0.6:
		# keep the view within +-0.6 vertical: move the camera, as the original does
		_camera_pos.y += (dir.y - 0.6 * signf(dir.y)) * 5.0
	_camera_pos.y = maxf(_camera_pos.y, ground_height(_camera_pos) + 2.0)
	camera.global_position = _camera_pos
	if not _camera_pos.is_equal_approx(target):
		var up := Vector3.UP if absf((target - _camera_pos).normalized().y) < 0.999 else Vector3.FORWARD
		camera.look_at(target, up)


func _process(dt: float) -> void:
	_update_flashes(dt)
	_update_end_fade(dt)
	if _fade_in < 1.0 and _end_time < 0.0:
		# effects come up over the first second of a flight (RedAce.c:50934)
		_fade_in = minf(_fade_in + dt, 1.0)
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(_fade_in, 0.0001)))
	# browsers release the captured mouse on Esc without passing the key on: treat that as pause
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_was_captured = true
	elif _was_captured and not standalone and not mission_over:
		_was_captured = false
		pause_requested.emit()
	if player and camera:
		_update_camera(dt)
		hud_label.visible = show_objectives
		goal_label.visible = show_objectives
		if show_objectives:
			var alt := height_above_ground(player.global_position)
			hud_label.text = "Mission %d   %s   speed %d   altitude %d   bank %d   roll/pitch sensitivity %.1f/%.1f" % [
				mission_id, player.plane_name, int(player.speed), int(alt), int(player.bank),
				controls.bind.roll.sensitivity, controls.bind.pitch.sensitivity]
			goal_label.text = _objective_text()
		_edge_of_battle()
	if brief_time > 0.0:
		brief_time -= dt
		brief_label.visible = brief_time > 0.0


## Original edge messages (strings.ini nearadgeofbattle / returntobattle): warn near the map edge;
## past it the plane is flown back toward the battle.
func _edge_of_battle() -> void:
	if mission_over or player.state == Aircraft.State.DEAD:
		return
	var near := not in_bounds(player.global_position, 350.0)
	var out := not in_bounds(player.global_position, 100.0)
	if out and not player.autopilot:
		player.autopilot = true
		_edge_warned = true
		message_label.text = strings.get("returntobattle", "Returning to Battle.")
	elif near and not out and not _edge_warned:
		_edge_warned = true
		message_label.text = strings.get("nearadgeofbattle", "You are close to the edge of the battle area.")
	elif not near and _edge_warned:
		_edge_warned = false
		player.autopilot = autopilot
		message_label.text = ""


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.world = self
	ui.add_child(hud)
	hud_label = _label(ui, 16, Color.WHITE)
	hud_label.position = Vector2(16, 150)
	goal_label = _label(ui, 16, Color(1.0, 0.85, 0.4))
	goal_label.position = Vector2(16, 172)
	message_label = _label(ui, 34, Color(1.0, 0.92, 0.6), Ini.data_path("ui/morpheus.ttf"))
	message_label.anchor_left = 0.0
	message_label.anchor_right = 1.0
	message_label.offset_left = 240
	message_label.offset_right = -240
	message_label.offset_top = 150
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.visible = false
	ui.add_child(_fade)
	_end_label = _label(ui, 28, Color.WHITE, Ini.data_path("ui/morpheus.ttf"))
	_end_label.anchor_left = 0.0
	_end_label.anchor_right = 1.0
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.visible = false
	brief_label = _label(ui, 17, Color(0.94, 0.9, 0.55), "res://fonts/Courier_New.ttf")
	brief_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief_label.anchor_left = 0.5
	brief_label.anchor_right = 0.5
	brief_label.anchor_top = 1.0
	brief_label.anchor_bottom = 1.0
	brief_label.offset_left = -460
	brief_label.offset_right = 460
	brief_label.offset_top = -250
	brief_label.offset_bottom = -16
	brief_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	brief_label.grow_vertical = Control.GROW_DIRECTION_BEGIN


## Original fonts: morpheus.ttf (game HUD and titles, decomp RedAce.c:37854) and Courier New for
## briefings (mission.html: face = "courier new"), bundled from the system msttcorefonts.
func _label(parent: Node, font_size: int, color: Color, font_path := "") -> Label:
	var l := Label.new()
	if font_path != "" and ResourceLoader.exists(font_path):
		l.add_theme_font_override("font", load(font_path))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	parent.add_child(l)
	return l


func _show_briefing(id: int) -> void:
	var f := FileAccess.open(Ini.data_path("language/english/missions/%d/mission.html" % id), FileAccess.READ)
	if f == null:
		brief_label.text = ""
		return
	var re := RegEx.create_from_string("<[^>]*>")
	var txt := re.sub(f.get_as_text(), " ", true)
	var words := {"^rank^": "Lieutenant", "^sirname^": "Pilot", "^forenames^": "Pilot", "&nbsp;": " ",
		"^controlleft^": "mouse left", "^controlright^": "mouse right",
		"^controlup^": "mouse forward", "^controldown^": "mouse back",
		"^controlfire1^": "the left mouse button", "^controlfire2^": "the right mouse button", "GO BACK": "",
		"^controlcamdown^": "the up arrow", "^controlcamup^": "the up arrow", "^controlcambehind^": "the down arrow",
		"^controlcamleft^": "the left arrow", "^controlcamright^": "the right arrow",
		"^controlthrottleup^": "right shift", "^controlthrottledown^": "right ctrl", "^controlspecial^": "space"}
	for k in words:
		txt = txt.replace(k, words[k])
	var ws := RegEx.create_from_string("\\s+")
	brief_label.text = ws.sub(txt, " ", true).strip_edges() + \
		"\n\n[Mouse: fly   Right Shift/Ctrl or W/S: throttle   Left/right button: guns/bombs   Space: boost   Arrows: views   F2: keyboard controls   [ ] - =: roll/pitch sensitivity   Tab: objectives   R: retry   N: next]"
	brief_time = 14.0


## music.ini entry -> CD audio track (redbook numbering counts audio tracks from 1, so entry
## "track = N" is the image's track N + 1, ripped to music/track<N+1>.ogg).
static func music_stream(entry: int) -> AudioStream:
	var ini := Ini.load_file(Ini.data_path("music.ini"))
	var sec: Dictionary = ini.get(str(entry), {})
	if str(sec.get("type", "")).strip_edges() != "redbook":
		return null
	var p := Ini.data_path("music/track%d.ogg" % (int(Ini.num(sec, "track", 0)) + 1))
	if not ResourceLoader.exists(p):
		return null
	var st: AudioStream = load(p)
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	return st


func _play_music(track: int) -> void:
	if music == null:
		music = AudioStreamPlayer.new()
		music.volume_db = -8.0
		music.bus = "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
		add_child(music)
	music.stream = music_stream(track)
	if music.stream:
		music.play()
