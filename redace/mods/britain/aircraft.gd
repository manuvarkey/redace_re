extends Aircraft
## Britain-only aircraft. World selects this script and assigns escort_leader_id.
## Optional sea API: is_sea(Vector3) -> bool, sea_crash(Vector3) -> void (wreck + splash).

const BOMBER_BANK := 18.0
const BOMBER_PITCH := 8.0
const BOMB_HEIGHT := 350.0
const ESCORT_RANGE := 650.0
const GUNNER_RANGE := 450.0
const GUNNER_INTERVAL := 0.2

var radar_icon := ""
var escort_leader_id := 0  # Mission object ID, not Godot's instance ID.
var escort_offset := Vector3(100.0, 45.0, -140.0)  # Leader's flight_basis coordinates.
var _escort_attack: Dictionary = {}
var _escort_rest := 0.0
var _gunner_cooldown := 0.0
var _bomb_target: Variant = null
var _bomb_bearing := Vector3.ZERO
var _bomb_circuit: Array[Vector3] = []
var _circuit_gate := 160.0
var _damage_paths: Array[String] = []
var _damage_stage := 0
var _visual_ambient := 0.4
var _visual_diffuse := 1.0


func setup(name_: String, main: World) -> void:
	super.setup(name_, main)
	radar_icon = "res://mods/britain/smallbomber.png" if plane_name == "he111" else ""
	var dir := "objects/planes/%s/" % plane_name
	var app: Dictionary = Ini.load_file(Ini.data_path(dir + "plane.ini")).get("appearance", {})
	_visual_ambient = Ini.num(app, "ambient", 0.4)
	_visual_diffuse = Ini.num(app, "diffuse", 1.0)
	_damage_paths.clear()
	for key in ["damagedff1", "damagedff2", "deaddff"]:
		var dff := str(app.get(key, ""))
		_damage_paths.append(dir + dff.get_basename().to_lower() + ".gltf" if not dff.is_empty() else "")


func _wwii() -> bool:
	return plane_name in ["he111", "bf109", "spitfire"]


func _ai(dt: float) -> void:
	if world.require_shot_down and not hidden and int(current_goal().get("type", 0)) != G_EVADE \
			and not _left_the_map():
		_edge_of_battle()
	if plane_name != "bf109" or allied or escort_leader_id <= 0:
		super._ai(dt)
		if allied and plane_name == "spitfire" and (not is_player or autopilot) and not hidden and state == State.FLYING:
			_guard_coastal_cliffs()
		return
	fire_input = false
	secondary_input = false
	_ai_pitch = NAN
	if _left_the_map():
		return
	_script_goal(current_goal(), dt)
	if hidden or int(current_goal().get("type", 0)) in [G_WAIT_TIME, G_WAIT_NEAR]:
		return
	var leader = world.object_for_goal(escort_leader_id, self)
	if not (leader is Aircraft) or not leader.present() or leader.allied != allied:
		_escort_attack.clear()
		super._ai(dt)  # A lost leader leaves the escort's original mission goals intact.
		return
	_escort_rest = maxf(0.0, _escort_rest - dt)
	var threat: Aircraft = null
	var closest := ESCORT_RANGE * ESCORT_RANGE
	for candidate in world.planes:
		if candidate == self or candidate.allied == allied or not candidate.present():
			continue
		# Defend the bomber even when the escort is on the far side of its formation.
		var distance := minf(global_position.distance_squared_to(candidate.global_position),
			leader.global_position.distance_squared_to(candidate.global_position))
		if distance <= closest:
			closest = distance
			threat = candidate
	if threat != null and _escort_rest <= 0.0:
		if int(_escort_attack.get("targetid", 0)) != threat.object_id:
			_escort_attack = {"type": G_ATTACK, "targetid": threat.object_id}
		if not _attack(_escort_attack, dt):
			_avoid_terrain()
			return
		_escort_rest = 3.0  # Honour the inherited damage/time disengagement before reacquiring.
	_escort_attack.clear()
	fire_input = false
	var station: Vector3 = leader.global_position + leader.flight_basis * escort_offset
	# Match physical forward speed (Aircraft moves at speed^2 / high_speed), with station error feedback.
	var lead_speed: float = leader.speed * leader.speed / leader.high_speed
	# Aim ahead along the bomber's bearing so arriving at the slot does not trigger
	# a turn back toward a point now behind the fighter.
	_steer(station + leader.flight_basis.z * maxf(lead_speed * 3.0, 180.0))
	_avoid_terrain()
	# Compensate the inherited fixed pitch-rate decay only while holding formation.
	_ai_pitch += 5.0 if _ai_pitch >= 0.0 else -5.0
	var along: float = (station - global_position).dot(leader.flight_basis.z)
	var desired := sqrt(maxf(0.0, lead_speed + along * 0.25) * high_speed)
	desired = clampf(desired, stall_speed + 8.0, high_speed)
	throttle = asin(clampf(desired / high_speed, 0.0, 1.0)) / 1.57


func _guard_coastal_cliffs() -> void:
	# The original single downward ray reports zero when a cliff is above its start.
	# Sample the path farther ahead and climb before the nose reaches that wall.
	var forward := Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized()
	var travel := maxf(velocity.length(), speed * speed / high_speed)
	for seconds: float in [2.0, 4.0, 6.0]:
		var probe: Vector3 = global_position + forward * travel * seconds
		var floor := world.ground_height(probe)
		var projected: float = global_position.y + velocity.y * seconds
		if floor + 135.0 > projected:
			_ai_pitch = maxf(_ai_pitch if not is_nan(_ai_pitch) else 0.0, 35.0 if seconds <= 2.0 else 25.0)
			_ai_bank = 0.0
			throttle = 1.0
			return


func _steer(aim: Vector3) -> void:
	if plane_name != "he111":
		super._steer(aim)
		return
	var flat := aim - global_position
	flat.y = 0.0
	var forward := Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized()
	var turn := forward.signed_angle_to(flat.normalized(), Vector3.UP) if flat.length_squared() > 1.0 else 0.0
	_ai_bank = clampf(-rad_to_deg(turn) * 0.8, -BOMBER_BANK, BOMBER_BANK)
	var wanted_pitch := clampf((aim.y - global_position.y) * 0.12, -BOMBER_PITCH, BOMBER_PITCH)
	_ai_pitch = clampf((wanted_pitch - rad_to_deg(asin(clampf(flight_basis.z.y, -1.0, 1.0)))) * 1.5, -4.0, 4.0)


func _apply_ai_commands() -> void:
	if plane_name == "he111" and state != State.DEAD:
		# Includes mission evades, formation, takeoff and any inherited command source.
		_ai_bank = clampf(_ai_bank, -BOMBER_BANK, BOMBER_BANK)
		_last_ai_bank = clampf(_last_ai_bank, -BOMBER_BANK, BOMBER_BANK)
		if not is_nan(_ai_pitch):
			_ai_pitch = clampf(_ai_pitch, -4.0, 4.0)
	super._apply_ai_commands()


func _fly(dt: float) -> void:
	if not _wwii():
		super._fly(dt)
		return
	if plane_name == "he111" and state != State.DEAD and state != State.GROUND:
		_limit_bomber_attitude()
		boost = false
		throttle = asin(clampf(cruise_speed / high_speed, 0.0, 1.0)) / 1.57
		var pitch := rad_to_deg(asin(clampf(flight_basis.z.y, -1.0, 1.0)))
		var rate := clampf(pitch_rate, -4.0, 4.0)
		if dt > 0.0:
			rate = clampf(rate, (-BOMBER_PITCH - pitch) / dt, (BOMBER_PITCH - pitch) / dt)
		# Cancel Aircraft's per-step +/-5 rate decay; otherwise small AI commands reverse direction.
		pitch_rate = rate + (5.0 if rate >= 0.0 else -5.0)
		_ai_pitch = pitch_rate
		_rate_set = true
	var actual_alt := ahead_alt
	ahead_alt = minf(ahead_alt, 400.0)
	super._fly(dt)
	# super updates this normally, but can return early on impact. Never expose the speed workaround to AI.
	ahead_alt = actual_alt
	if state != State.DEAD or falling:
		_update_ahead_alt()
	if plane_name == "he111" and state != State.DEAD and state != State.GROUND:
		_limit_bomber_attitude()
	# The inherited gentle-contact branch lands on water. Convert that contact to a crash as well.
	if (state != State.DEAD or falling) and _over_sea(global_position) \
			and global_position.y <= world.ground_height(global_position) + gear_height + 0.1:
		crash()


func _limit_bomber_attitude() -> void:
	bank = clampf(bank, -BOMBER_BANK, BOMBER_BANK)
	var heading := Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized()
	if heading.is_zero_approx():
		heading = Vector3.BACK
	var pitch := clampf(asin(clampf(flight_basis.z.y, -1.0, 1.0)), -deg_to_rad(BOMBER_PITCH), deg_to_rad(BOMBER_PITCH))
	flight_basis = Basis.looking_at(-heading, Vector3.UP) * Basis(Vector3.RIGHT, -pitch)
	basis = flight_basis * Basis(Vector3.BACK, deg_to_rad(bank))


func on_hit(attacker) -> void:
	if plane_name != "he111":
		super.on_hit(attacker)
	# Bomber gunners defend it; its pilot keeps the bombing bearing instead of pushing a fighter evade.


func _edge_of_battle() -> void:
	if plane_name == "he111" and int(current_goal().get("type", 0)) in [G_BOMB_RUN, G_DIVE_ATTACK, G_ATTACK]:
		return
	super._edge_of_battle()


func _free_goal() -> void:
	# Britain defenders use short patrol legs so later, initially hidden waves are acquired promptly.
	if world.require_shot_down and allied:
		var raider := world.nearest_enemy(self)
		if raider:
			_push_goal({"type": G_ATTACK, "targetid": raider.object_id, "pos": Vector3.ZERO, "radius": 0.0})
		else:
			_push_goal({"type": G_EVADE, "targetid": 0, "pos": world.map_center(260.0), "radius": 3.0})
		return
	super._free_goal()


func _attack(goal: Dictionary, dt: float) -> bool:
	return _bomb_run(goal) if plane_name == "he111" else super._attack(goal, dt)


func _dive_attack(goal: Dictionary) -> bool:
	return _bomb_run(goal) if plane_name == "he111" else super._dive_attack(goal)


func _bomb_run(goal: Dictionary) -> bool:
	if plane_name != "he111":
		return super._bomb_run(goal)
	fire_input = false
	secondary_input = false
	var target = _goal_object(goal)
	if target == null or target is Aircraft:
		return true
	var tp := _obj_pos(target)
	var to := tp - global_position
	to.y = 0.0
	if _bomb_target != target:
		_bomb_target = target
		_bomb_bearing = to.normalized() if to.length_squared() > 1.0 else Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized()
		_bomb_circuit.clear()
		if flight_basis.z.dot(_bomb_bearing) < 0.95 or to.length() < 650.0:
			_start_circuit(tp)
	var height := tp.y + BOMB_HEIGHT
	if not _bomb_circuit.is_empty():
		var waypoint := _bomb_circuit[0]
		waypoint.y = height
		_steer(waypoint)
		_avoid_terrain()
		var horizontal := waypoint - global_position
		horizontal.y = 0.0
		if horizontal.length() < _circuit_gate:
			_bomb_circuit.pop_front()
		return false
	# Track a fixed approach line with a lookahead, rather than chasing the target's bearing overhead.
	var along := to.dot(_bomb_bearing)
	var on_line := tp - _bomb_bearing * along
	var aim := on_line + _bomb_bearing * 650.0
	aim.y = height
	_steer(aim)
	_avoid_terrain()
	var impact := _bomb_impact(tp.y)
	var error := Vector2(impact.x - tp.x, impact.z - tp.z).length()
	var agl := global_position.y - tp.y
	secondary_input = ordnance_type == 1 and ordnance_left > 0 and agl >= 300.0 and agl <= 400.0 \
		and flight_basis.z.dot(_bomb_bearing) > 0.98 and absf(bank) < 5.0 and error <= 25.0
	# Missed releases and empty bomb racks both fly another circuit; never change the goal to guns.
	if along < -180.0:
		_start_circuit(tp)
	return false


func _bomb_impact(target_y: float) -> Vector3:
	# Match _guns' release point and spawn_ordnance's initial velocity, including an INI release impulse.
	var origin := global_position - global_transform.basis.y * 2.0
	var bomb: Dictionary = world.ordnance.get(2, {})
	var launch := velocity + velocity.normalized() * Ini.num(bomb, "releasespeed", 0.0)
	var height := maxf(origin.y - target_y, 0.0)
	var time := (launch.y + sqrt(launch.y * launch.y + 2.0 * World.BOMB_GRAVITY * height)) / World.BOMB_GRAVITY
	return origin + launch * time + Vector3.DOWN * (0.5 * World.BOMB_GRAVITY * time * time)


func _start_circuit(tp: Vector3) -> void:
	var side := _bomb_bearing.cross(Vector3.UP)
	var center := Vector3(world.map_bounds.get_center().x, tp.y, world.map_bounds.get_center().y)
	if side.dot(center - tp) < 0.0:
		side = -side
	# Size the circuit for the INI roll rate: a bomber cannot make fighter-sized corners.
	var roll := lerpf(low_roll, high_roll, clampf(cruise_speed / high_speed, 0.0, 1.5))
	var turn_speed := deg_to_rad(sin(deg_to_rad(BOMBER_BANK)) * roll)
	var turn_radius := maxf(250.0, cruise_speed * cruise_speed / high_speed / maxf(turn_speed, 0.01))
	var runout := maxf(750.0, turn_radius * 1.5)
	# Leave a full turn diameter plus a straight settling leg before bomb release.
	var behind := maxf(1800.0, turn_radius * 4.0)
	var width := turn_radius * 3.2
	_circuit_gate = maxf(160.0, turn_radius * 0.65)
	_bomb_circuit.assign([tp + _bomb_bearing * runout,
		tp + _bomb_bearing * runout + side * width,
		tp - _bomb_bearing * behind + side * width,
		tp - _bomb_bearing * behind])


func _guns(dt: float) -> void:
	if _wwii() and (state == State.DEAD or hidden):
		_gun_sound_firing(false)
		return
	if plane_name != "he111":
		super._guns(dt)
		return
	fire_input = false  # There are no pilot-operated forward guns, even for inherited attack goals.
	super._guns(dt)  # Bomb ammunition, cooldown and sound remain owned by Aircraft.
	_gunner_cooldown = maxf(0.0, _gunner_cooldown - dt)
	if state == State.GROUND or _gunner_cooldown > 0.0:
		return
	var shot := _gunner_shot()
	if shot.is_empty():
		return
	world.spawn_ordnance(self, 1, shot.origin, velocity, shot.direction)
	_gunner_cooldown = GUNNER_INTERVAL
	_gun_sound_firing(true)


func _gunner_shot() -> Dictionary:
	var best := {}
	var closest := GUNNER_RANGE * GUNNER_RANGE
	var frame := global_transform.basis.orthonormalized()
	var bullet_speed := Ini.num(world.ordnance.get(1, {}), "releasespeed", 250.0)
	for enemy in world.planes:
		if enemy == self or enemy.allied == allied or not enemy.present():
			continue
		var to := enemy.global_position - global_position
		var distance := to.length_squared()
		if distance < 30.0 * 30.0 or distance > closest:
			continue
		var aim := to + (enemy.velocity - velocity) * (sqrt(distance) / maxf(bullet_speed, 1.0))
		var local := frame.inverse() * aim.normalized()
		var origin: Vector3
		if local.z < -0.65 and local.y > -0.15 and local.y < 0.7:
			origin = global_position - frame.z * (back_length + 1.0) + frame.y * up_length
		elif local.y > 0.35 and local.z < 0.35:
			origin = global_position + frame.y * (up_length + 1.0)
		else:
			continue  # Forward, low and wing-level broadside sectors are masked by the airframe.
		var end := global_position + aim
		if world.ground_hit_fraction(origin, end) > 0.0:
			continue
		var safe := true
		for friend in world.planes:
			if friend == self or friend.allied != allied or not friend.present():
				continue
			var near := Geometry3D.get_closest_point_to_segment(friend.global_position, origin, end)
			if near.distance_to(friend.global_position) < friend.radius + 3.0:
				safe = false
				break
		if safe:
			closest = distance
			best = {"origin": origin, "direction": (end - origin).normalized()}
	return best


func take_damage(amount: float, attacker = null) -> void:
	super.take_damage(amount, attacker)
	_update_damage_model()


func _shot_down() -> void:
	super._shot_down()
	_update_damage_model()


func _terrain_probes(prev: Vector3) -> void:
	if _wwii() and state == State.DEAD and falling:
		# Aircraft's wing probe emits destroyed even for an already shot-down plane. Finish its impact once.
		var frame := global_transform.basis
		for tip in [global_position + frame.z * front_length, global_position + frame.x * port_length,
				global_position - frame.x * starboard_length]:
			if world.ground_hit_fraction(prev, tip) > 0.0:
				crash()
				return
		return
	super._terrain_probes(prev)


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	_update_damage_model()  # Includes terrain probe deaths and externally adjusted health.


func _update_damage_model() -> void:
	if not _wwii():
		return
	var damage := 1.0 - health / maxf(endurance, 0.001)
	var stage := 3 if state == State.DEAD else (2 if damage >= 0.7 else (1 if damage >= 0.35 else 0))
	if stage <= _damage_stage:
		return
	_damage_stage = stage
	if _damage_paths.size() < stage or _damage_paths[stage - 1].is_empty():
		return
	var replacement := _load_damage_model(_damage_paths[stage - 1])
	if replacement == null:
		return  # Missing optional art must not break flight or collision geometry.
	World.apply_lighting(replacement, _visual_ambient, _visual_diffuse)
	var show_model := _model == null or _model.visible
	if _model:
		_model.visible = false
		_model.queue_free()
	_propellers.clear()
	# Bounds/atom spheres remain from setup; triangle hits rebuild lazily from the current visible mesh.
	_faces.clear()
	_model = replacement
	add_child(_model)
	_model.visible = show_model
	_find_propellers(_model)


func _load_damage_model(path: String) -> Node3D:
	return World.load_model(path) if ResourceLoader.exists(Ini.data_path(path)) else null


func _over_sea(pos: Vector3) -> bool:
	return world.has_method("is_sea") and bool(world.call("is_sea", pos))


func crash() -> void:
	if state == State.DEAD and not falling:
		return
	if not _wwii() or not _over_sea(global_position):
		super.crash()
		_update_damage_model()
		return
	var was_alive := state != State.DEAD
	state = State.DEAD
	falling = false
	crashed = was_alive
	health = 0.0
	_update_damage_model()
	if _model:
		_model.hide()
	if _shadow:
		_shadow.hide()
	if _engine_sound:
		_engine_sound.stop()
	_gun_sound_firing(false)
	if world.has_method("sea_crash"):
		world.call("sea_crash", global_position)
	if was_alive:
		destroyed.emit(self)  # Falling planes have already emitted this in _shot_down.
	set_physics_process(false)
	set_process(false)  # Do not let _place_shadow reveal the shadow again.
