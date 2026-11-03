extends SceneTree
## Run: godot --headless --path redace -s tools/test_britain_aircraft.gd
## No mission/assets generation or World spawning integration is required.

const BritainAircraft := preload("res://mods/britain/aircraft.gd")
const STEP := 1.0 / 60.0
var failures := 0
var checks := 0
var world: TestWorld


class TestWorld extends World:
	var shots: Array[Dictionary] = []
	var water := false
	var splashes := 0
	var losses := 0
	var terrain := 0.0
	var cliff_x := INF
	var cliff_height := 0.0
	var sea_queries: Array[Vector3] = []

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		particles = Particles.new()
		# No scene/effects setup: inherited damage calls work with empty particle systems.
		map_bounds = Rect2(-20000, -20000, 40000, 40000)
		map_height = Vector2(100, 1500)
		ordnance = {1: {"releasespeed": "250"}, 2: {"releasespeed": "0"}}

	func _exit_tree() -> void:
		particles.free()

	func ground_height(_pos: Vector3) -> float:
		return cliff_height if _pos.x >= cliff_x else terrain

	func ground_normal(_pos: Vector3) -> Vector3:
		return Vector3.UP

	func ground_hit_fraction(from: Vector3, to: Vector3) -> float:
		var floor := ground_height(to)
		if from.y > floor and to.y <= floor:
			return (from.y - floor) / (from.y - to.y)
		return 0.0

	func is_sea(pos: Vector3) -> bool:
		sea_queries.append(pos)
		return water

	func sea_crash(_pos: Vector3) -> void:
		splashes += 1

	func spawn_ordnance(owner_obj, kind: int, pos: Vector3, base_vel: Vector3, dir := Vector3.ZERO) -> void:
		shots.append({"owner": owner_obj, "kind": kind, "pos": pos, "velocity": base_vel, "direction": dir})

	func play_at(_pos: Vector3, _stream: AudioStream, _volume_db := 0.0) -> void:
		pass

	func flash(_node: Node3D, _seconds := 0.25) -> void:
		pass

	func collide(_plane: Aircraft, _prev: Vector3, _dt: float) -> void:
		pass

	func _count_rule_members() -> void:
		pass

	func record_loss(_plane: Aircraft) -> void:
		losses += 1


class VisualAircraft extends "res://mods/britain/aircraft.gd":
	var loaded_paths: Array[String] = []

	func _load_damage_model(path: String) -> Node3D:
		loaded_paths.append(path)
		var model := Node3D.new()
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.scale = Vector3.ONE * 0.1  # Damage art is deliberately smaller than the collision model.
		model.add_child(mesh)
		return model


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func _fresh_world() -> void:
	if world:
		world.free()
	world = TestWorld.new()
	root.add_child(world)


func _plane(name_: String, pos := Vector3(0, 350, 0), side := false) -> Aircraft:
	var plane := BritainAircraft.new()
	plane.plane_name = name_
	plane.world = world
	plane.allied = side
	plane.object_id = 100 + world.planes.size()
	world.add_child(plane)
	world.planes.append(plane)
	world.objects_by_id[plane.object_id] = plane
	plane.place(Transform3D(Basis.IDENTITY, pos))
	plane._first_frame = false
	plane.state = Aircraft.State.FLYING
	var physics: Dictionary = Ini.load_file(Ini.data_path("objects/planes/%s/plane.ini" % ("bristolscout" if name_ == "bristol" else name_))).get("physics", {})
	for pair in [["high_speed", "highspeed"], ["cruise_speed", "cruisespeed"], ["climb_speed", "climbspeed"],
		["dive_speed", "divespeed"], ["stall_speed", "stallspeed"], ["high_roll", "highroll"], ["low_roll", "lowroll"],
		["high_pitch", "highpitch"], ["low_pitch", "lowpitch"], ["accel", "accel"]]:
		plane.set(pair[0], Ini.num(physics, pair[1], plane.get(pair[0])))
	plane.speed = plane.cruise_speed
	plane.throttle = 1.0
	plane.velocity = Vector3.BACK * plane.speed * plane.speed / plane.high_speed
	plane._update_ahead_alt()
	plane.set_physics_process(false)
	plane.set_process(false)
	plane.destroyed.connect(world.record_loss)
	return plane


func _target(pos := Vector3.ZERO) -> Dictionary:
	var node := Node3D.new()
	world.add_child(node)
	node.global_position = pos
	var target := {"id": 1, "node": node, "dead": false, "groups": 1 << 7}
	world.objects_by_id[1] = target
	return target


func _run() -> void:
	_test_ceiling_and_limits()
	_test_bombing()
	_test_mission_approach()
	_test_gunners()
	_test_escorts()
	_test_formation_speed()
	_test_cliff_preview()
	_test_defender_waves()
	_test_damage()
	_test_crashes()
	world.free()
	print("BRITAIN AIRCRAFT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_ceiling_and_limits() -> void:
	_fresh_world()
	for name_ in ["he111", "bf109", "spitfire"]:
		var plane = _plane(name_, Vector3(0, 950, 0))
		plane._ai_pitch = 5.0
		plane.pitch_rate = 5.0
		plane._fly(STEP)
		_check(plane.speed >= plane.cruise_speed - 0.1, name_ + " must not lose speed above the old ceiling")
		_check(plane.state == Aircraft.State.FLYING, name_ + " must not altitude-stall")
		_check(plane.ahead_alt > 900.0, name_ + " must retain actual ahead clearance")
		plane.position.y = 100.0
		plane._update_ahead_alt()
		plane._ai_pitch = 0.0
		plane._avoid_terrain()
		_check(plane._ai_pitch > 0.0, name_ + " must still avoid actual nearby terrain")
		plane.position.y = 200.0
		plane._update_ahead_alt()
		plane._ai_pitch = 0.0
		plane._avoid_terrain()
		_check(plane._ai_pitch == 0.0, name_ + " must not acquire a higher minimum altitude")
		plane.speed = plane.stall_speed - 20.0
		plane._fly(STEP)
		_check(plane.state == Aircraft.State.STALL, name_ + " must retain real low-speed stalls")
	var legacy = _plane("bristol", Vector3(0, 950, 0))
	legacy.ahead_alt = 600.0
	legacy.pitch_rate = 5.0
	legacy._ai_pitch = 5.0
	legacy._fly(STEP)
	_check(legacy.speed < legacy.stall_speed, "Legacy aircraft must retain inherited altitude behavior")
	var bomber = _plane("he111")
	for sign_ in [-1.0, 1.0]:
		bomber.goals.assign([{"type": Aircraft.G_EVADE, "pos": Vector3(sign_ * 300, 1500, -300), "radius": 5.0}])
		bomber._ai(STEP)
		bomber._apply_ai_commands()
		_check(absf(bomber.bank) <= 22.0 and absf(bomber.pitch_rate) <= 4.0, "Evade commands must obey bomber limits")
		for i in 300:
			bomber._ai_bank = sign_ * 90.0
			bomber._ai_pitch = sign_ * 90.0
			bomber._apply_ai_commands()
			bomber._fly(STEP)
		_check(absf(bomber.bank) <= 22.001, "He 111 bank must stay bounded through sustained commands")
		_check(absf(rad_to_deg(asin(bomber.flight_basis.z.y))) <= 8.001, "He 111 pitch attitude must stay bounded")
		_check(bomber.speed < 125.0 and bomber.flight_basis.y.y > 0.0, "Bomber must remain slow and upright")
	var goal_count: int = bomber.goals.size()
	bomber.retaliate = true
	bomber.on_hit(legacy)
	_check(bomber.goals.size() == goal_count, "Hits must not replace the bombing bearing with fighter retaliation")


func _test_bombing() -> void:
	_fresh_world()
	_target()
	var bomber = _plane("he111", Vector3(0, 350, -2000))
	bomber.ordnance_type = 1
	bomber.ordnance_left = 3
	bomber.goals.assign([{"type": Aircraft.G_BOMB_RUN, "targetid": 1}])
	var max_bank := 0.0
	var max_pitch := 0.0
	var min_height := INF
	var max_height := -INF
	var circuit_entries := 0
	var was_circling := false
	# Long enough to release on several passes, empty the racks and continue circling.
	for i in 36000:
		bomber._physics_process(STEP)
		var circling: bool = not bomber._bomb_circuit.is_empty()
		if circling and not was_circling:
			circuit_entries += 1
		was_circling = circling
		max_bank = maxf(max_bank, absf(bomber.bank))
		max_pitch = maxf(max_pitch, absf(rad_to_deg(asin(bomber.flight_basis.z.y))))
		min_height = minf(min_height, bomber.position.y)
		max_height = maxf(max_height, bomber.position.y)
	_check(max_bank <= 22.001 and max_pitch <= 8.001, "Full bombing/circuit simulation must obey attitude limits")
	_check(min_height >= 300.0 and max_height <= 400.0, "Bombing approach and retry must hold 300–400 above target")
	_check(world.shots.size() == 3 and bomber.ordnance_left == 0, "Repeated circuits must actually deliver all three bombs (shots=%d, pos=%s, circuit=%s)" % [world.shots.size(), bomber.position, bomber._bomb_circuit])
	_check(circuit_entries >= 3, "Missed/empty bomb runs must retry through circuits (entries=%d)" % circuit_entries)
	_check(bomber.current_goal().get("type") == Aircraft.G_BOMB_RUN, "Empty racks must never switch the factory goal to guns")
	_check(bomber.state == Aircraft.State.FLYING and not bomber.left_map, "Bomber must remain in flight after repeat passes")
	for shot in world.shots:
		_check(shot.kind == 2, "He 111 factory attacks must spawn bombs, never forward bullets")
		var pos: Vector3 = shot.pos
		var vel: Vector3 = shot.velocity
		# Independently integrate the same semi-implicit gravity used by World._update_shells.
		while pos.y > 0.0:
			vel.y -= 60.0 * STEP
			pos += vel * STEP
		_check(Vector2(pos.x, pos.z).length() < 30.0, "Actual gravity-60 bomb trajectory must hit within factory blast radius")
	# A nonzero vertical velocity and release impulse must enter the ballistic prediction too.
	bomber.position = Vector3(0, 370, -700)
	bomber.velocity = Vector3(20, 12, 110)
	world.ordnance[2].releasespeed = "10"
	var impact: Vector3 = bomber._bomb_impact(40.0)
	var v: Vector3 = bomber.velocity + bomber.velocity.normalized() * 10.0
	var origin: Vector3 = bomber.global_position - bomber.global_basis.y * 2.0
	var time := (v.y + sqrt(v.y * v.y + 120.0 * (origin.y - 40.0))) / 60.0
	var expected := origin + v * time + Vector3.DOWN * 30.0 * time * time
	_check(impact.distance_to(expected) < 0.001, "Ballistic prediction must include launch offset, vertical speed and release impulse")
	for kind in [Aircraft.G_ATTACK, Aircraft.G_DIVE_ATTACK]:
		bomber.goals.assign([{"type": kind, "targetid": 1}])
		bomber._ai(STEP)
		bomber._apply_ai_commands()
		_check(not bomber.fire_input and not bomber.secondary_input and absf(bomber.bank) <= 22.0,
			"Inherited attack/dive goals must not turn empty bombers into fighters")


func _test_mission_approach() -> void:
	_fresh_world()
	world.map_bounds = Rect2(0, 0, 6400, 6400)
	world.require_shot_down = true
	world.terrain = 46.0
	_target(Vector3(1800, 46, 3300))
	var bomber = _plane("he111", Vector3(5100, 440, 2300))
	bomber.place(Transform3D(Basis.looking_at(Vector3(1, 0, -1).normalized(), Vector3.UP), bomber.position))
	bomber.ordnance_type = 1
	bomber.ordnance_left = 2
	bomber.goals.assign([{"type": Aircraft.G_BOMB_RUN, "targetid": 1}])
	for i in 18000:
		bomber._physics_process(STEP)
	_check(not bomber.left_map and not bomber.hidden and bomber.present(), "Slow-roll circuits from the mission spawn must remain inside Britain")
	_check(world.shots.size() == 2, "Oblique mission approach must align and deliver bombs with the new INI rates (shots=%d, pos=%s)" % [world.shots.size(), bomber.position])


func _test_gunners() -> void:
	_fresh_world()
	var bomber = _plane("he111")
	var enemy = _plane("spitfire", bomber.position + Vector3(0, 0, -200), true)
	enemy.velocity = bomber.velocity
	var hidden_enemy = _plane("spitfire", bomber.position + Vector3(0, 0, -80), true)
	hidden_enemy.hidden = true
	var dead_enemy = _plane("spitfire", bomber.position + Vector3(0, 0, -60), true)
	dead_enemy.state = Aircraft.State.DEAD
	var near_enemy = _plane("spitfire", bomber.position + Vector3(60, 0, -100), true)
	near_enemy.velocity = bomber.velocity
	bomber.fire_input = true
	bomber._guns(STEP)
	_check(world.shots.size() == 1 and world.shots[0].kind == 1, "Rear gunner must use existing bullet kind")
	_check(world.shots[0].direction.x > 0.4, "Gunner must select the nearest present eligible enemy")
	for i in 60:
		bomber._guns(STEP)
	_check(world.shots.size() >= 5 and world.shots.size() <= 6, "Gunner must respect a five-round-per-second cadence")
	near_enemy.hidden = true
	for offset in [Vector3(0, 0, 200), Vector3(200, 0, 0), Vector3(0, -200, -100), Vector3(0, 0, -500)]:
		enemy.position = bomber.position + offset
		_check(bomber._gunner_shot().is_empty(), "Gunner must reject masked or out-of-range sectors: " + str(offset))
	enemy.position = bomber.position + Vector3(0, 180, -80)
	var dorsal: Dictionary = bomber._gunner_shot()
	_check(not dorsal.is_empty() and dorsal.origin.y > bomber.position.y + bomber.up_length,
		"Dorsal gunner must shoot above the fuselage")
	enemy.position = bomber.position + Vector3(0, 0, -200)
	var friend = _plane("bf109", bomber.position + Vector3(0, 0, -100))
	_check(bomber._gunner_shot().is_empty(), "Gunner must withhold fire through a friendly aircraft")
	friend.hidden = true
	_check(not bomber._gunner_shot().is_empty(), "Hidden aircraft must not obstruct gunner fire")
	var before := world.shots.size()
	bomber.hidden = true
	bomber._guns(1.0)
	bomber.hidden = false
	bomber.state = Aircraft.State.DEAD
	bomber._guns(1.0)
	_check(world.shots.size() == before, "Hidden or dead bombers must never fire")
	var fighter = _plane("bf109")
	fighter.state = Aircraft.State.DEAD
	fighter.fire_input = true
	fighter._guns(1.0)
	_check(world.shots.size() == before, "A fighter must not fire in the remainder of its sea-crash frame")


func _test_escorts() -> void:
	_fresh_world()
	var leader = _plane("he111")
	leader.place(Transform3D(Basis(Vector3.UP, PI / 2), leader.position))
	var escort = _plane("bf109", Vector3(0, 395, -200))
	escort.escort_leader_id = leader.object_id
	escort.goals.assign([{"type": Aircraft.G_ATTACK, "targetid": -8}])
	escort._ai(STEP)
	var station: Vector3 = leader.position + leader.flight_basis * escort.escort_offset
	var expected_side: float = escort._local_dir(station + leader.flight_basis.z * maxf(leader.speed * leader.speed / leader.high_speed * 3.0, 180.0) - escort.position).x
	_check(signf(escort._ai_bank) == signf(expected_side) and not escort.fire_input,
		"Escort must follow the externally selected leader's rotated local offset")
	var hidden_enemy = _plane("spitfire", Vector3(0, 395, -100), true)
	hidden_enemy.hidden = true
	var dead_enemy = _plane("spitfire", Vector3(0, 395, -90), true)
	dead_enemy.state = Aircraft.State.DEAD
	escort._ai(STEP)
	_check(escort._escort_attack.is_empty(), "Escort must ignore hidden and dead threats")
	var threat = _plane("spitfire", leader.position + Vector3(0, 0, 640), true)
	escort._ai(STEP)
	_check(escort._escort_attack.get("targetid") == threat.object_id, "Threat within 650 of bomber must draw its escort")
	threat.position = Vector3(0, 350, 2000)
	escort._ai(STEP)
	_check(escort._escort_attack.is_empty() and not escort.fire_input, "Out-of-range threats must release escort back to formation")
	threat.position = leader.position + Vector3(0, 0, 200)
	escort._ai(STEP)
	threat.hidden = true
	escort._ai(STEP)
	_check(escort._escort_attack.is_empty(), "Hidden attack targets must release escort back to formation")
	threat.hidden = false
	escort.health = 10.0
	escort._ai(STEP)
	_check(escort._escort_attack.is_empty() and escort._escort_rest > 0.0 and not escort.fire_input,
		"Inherited damage disengagement must resume escorting without immediate reacquisition")
	escort.goals.assign([{"type": Aircraft.G_HIDE}, {"type": Aircraft.G_WAIT_TIME, "radius": 1.0},
		{"type": Aircraft.G_APPEAR, "pos": Vector3(0, 400, 0)}, {"type": Aircraft.G_ATTACK, "targetid": -8}])
	escort._ai(0.5)
	_check(escort.hidden and not escort.fire_input, "Escort must preserve timed hidden raid scripting")
	escort._ai(0.6)
	_check(not escort.hidden and escort.state == Aircraft.State.FLYING, "Escort must appear when its scripted wait completes")


func _test_formation_speed() -> void:
	_fresh_world()
	var leader = _plane("he111")
	var escort = _plane("bf109")
	var spitfire = _plane("spitfire", Vector3(8000, 350, 0), true)
	_check(absf(leader.high_speed / spitfire.high_speed - 270.0 / 355.0) < 0.0001,
		"Actual INI bomber/fighter maxima must preserve the historical reference ratio")
	_check(absf(escort.high_speed / spitfire.high_speed - 354.0 / 355.0) < 0.0001,
		"Actual INI Bf109/Spitfire maxima must preserve the historical reference ratio")
	escort.escort_leader_id = leader.object_id
	escort.goals.assign([{"type": Aircraft.G_ATTACK, "targetid": -8}])
	# Deliberately start behind and to the side of the slot, at fighter cruise speed.
	escort.position = leader.position + escort.escort_offset + Vector3(35, 0, -80)
	var max_speed_error := 0.0
	var max_slot_error := 0.0
	for i in 7200:
		leader._steer(leader.position + Vector3(0, 350.0 - leader.position.y, 1000))
		leader._apply_ai_commands()
		leader._fly(STEP)
		escort._physics_process(STEP)
		if i > 3600:
			max_speed_error = maxf(max_speed_error, absf(escort.velocity.length() - leader.velocity.length()))
			max_slot_error = maxf(max_slot_error, escort.position.distance_to(leader.position + leader.flight_basis * escort.escort_offset))
	_check(max_speed_error < 2.0, "Settled escort must match bomber physical speed within 2 units/s (error=%f)" % max_speed_error)
	_check(max_slot_error < 20.0, "Escort must hold its slot without orbiting the bomber (error=%f)" % max_slot_error)
	_check(escort.state == Aircraft.State.FLYING, "Formation speed must remain above fighter stall speed")


func _test_cliff_preview() -> void:
	_fresh_world()
	world.cliff_x = 480.0
	world.cliff_height = 180.0
	var defender = _plane("spitfire", Vector3(0, 235, 0), true)
	defender.flight_basis = Basis(Vector3.UP, PI / 2)
	defender.goals.assign([{"type": Aircraft.G_WAYPOINT, "pos": Vector3(1200, 235, 0), "radius": 20.0}])
	defender._ai(STEP)
	_check(defender._ai_pitch >= 25.0 and defender.throttle == 1.0,
		"An allied Spitfire must begin pulling up before the original terrain ray reaches a cliff")
	for i in 480:
		defender._physics_process(STEP)
		if defender.position.x >= world.cliff_x:
			break
	_check(defender.position.x >= world.cliff_x and defender.state == Aircraft.State.FLYING,
		"Allied Spitfire must cross a 180-unit cliff safely")
	_check(defender.position.y > world.cliff_height + defender.gear_height,
		"Cliff crossing must retain gear clearance")


func _test_defender_waves() -> void:
	_fresh_world()
	world.require_shot_down = true
	var defender = _plane("spitfire", Vector3(0, 350, 0), true)
	var later_wave = _plane("he111", Vector3(0, 350, 300))
	later_wave.hidden = true
	defender._ai(STEP)
	_check(defender.current_goal().get("type") == Aircraft.G_EVADE, "Defender must patrol while future waves are hidden")
	later_wave.hidden = false
	for i in 185:
		defender._ai(STEP)
	_check(defender.current_goal().get("targetid") == later_wave.object_id and defender.current_goal().get("type") == Aircraft.G_ATTACK,
		"Defender must reacquire a newly appeared wave within its three-second patrol")
	later_wave.state = Aircraft.State.DEAD
	defender._ai(STEP)
	defender._ai(STEP)
	_check(defender.current_goal().get("type") == Aircraft.G_EVADE, "Defender must resume patrol after destroying a wave")
	defender.position.x = world.map_bounds.end.x - 100.0
	defender.goals.assign([{"type": Aircraft.G_ATTACK, "targetid": later_wave.object_id}])
	defender._ai(STEP)
	_check(defender.current_goal().get("type") == Aircraft.G_EVADE and defender.current_goal().pos.x < defender.position.x,
		"Britain subclass must retain the active-goal map-edge recovery hook")
	# Same mission flag on base Aircraft must not activate the Britain-only patrol behavior.
	var legacy := Aircraft.new()
	legacy.world = world
	legacy.allied = true
	world.add_child(legacy)
	legacy.set_physics_process(false)
	legacy.set_process(false)
	legacy._free_goal()
	_check(legacy.current_goal().get("type") == Aircraft.G_WAYPOINT, "Core Aircraft must retain its original free-flight behavior")


func _test_damage() -> void:
	_fresh_world()
	for name_ in ["he111", "bf109", "spitfire"]:
		var plane := VisualAircraft.new()
		plane.world = world
		plane.plane_name = name_
		world.add_child(plane)
		plane.set_physics_process(false)
		plane.set_process(false)
		plane._damage_paths.assign(["objects/planes/%s/damaged1.gltf" % name_,
			"objects/planes/%s/damaged2.gltf" % name_, "objects/planes/%s/wreck.gltf" % name_])
		var pristine := Node3D.new()
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(10, 4, 10)
		mesh.mesh = box
		pristine.add_child(mesh)
		plane.add_child(pristine)
		plane._model = pristine
		plane._lengths_from_model(pristine)
		_check(plane.box_hit(Vector3(4, 0, -20), Vector3(4, 0, 20)), name_ + " pristine triangles must hit")
		var atoms: Array = plane.atoms.duplicate(true)
		var hit_size := plane.hit_radius_sq
		var gear := plane.gear_height
		plane.take_damage(34.0)
		_check(plane._model == pristine, name_ + " must keep pristine art below 35% damage")
		plane.take_damage(1.0)
		_check(plane.loaded_paths.size() == 1 and plane.loaded_paths.back().ends_with("damaged1.gltf"), name_ + " must swap at 35%")
		_check(plane._faces.is_empty(), name_ + " must invalidate triangle cache on model swap")
		plane.take_damage(35.0)
		_check(plane.loaded_paths.size() == 2 and plane.loaded_paths.back().ends_with("damaged2.gltf"), name_ + " must swap at 70%")
		_check(not plane.box_hit(Vector3(4, 0, -20), Vector3(4, 0, 20)), name_ + " must rebuild triangles from the damaged mesh")
		_check(plane.box_hit(Vector3(0, 0, -20), Vector3(0, 0, 20)), name_ + " damaged mesh must still collide at its centre")
		plane.take_damage(30.0)
		_check(plane.loaded_paths.size() == 3 and plane.loaded_paths.back().ends_with("wreck.gltf") and plane.falling,
			name_ + " must use the wreck when shot down")
		_check(plane._faces.is_empty() and plane.atoms == atoms and plane.hit_radius_sq == hit_size and plane.gear_height == gear,
			name_ + " stages must invalidate triangles while preserving initial bounds and atom spheres")
	# Verify real setup resolves appearance metadata through Ini, not a fixed game_data path.
	var real := BritainAircraft.new()
	world.add_child(real)
	real.setup("he111", world)
	real.set_physics_process(false)
	real.set_process(false)
	var appearance: Dictionary = Ini.load_file(Ini.data_path("objects/planes/he111/plane.ini")).get("appearance", {})
	var index := 0
	for key in ["damagedff1", "damagedff2", "deaddff"]:
		var dff := str(appearance.get(key, ""))
		var expected := "objects/planes/he111/" + dff.get_basename().to_lower() + ".gltf" if not dff.is_empty() else ""
		_check(real._damage_paths[index] == expected, "Setup must resolve " + key + " relative to the plane's INI")
		index += 1
	_check(not real.atoms.is_empty(), "Real setup must retain pristine collision atom spheres")


func _test_crashes() -> void:
	_fresh_world()
	world.water = true
	var plane = _plane("spitfire", Vector3(0, 2.01, 0))
	plane._model = Node3D.new()
	plane.add_child(plane._model)
	plane._shadow = Node3D.new()
	plane.add_child(plane._shadow)
	plane.flight_basis = Basis(Vector3.RIGHT, deg_to_rad(1.0))
	plane.pitch_rate = 5.0
	plane._ai_pitch = 5.0
	plane._fly(STEP)
	_check(plane.state == Aircraft.State.DEAD and not plane.falling and plane.crashed,
		"Gentle sea contact must crash instead of entering GROUND")
	_check(world.splashes == 1 and world.losses == 1 and plane.counts_as_lost(), "Sea crash must call world effects and count one loss")
	_check(not plane._model.visible and not plane._shadow.visible and not plane.is_processing(), "Sea crash must hide aircraft and shadow")
	_check(not world.sea_queries.is_empty() and world.sea_queries.back() is Vector3, "Sea query must use the Vector3 API")
	plane.crash()
	_check(world.splashes == 1 and world.losses == 1, "Repeated sea impact must not duplicate effects or loss")
	var falling_plane = _plane("he111")
	falling_plane.take_damage(100.0)
	_check(world.losses == 2 and falling_plane.falling, "Shot down must emit the loss while still airborne")
	falling_plane.crash()
	_check(world.losses == 2 and world.splashes == 2 and not falling_plane.crashed,
		"A shot-down sea impact must preserve shot-down credit without double counting")
	var wing_impact = _plane("he111", Vector3(0, 5, 0))
	wing_impact.take_damage(100.0)
	wing_impact.basis = Basis(Vector3.BACK, deg_to_rad(70.0))
	wing_impact._terrain_probes(Vector3(0, 10, 0))
	_check(world.losses == 3 and world.splashes == 3 and not wing_impact.falling,
		"A falling wingtip sea impact must not emit a second destruction signal")
	world.water = false
	var land_plane = _plane("bf109")
	land_plane.crash()
	_check(world.losses == 4 and world.splashes == 3 and land_plane.crashed,
		"Land crashes must preserve inherited crash counting and effects")
	_check(not world.particles._columns.is_empty(), "Land crash must still create inherited smoke column")
