extends SceneTree
## Paired deterministic oracle from 4bb147d: damage events, effects, survivors and ribbons.

class QuietWorld extends World:
	var sounds: Array = []
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func play_at(at: Vector3, _stream: AudioStream, volume := 0.0) -> void:
		sounds.append([at, volume])

class ReferenceWorld extends "res://tools/bullet_reference.gd":
	var sounds: Array = []
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func play_at(at: Vector3, _stream: AudioStream, volume := 0.0) -> void:
		sounds.append([at, volume])

class RecordingParticles extends Particles:
	var events: Array = []
	func _ready() -> void:
		set_process(false)
	func puff(system: String, pos: Vector3, vel: Vector3, size: float, color: Color,
			color_rate := Color(0, 0, 0, -1), size_rate := 0.0, gravity := 0.0) -> void:
		events.append([system, pos, vel, size, color, color_rate, size_rate, gravity])
	func burst(pos: Vector3, size: float) -> void:
		events.append(["burst", pos, size])
	func smoke_column(pos: Vector3, size: float) -> void:
		events.append(["column", pos, size])

class HitPlane extends Aircraft:
	var hits: Array = []
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func on_hit(_attacker) -> void:
		pass
	func take_damage(amount: float, attacker = null) -> void:
		hits.append([amount, attacker.object_id if attacker is Aircraft else 0])
		super.take_damage(amount, attacker)

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	run.call_deferred()

func plane(w: World, id: int, pos: Vector3, radius := 10.0, groups := 1) -> HitPlane:
	var p := HitPlane.new()
	p.world = w
	p.object_id = id
	p.proximity_groups = groups
	p.hit_radius_sq = radius * radius
	p.health = 10000
	p.endurance = 10000
	w.add_child(p)
	p.position = pos
	w.planes.append(p)
	return p

func round_at(pos: Vector3, vel := Vector3.ZERO, owner_obj = null, aa := false, life := 10.0, damage := 1.0) -> Dictionary:
	return {"pos": pos, "vel": vel, "owner": owner_obj, "aa": aa, "life": life, "damage": damage}

func target(w: World, pos: Vector3, rotated := false) -> Dictionary:
	var node := Node3D.new()
	w._level.add_child(node)
	node.position = pos
	if rotated:
		node.rotation = Vector3(0.35, 0.6, 0.25)
		node.scale = Vector3(1.5, 2.0, 0.7)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	node.add_child(mesh)
	var t := {"node": node, "center": Vector3.ZERO, "aabb": AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)),
		"dead": false, "health": 50.0, "endurance": 50.0, "model_index": 0,
		"models": [""], "name": "fixture", "groups": 0, "hit_sound": null,
		"explosion_sound": null, "break_sound": null, "hit_time": 0.0}
	w.targets.append(t)
	return t

func setup(reference: bool) -> World:
	var w: World = ReferenceWorld.new() if reference else QuietWorld.new()
	root.add_child(w)
	w.map_bounds = Rect2(-2000, -2000, 4000, 4000)
	w._level = Node3D.new()
	w.add_child(w._level)
	w.particles = RecordingParticles.new()
	w._level.add_child(w.particles)
	w.camera = Camera3D.new()
	w.add_child(w.camera)
	w.camera.position = Vector3(60, 150, 150)
	w._make_bullet_multimesh()
	# Real, two-sided terrain physics query, including a ray starting below the surface.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	shape.shape = box
	body.add_child(shape)
	w._level.add_child(body)
	body.position.y = -1
	return w

func snapshot(w: World) -> Dictionary:
	var bullets := []
	for b in w.bullets:
		bullets.append([b.pos, b.vel, b.life, b.damage, b.aa, b.owner.object_id if b.owner is Aircraft else 0])
	var aircraft := []
	for p: HitPlane in w.planes:
		aircraft.append([p.object_id, p.health, p.state, p.hits.duplicate(true)])
	var scenery := []
	for t in w.targets:
		scenery.append([t.health, t.dead])
	return {"bullets": bullets, "planes": aircraft, "targets": scenery,
		"effects": w.particles.events.duplicate(true), "sounds": w.sounds.duplicate(true)}

func scenario(reference: bool, kind: String) -> Array:
	seed(45678)
	var w := setup(reference)
	var ticks := 5
	match kind:
		"repeated and multiple aircraft":
			var owner := plane(w, 1, Vector3(100, 100, 100))
			plane(w, 2, Vector3(100, 100, 100), 12.0, 3) # 3 groups => 3 hits every tick
			plane(w, 3, Vector3(102, 100, 100))
			var hidden := plane(w, 4, Vector3(100, 100, 100))
			hidden.hidden = true
			plane(w, 5, Vector3(100, 100, 100)).state = Aircraft.State.DEAD
			plane(w, 6, Vector3(100, 100, 100), 10.0, 0)
			plane(w, 7, Vector3(90, 100, 100)) # moving away from the radius boundary
			w.bullets.append(round_at(Vector3(100, 100, 100), Vector3(0.1, 0, 0), owner))
		"terrain scenery AA and expiry":
			var t := target(w, Vector3(0, 10, 0))
			target(w, Vector3(-100, 10, 0), true)
			w.bullets.append(round_at(Vector3(-3, 10, 0), Vector3(360, 0, 0)))
			w.bullets.append(round_at(Vector3(10, 1, 10), Vector3(0, -120, 0)))
			w.bullets.append(round_at(Vector3(10, -3, 10), Vector3(0, 240, 0)))
			w.bullets.append(round_at(Vector3(-3, 10, 0), Vector3(360, 0, 0), null, true))
			w.bullets.append(round_at(Vector3(0, 10, 0), Vector3.ZERO, null, false, 0.001))
			w.bullets.append(round_at(Vector3(1999, 100, 0), Vector3(360, 0, 0)))
			w.bullets.append(round_at(Vector3(-103, 10, 0), Vector3(360, 0, 0)))
			# Descending segment starts above the top: must still test scenery.
			w.bullets.append(round_at(Vector3(0, 20, 0), Vector3(0, -600, 0), null, false, 10, 60))
			# A later bullet still hits and stops on the wreck.
			w.bullets.append(round_at(Vector3(-3, 10, 0), Vector3(360, 0, 0)))
		"heavy firing and cell boundaries":
			ticks = 30
			var random := RandomNumberGenerator.new()
			random.seed = 98765
			for i in 22:
				var p := plane(w, i + 1, Vector3((i % 4) * 100, 100 + (i % 3) * 100, (i / 4) * 100), 20, 1 + i % 3)
				if i == 0:
					p.health = 2 # dies part way through the bullet pass
			for i in 4096:
				var pos := Vector3(random.randf_range(-40, 360), random.randf_range(60, 340), random.randf_range(-40, 560))
				var vel := Vector3(random.randf_range(-40, 40), random.randf_range(-20, 20), random.randf_range(-40, 40))
				w.bullets.append(round_at(pos, vel, w.planes[i % 22] if i % 3 == 0 else null, i % 4 == 0,
					random.randf_range(0.01, 0.6)))
			for pos in [Vector3(100, 100, 100), Vector3(-100, 100, -100), Vector3(0, 100, 0)]:
				var p := plane(w, w.planes.size() + 1, pos, 150)
				p.hidden = false # radii spanning multiple cells
		"strict sphere boundary":
			plane(w, 1, Vector3(110, 100, 100))
			w.bullets.append(round_at(Vector3(100, 100, 100)))
		"moving between ticks":
			plane(w, 1, Vector3(500, 100, 0))
			target(w, Vector3(0, 10, 0))
			w.bullets.append(round_at(Vector3(0, 100, 0)))
	w._build_grid()
	await physics_frame
	await physics_frame
	var space := w.get_world_3d().direct_space_state
	var result := []
	for tick in ticks:
		if kind == "moving between ticks":
			w.planes[0].position.x = 0 if tick % 2 == 0 else 500
			w.planes[0].hidden = tick == 2
			w.targets[0].node.position.y = tick * 25
			w.bullets.append(round_at(Vector3(-3, 100, 0), Vector3(360, 0, 0)))
		w.mission_time += 1.0 / 60.0
		w._update_bullets(1.0 / 60.0, space)
		result.append(snapshot(w))
		result[-1].rng = randf() # damage/effects must consume the same random draws in the same order
	if kind == "repeated and multiple aircraft":
		check(w.bullets.size() == 1, "aircraft hits never consume the bullet")
		check(w.planes[1].hits.size() == 15 and w.planes[2].hits.size() == 5, "repeat damage and multiple aircraft preserved")
		check(w.planes[0].hits.is_empty() and w.planes[3].hits.is_empty() and w.planes[4].hits.is_empty(), "owner, hidden and dead exclusions")
	if kind == "strict sphere boundary":
		check(w.planes[0].hits.is_empty(), "strict radius equality is excluded")
	if kind == "moving between ticks":
		check(w.targets[0].health < 50, "scenery cache follows placement changes between ticks")
	if kind == "terrain scenery AA and expiry":
		check(w.targets[0].dead and w.targets[1].health < 50, "scenery damage, wrecks and transformed models exercised")
		check(w.bullets.size() == 1 and w.bullets[0].aa, "terrain, scenery, expiry and bounds remove rounds; AA passes through")
	if kind == "heavy firing and cell boundaries":
		check(w.planes[0].state == Aircraft.State.DEAD, "live presence checks stop later damage after death")
	# Compare the actual ribbon vertex/UV/color buffers, including empty meshes and moved cameras.
	w.bullets.append(round_at(Vector3(0, 120, 0), Vector3(0, 0, 300)))
	w.bullets.append(round_at(Vector3(10, 120, 0), Vector3(0, 0, 300), null, true))
	w._draw_bullets()
	var surfaces := []
	for i in w._bullets_mesh.get_surface_count():
		surfaces.append(w._bullets_mesh.surface_get_arrays(i))
		check(surfaces[-1][Mesh.ARRAY_VERTEX].size() >= 12, "actual ribbon buffers contain both gun and AA vertices")
	result.append(surfaces)
	w.free()
	await physics_frame
	return result

func run() -> void:
	for kind in ["repeated and multiple aircraft", "terrain scenery AA and expiry", "heavy firing and cell boundaries", "moving between ticks", "strict sphere boundary"]:
		var baseline := await scenario(true, kind)
		var optimized := await scenario(false, kind)
		check(baseline == optimized, "paired positions, lifetime, damage, order, effects and rendering: " + kind)
	print("Bullet parity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
