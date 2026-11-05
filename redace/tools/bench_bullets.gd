extends SceneTree
## Fixed heavy-fire CPU benchmark on actual Britain geometry. No FPS claim in headless mode.
## godot --headless --path redace -s tools/bench_bullets.gd

var world: World
var rounds: Array[Dictionary] = []
var ends: PackedVector3Array = []
var reference := false
var altitude := 360.0
var space: PhysicsDirectSpaceState3D

func _initialize() -> void:
	run.call_deferred()

func timed(label: String, action: Callable, count := 20) -> void:
	for i in 3:
		action.call()
	var samples: Array[float] = []
	for i in count:
		var start := Time.get_ticks_usec()
		action.call()
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	print("BENCH %s median_ms=%.3f p95_ms=%.3f" % [label, samples[samples.size() / 2], samples[int(samples.size() * 0.95)]])

func collision() -> void:
	if not reference:
		world._prepare_bullet_collision()
	for i in rounds.size():
		world._bullet_hits(rounds[i], rounds[i].pos, ends[i], space)

func scenery() -> void:
	if not reference:
		world._prepare_bullet_collision()
	for i in rounds.size():
		world._bullet_hits_scenery(rounds[i], rounds[i].pos, ends[i], space)

func terrain() -> void:
	for i in rounds.size():
		space.intersect_ray(PhysicsRayQueryParameters3D.create(rounds[i].pos, ends[i]))

func aircraft() -> void:
	for i in rounds.size():
		var b: Dictionary = rounds[i]
		for p in world.planes:
			if p.proximity_groups == 0 or is_same(p, b.owner) or not p.present():
				continue
			if p.global_position.distance_squared_to(ends[i]) < p.hit_radius_sq:
				for k in p.proximity_groups:
					p.take_damage(b.damage, b.owner)

func step() -> void:
	for i in rounds.size():
		var b: Dictionary = rounds[i]
		b.pos = Vector3(2700 + (i % 32) * 2, altitude, 1700 + (i / 32) * 2)
		b.life = World.BULLET_LIFE
	world.bullets.assign(rounds)
	world._physics_process(1.0 / 60.0)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--reference":
			reference = true
		if arg.begins_with("--altitude="):
			altitude = float(arg.get_slice("=", 1))
	seed(12345)
	world = load("res://tools/bullet_reference.gd").new() if reference else World.new()
	world.standalone = false
	root.add_child(world)
	world.load_mission(26)
	world.autopilot = true
	world.set_physics_process(false)
	world.set_process(false)
	for p in world.planes:
		p.set_physics_process(false)
		p.set_process(false)
		p.hidden = false  # all raids present, testing the heavy combat candidate count
	world.particles.set_process(false)
	# Prevent mission-end/turret work from changing the sample between iterations.
	world.mission_over = true
	for target in world.targets:
		target.turret = false
	await physics_frame
	await physics_frame
	space = world.get_world_3d().direct_space_state
	print("BENCH engine=%s display=%s renderer=%s planes=%d targets=%d terrain=%s altitude=%.0f reference=%s" % [Engine.get_version_info().string,
		DisplayServer.get_name(), RenderingServer.get_current_rendering_method(), world.planes.size(), world.targets.size(), world.map_height, altitude, reference])
	for n in [1024, 4096]:
		rounds.clear()
		ends.clear()
		for i in n:
			var pos := Vector3(2700 + (i % 32) * 2, altitude, 1700 + (i / 32) * 2)
			var vel := Vector3(20, -2, 300)
			rounds.append({"pos": pos, "vel": vel, "owner": null, "life": World.BULLET_LIFE, "damage": 1.0, "aa": false})
			ends.append(pos + vel / 60.0)
		world.bullets.assign(rounds)
		timed("n=%d collision" % n, collision)
		timed("n=%d scenery_and_terrain" % n, scenery)
		timed("n=%d terrain" % n, terrain)
		timed("n=%d reference_aircraft_scan" % n, aircraft)
		timed("n=%d render_prepare" % n, world._draw_bullets)
		timed("n=%d physics_step_including_render" % n, step)
	world.free()
	World._scene_cache.clear()
	quit()
