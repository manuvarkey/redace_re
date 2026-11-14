extends SceneTree
## Staged mission loading for the loading page's bar (World.load_mission_async) against the one-call load.
## godot --headless --path redace -s tools/test_loading.gd

var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func summary(w: World) -> Array:
	var out := []
	for t in w.targets:
		out.append([t.name, t.id, (t.node as Node3D).global_position.snapped(Vector3.ONE * 0.001)])
	for p in w.planes:
		out.append([p.plane_name, p.object_id, p.global_position.snapped(Vector3.ONE * 0.001), p.goals.size(), p.health])
	out.append([w.rules.size(), w.time_limit, w.map_bounds, w.player.object_id if w.player else -1])
	return out


func make_world() -> World:
	var w := World.new()
	w.standalone = false
	root.add_child(w)
	return w


func run() -> void:
	# start as Game does, from a running frame (Game._fly awaits two frames with the loading page up)
	await process_frame
	await process_frame
	for id in [-3, 1, 109]:
		var sync := make_world()
		sync.load_mission(id)
		check(not sync.loading and not sync.planes.is_empty(), "mission %d: load_mission returns loaded" % id)
		var expected := summary(sync)
		sync.free()

		var w := make_world()
		var fractions: Array[float] = []
		var frames_at_start := Engine.get_process_frames()
		var stepped := {"during": false}
		var step_frames := {}
		var progress := func(f: float) -> void:
			fractions.append(f)
			step_frames[Engine.get_process_frames()] = true
			# while loading, the world must not step: its mission clock stays at zero and planes are idle
			if w.mission_time != 0.0 or w.planes.any(func(p): return p.is_physics_processing()):
				stepped.during = true
		await w.load_mission_async(id, progress)
		var frames := Engine.get_process_frames() - frames_at_start
		check(summary(w) == expected, "mission %d: staged load builds the same mission" % id)
		check(fractions.size() >= 3 and fractions[0] == 0.0 and fractions[-1] == 1.0, "mission %d: progress runs 0 to 1 (%d steps)" % [id, fractions.size()])
		var rising := true
		for i in range(1, fractions.size()):
			rising = rising and fractions[i] >= fractions[i - 1]
		check(rising, "mission %d: progress never goes back" % id)
		check(step_frames.size() == fractions.size(), "mission %d: each step is on its own frame (%d frames, %d steps)" % [id, step_frames.size(), fractions.size()])
		check(not stepped.during, "mission %d: nothing steps while loading" % id)
		check(not w.loading and w._ui.visible, "mission %d: HUD back after loading" % id)
		check(w.planes.all(func(p): return p.is_physics_processing() and p.is_processing()), "mission %d: planes fly after loading" % id)
		print("mission %d: %d progress steps over %d frames" % [id, fractions.size(), frames])
		w.free()
	World._scene_cache.clear()
	print("Loading: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
