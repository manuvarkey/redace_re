extends SceneTree
## Ground object lookups against the full scans they replace: the collision probe broad phase
## (World._collision_target_indices) and the per-group lists (World.targets_in_groups).
## godot --headless --path redace -s tools/test_target_lookup.gd
## Optional: -- --seconds=N (live flight per mission, default 30), --missions=-3,5 (default below).

const MISSIONS := [-3, -1, 1, 5, 20, 109, 112]

var world: World
var checks := 0
var failures := 0
var compared := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


# ---------------------------------------------------------------- references: the scans before the lookups

func reference_candidates(p: Aircraft, a: Vector3, b: Vector3, margin: float) -> Array:
	var candidates: Array = []
	for q in world.planes:
		if q == p or q.hidden:
			continue
		if q._model != null:
			q.prepare_collision_parts()
			if not World.segment_near_node(q._model, q._collision_reach, a, b, margin):
				continue
		candidates.append({"node": q, "plane": q})
	for t in world.targets:
		world._prepare_target_collision(t)
		if World.segment_near_node(t.node, float(t.collision_reach), a, b, margin):
			candidates.append({"node": t.node, "target": t})
	candidates.sort_custom(func(x, y): return x.node.get_index() < y.node.get_index())
	return candidates


func reference_object_for_goal(id: int, me: Aircraft) -> Variant:
	var best = null
	var best_d := INF
	var bit := 1 << -id
	for p in world.planes:
		if p.present() and (p.groups & bit):
			var d := p.global_position.distance_squared_to(me.global_position)
			if d > 0.1 and d < best_d:
				best_d = d
				best = p
	for t in world.targets:
		if not t.dead and (int(t.groups) & bit):
			var d: float = t.node.global_position.distance_squared_to(me.global_position)
			if d > 0.1 and d < best_d:
				best_d = d
				best = t
	return best


func reference_nearest_in_group(group: int, pos: Vector3) -> Variant:
	var best: Variant = null
	var best_d := INF
	var bit := 1 << group
	for p in world.planes:
		if p.present() and p.groups & bit:
			var d := p.global_position.distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = p
	for t in world.targets:
		if not t.dead and int(t.groups) & bit:
			var d: float = (t.node as Node3D).global_position.distance_squared_to(pos)
			if d > 0.1 and d < best_d:
				best_d = d
				best = t
	return best


func same_candidates(x: Array, y: Array) -> bool:
	if x.size() != y.size():
		return false
	for i in x.size():
		if x[i].node != y[i].node or x[i].has("plane") != y[i].has("plane"):
			return false
	return true


func same_object(x: Variant, y: Variant) -> bool:
	if x == null or y == null:
		return x == null and y == null
	return is_same(x, y)


var _bad_messages := 0


func compare_segment(p: Aircraft, a: Vector3, b: Vector3, margin: float, label: String) -> void:
	compared += 1
	var ok := same_candidates(world._collision_candidates(p, a, b, margin), reference_candidates(p, a, b, margin))
	if not ok:
		failures += 1
		if _bad_messages < 10:
			_bad_messages += 1
			printerr("FAIL: %s candidates differ, segment %s..%s margin %.2f" % [label, a, b, margin])


# ---------------------------------------------------------------- checks

func load_world(id: int) -> bool:
	if world:
		world.free()
	seed(7)
	world = World.new()
	world.standalone = false
	world.autopilot = true
	root.add_child(world)
	world.load_mission(id)
	if world.targets.is_empty():
		return false
	if world.player:
		world.player.autopilot = true
	world.set_physics_process(false)
	world.set_process(false)
	for p in world.planes:
		p.set_physics_process(false)
		p.set_process(false)
	world.particles.set_process(false)
	return true


func tick(dt: float) -> void:
	world._physics_process(dt)
	for p in world.planes.duplicate():
		if is_instance_valid(p):
			p._physics_process(dt)


## Every tick of a live flight: each plane's probe envelope (as World._collide_probes asks for it) and the
## individual probes, its avoidance lookup, and each turret's target search, against the full scans.
func live_flight(id: int, seconds: float) -> void:
	if not load_world(id):
		check(false, "mission %d loads" % id)
		return
	var dt := 1.0 / 60.0
	var start_compared := compared
	var group_checks := 0
	for i in int(seconds * 60.0):
		var prev := {}
		for p in world.planes:
			prev[p] = p.global_position
		tick(dt)
		for p in world.planes:
			if p.hidden or (p.state == Aircraft.State.DEAD and not p.falling):
				continue
			var origin := p.global_position
			var from: Vector3 = prev[p]
			var margin := maxf(p.front_length, maxf(p.down_length, maxf(p.back_length, p.port_length)))
			compare_segment(p, from, origin, margin, "mission %d t=%.2f %s" % [id, world.mission_time, p.plane_name])
			if i % 10 == 0:
				for k in 6:
					var sg := p.probe_segment(k, from, origin)
					compare_segment(p, sg[0], sg[1], 0.0, "mission %d probe %d" % [id, k])
			for g in [-7, -8, -9]:
				group_checks += 1
				if not same_object(world.object_for_goal(g, p), reference_object_for_goal(g, p)):
					check(false, "mission %d object_for_goal(%d) for %s" % [id, g, p.plane_name])
		for t in world.targets:
			if t.turret:
				var pos: Vector3 = t.node.global_position
				group_checks += 1
				if not same_object(world._nearest_in_group(int(t.aa_group), pos), reference_nearest_in_group(int(t.aa_group), pos)):
					check(false, "mission %d turret search group %d" % [id, t.aa_group])
	var hud_mask := (1 << 6) | (1 << 7)
	check(world.targets_in_groups(hud_mask) == world.targets.filter(func(t): return t.groups & hud_mask), "mission %d HUD list" % id)
	print("mission %d: %d planes, %d objects, %d candidate lists and %d group searches compared over %.0f s" % [
		id, world.planes.size(), world.targets.size(), compared - start_compared, group_checks, seconds])


## Segments of every length and margin across the map, including ones spanning many cells.
func random_segments(count: int) -> void:
	var p := world.planes[0]
	var b := world.map_bounds
	for i in count:
		var a := Vector3(randf_range(b.position.x, b.end.x), randf_range(world.map_height.x, world.map_height.y + 50.0),
			randf_range(b.position.y, b.end.y))
		var length: float = [2.0, 10.0, 60.0, 250.0, 900.0][i % 5]
		var e := a + Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)).normalized() * length
		compare_segment(p, a, e, [0.0, 3.0, 12.0, 40.0][i % 4], "random")


## Short segments through and around one object's bounding sphere.
func around(t: Dictionary, label: String) -> void:
	var p := world.planes[0]
	var c: Vector3 = t.node.global_position
	world._prepare_target_collision(t)
	var sc: Vector3 = (t.node as Node3D).global_basis.get_scale().abs()
	var r := float(t.collision_reach) * sc[sc.max_axis_index()]
	for i in 200:
		var off := Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * (r + 15.0)
		var a := c + off
		compare_segment(p, a, a + Vector3(randf_range(-4, 4), randf_range(-1, 1), randf_range(-4, 4)), randf_range(0.0, 12.0), label)
	check(world._collision_candidates(p, c, c + Vector3(1, 0, 0), 0.0).any(func(x): return x.node == t.node)
		or float(t.collision_reach) == 0.0, label + ": a segment through the centre finds the object")


func edge_cases() -> void:
	load_world(-3)
	tick(1.0 / 60.0)
	random_segments(5000)

	# a damage model change can change the reach: the object is reinserted before the next query
	var target: Dictionary = {}
	for t in world.targets:
		if not t.turret and t.models.size() > 1 and float(t.endurance) > 0.0:
			target = t
			break
	var before := float(target.get("collision_reach", 0.0))
	world._damage_target(target, float(target.endurance) * 2.0)
	around(target, "after the damage model change of %s (reach %.1f -> ?)" % [target.name, before])
	world._prepare_target_collision(target)
	print("damage model: %s reach %.1f -> %.1f" % [target.name, before, float(target.collision_reach)])

	# a turret moved across the map mid-mission (Red Baron mission 12), no notification
	var gun: Dictionary = world.targets.filter(func(t): return t.turret)[0]
	(gun.node as Node3D).global_position += Vector3(2500, 0, -1800)
	around(gun, "turret moved without notice")

	# scenery moved and rescaled by a mission script, which calls targets_moved()
	var house: Dictionary = world.targets.filter(func(t): return not t.turret and float(t.get("collision_reach", 0.0)) > 3.0)[5]
	var node: Node3D = house.node
	node.global_transform = Transform3D(node.global_basis.scaled(Vector3(3, 1, 3)), node.global_position + Vector3(-1500, 0, 900))
	world.targets_moved()
	around(house, "scenery moved and rescaled with targets_moved()")

	# an object added at run time is found by both lookups without notification
	var sec := {"name": "tree1", "id": 999001, "groups": str(1 << 7), "pos": "%f %f %f" % [node.global_position.x + 40.0,
		node.global_position.y, node.global_position.z], "up": "0 1 0", "at": "0 0 1", "right": "1 0 0"}
	world._spawn_ground(sec, false)
	var added: Dictionary = world.targets[-1]
	around(added, "object added at run time")
	check(world.targets_in_groups(1 << 7).has(added), "group list includes an object added at run time")

	# the same mission loaded again: same object count, fresh lookups
	world.load_mission(-3)
	world.player.autopilot = true
	for p in world.planes:
		p.set_physics_process(false)
		p.set_process(false)
	tick(1.0 / 60.0)
	random_segments(2000)
	var g7: Array = world.targets_in_groups(1 << 7)
	check(g7.all(func(t): return is_instance_valid(t.node) and world.targets.has(t)), "group lists rebuilt after a reload")


func run() -> void:
	var seconds := 30.0
	var missions: Array = MISSIONS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
		if a.begins_with("--missions="):
			missions = Array(a.get_slice("=", 1).split(",")).map(func(s): return int(s))
	for id in missions:
		live_flight(id, seconds)
	edge_cases()
	world.free()
	World._scene_cache.clear()
	print("Target lookup: %d candidate lists compared, %d checks, %d failures" % [compared, checks + compared, failures])
	quit(1 if failures else 0)
