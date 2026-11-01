class_name Aircraft
extends Node3D
## One aircraft. Flight model follows the original RedAce.exe plane update (decomp/RedAce.c:32540):
##   target speed = sin(throttle * 1.57) * highspeed, pulled toward climbspeed when climbing
##   and toward divespeed when diving; speed rises by accel per second and is capped by the target.
##   velocity = forward * speed^2 / highspeed + up * speed^2 * mass * 10 / cruisespeed^2 - world_up * mass * 10
##   roll/pitch rates interpolate low..high with speed / highspeed; below stallspeed the lift is lost.
## Attitude follows the original rotations (decomp RedAce.c FUN_00432a5f, asm 0x4343a6..0x434440):
##   the flight frame M never rolls; the plane is drawn as M rotated by the bank angle about forward.
##   M pitches about its wing axis by pitch_rate * dt and yaws about world up by sin(bank) * rollrate * dt.
##   bank is limited to +-90 while upright; when M is inverted, passing +-90 flips M by 180 (roll out).
##   pitch_rate decays by 5 deg/s per frame (150 deg/s^2 at the original 30 fps) and is clamped to the pitch rate.
## Guns follow the original burst logic (decomp/RedAce.c:31605): firerate rounds per second while
## the trigger has been held for less than fireon seconds, then a pause of fireoff seconds.
## Model axes follow RenderWare: basis.z = forward ("at"), basis.y = up, basis.x = left wing.

enum State { FLYING, STALL, GROUND, DEAD }

signal destroyed(plane: Aircraft)

var plane_name := ""
var object_id := 0
var groups := 0
var is_player := false
var autopilot := false  # debug: player aircraft flown by the AI (--autopilot)
var allied := false
var endurance := 100.0
var health := 100.0
var radius := 8.0
var atoms := []  # bounding sphere of each atomic, plane space (blasts, FUN_0044cf81)
var hit_radius_sq := 64.0  # rounds hit inside this: back length * starboard length (FUN_0044d311)
var proximity_groups := 0  # how many of groups 4, 8, 9 the plane is in
var left_map := false  # flew 150 past the world box (0x439046)

var mass := 0.3
var accel := 20.0
var dive_speed := 128.0
var high_speed := 118.0
var cruise_speed := 105.0
var climb_speed := 108.0
var stall_speed := 80.0
var high_roll := 105.0
var low_roll := 90.0
var high_pitch := 110.0
var low_pitch := 100.0
var fire_rate := 50.0
var fire_on := 0.75
var fire_off := 0.15
var down_length := 2.0
var gear_height := 2.0  # ground contact (model bounds)
var tail_length := 5.0
var back_length := 5.0
var front_length := 5.0
var port_length := 8.0
var starboard_length := 8.0
var up_length := 2.0

var speed := 0.0
var throttle := 0.8
var boost := false
var state := State.FLYING
var velocity := Vector3.ZERO

# flight frame (no roll), bank angle in degrees (+ = right wing down), pitch rate in deg/s (+ = nose up)
var flight_basis := Basis.IDENTITY
var bank := 0.0
var pitch_rate := 0.0

var fire_input := false
var secondary_input := false

var ordnance_type := 0  # mission ordinancetype: 1 = bombs, 2 = rockets (ordinance.ini entry type + 1)
var ordnance_left := 0
var goals: Array[Dictionary] = []
var goal_index := 0

var world: World = null

var hidden := false  # removed from the world by a script goal (original pilot flag 0x420)
var retaliate := false  # goal 0x130 on / 0x140 off: when hit, attack the attacker instead of evading
var crashed := false  # true when the plane hit the ground rather than being shot down
var _first_frame := true
var _trigger_time := 0.0
var _shots := 0.0
var _secondary_cooldown := 0.0
var _propellers: Array[Node3D] = []
var _prop_angle := 0.0
var _engine_sound: AudioStreamPlayer3D
var _gun_sound: AudioStreamPlayer3D
var _hit_sound: AudioStream
var _alt_hit_sound: AudioStream
var falling := false  # shot down: spinning toward the ground (original state 2)
var _smoke_puff := 0.0  # extra smoke after each hit, decays 3.5/s (original offset 0x1c8)
var _smoke_timer := 0.0
var _blast_sound: AudioStream
var _hit_sound_time := -1.0
var _model: Node3D
var _faces := PackedVector3Array()  # clump triangles in this node's space, for collisions
var _rocket_sound: AudioStream
var _shadow: Node3D
var _bomb_sound: AudioStream


func setup(name_: String, main: World) -> void:
	plane_name = name_.to_lower()
	world = main
	var dir := "objects/planes/%s/" % plane_name
	var ini := Ini.load_file(Ini.data_path(dir + "plane.ini"))
	var ph: Dictionary = ini.get("physics", {})
	mass = Ini.num(ph, "mass", mass)
	accel = Ini.num(ph, "accel", accel)
	dive_speed = Ini.num(ph, "divespeed", dive_speed)
	high_speed = Ini.num(ph, "highspeed", high_speed)
	cruise_speed = Ini.num(ph, "cruisespeed", cruise_speed)
	climb_speed = Ini.num(ph, "climbspeed", climb_speed)
	stall_speed = Ini.num(ph, "stallspeed", stall_speed)
	high_roll = Ini.num(ph, "highroll", high_roll)
	low_roll = Ini.num(ph, "lowroll", low_roll)
	high_pitch = Ini.num(ph, "highpitch", high_pitch)
	low_pitch = Ini.num(ph, "lowpitch", low_pitch)
	var col: Dictionary = ini.get("collision", {})
	radius = maxf(Ini.num(col, "portlength", 8.0), Ini.num(col, "backlength", 5.0))
	down_length = Ini.num(col, "downlength", 2.0)
	back_length = Ini.num(col, "backlength", 5.0)
	front_length = Ini.num(col, "frontlength", 5.0)
	port_length = Ini.num(col, "portlength", 8.0)
	starboard_length = Ini.num(col, "starboardlength", 8.0)
	up_length = Ini.num(col, "uplength", 2.0)
	var arm: Dictionary = ini.get("armaments", {})
	endurance = Ini.num(arm, "endurance", 100.0)
	fire_rate = Ini.num(arm, "firerate", 10.0)
	fire_on = Ini.num(arm, "fireon", 1.0)
	fire_off = Ini.num(arm, "fireoff", 0.0)
	health = endurance

	var app: Dictionary = ini.get("appearance", {})
	var dff: String = app.get("dff", plane_name + ".dff")
	var model := World.load_model(dir + dff.get_basename() + ".gltf")
	if model:
		World.apply_lighting(model, Ini.num(app, "ambient", 0.4), Ini.num(app, "diffuse", 1.0))
		add_child(model)
		_model = model
		_find_propellers(model)
		_lengths_from_model(model)
	# [appearance] shadow = <plane>shadow.dff: a dark clump laid flat on the ground under the plane
	var shadow_dff: String = str(app.get("shadow", ""))
	if shadow_dff != "":
		_shadow = World.load_model(dir + shadow_dff.get_basename().to_lower() + ".gltf")
		if _shadow:
			_shadow.top_level = true
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0.19, 0.19, 0.19)  # the clump's material colour
			for mi in _shadow.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = mat
				(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(_shadow)

	var snd: Dictionary = ini.get("sound", {})
	_engine_sound = _make_player(World.load_sound(snd.get("engine", "")), 40.0)
	_gun_sound = _make_player(World.load_sound(snd.get("machinegun", "")), 30.0)
	_hit_sound = World.load_sound(snd.get("hitsound", ""))
	_alt_hit_sound = World.load_sound(snd.get("althitsound", ""))
	_blast_sound = World.load_sound(snd.get("explosion", "planecrash.wav"))
	_rocket_sound = World.load_sound(snd.get("rocket", "rocket.wav"))
	_bomb_sound = World.load_sound(snd.get("bomb", "bombhatch.wav"))
	speed = cruise_speed


## Gear height and tail length from the clump's vertex bounds (decomp FUN_0042e91a, RedAce.c:30730:
## every atomic's untransformed vertices; the exe replaces all six [collision] lengths with them):
## down = -min y (the wheels), back = -min z. Parked, the plane sits down + 0.05 above the ground, nose up
## by atan(down / back), which rests it on wheels and tail skid. Deviation: the collision probes keep the
## plane.ini lengths; with the exe's wingspan-sized probes the remake's formations kept colliding.
func _lengths_from_model(model: Node3D) -> void:
	var lo := Vector3(INF, INF, INF)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		lo = lo.min((mi as MeshInstance3D).get_aabb().position)
	if lo.is_finite():
		gear_height = -lo.y
		tail_length = -lo.z
	_read_atoms(model)


## Atomic spheres and the clump box, which replaces plane.ini's [collision] lengths in the exe
## (0x42e7c8). Computed once per model file.
static var _geometry_cache := {}
func _read_atoms(model: Node3D) -> void:
	if not _geometry_cache.has(plane_name):
		var list := []
		var box := AABB()
		var first := true
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var xf: Transform3D = (mi as MeshInstance3D).transform
			var n: Node = (mi as Node).get_parent()
			while n != model:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			xf = model.transform * xf
			var own := PackedVector3Array()
			for v in (mi as MeshInstance3D).mesh.get_faces():
				own.append(xf * v)
			if own.is_empty():
				continue
			list.append(World.sphere_of(own))
			for v in own:
				box = AABB(v, Vector3.ZERO) if first else box.expand(v)
				first = false
		_geometry_cache[plane_name] = {"atoms": list,
			"hit": maxf(-box.position.z, 0.0) * maxf(box.end.x, 0.0)}
	atoms = _geometry_cache[plane_name].atoms
	hit_radius_sq = _geometry_cache[plane_name].hit


## Propeller = the atomic textured "soppropeller"; its RenderWare frame is spun about forward.
func _find_propellers(model: Node3D) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat and mat.resource_name.to_lower().begins_with("soppropeller"):
				_propellers.append(mi as Node3D)
				break


func place(t: Transform3D) -> void:
	flight_basis = t.basis.orthonormalized()
	bank = 0.0
	global_transform = t


func _make_player(stream: AudioStream, unit: float) -> AudioStreamPlayer3D:
	if stream == null:
		return null
	var a := AudioStreamPlayer3D.new()
	a.stream = stream
	a.unit_size = unit
	a.bus = "Effects"
	add_child(a)
	return a


func _process(_dt: float) -> void:
	if not hidden and not _first_frame:
		_place_shadow()


func _physics_process(dt: float) -> void:
	if state == State.DEAD:
		if falling:
			_fall(dt)
			_damage_smoke(dt)
		return
	if _first_frame:
		# terrain collision exists only from the first physics frame on
		_first_frame = false
		# every aircraft, the player's too, is created parked in its ground state (decomp FUN_0042cec1,
		# state 4, speed 0) at its mission position; its script goals then move it (0x100 puts it in the air)
		state = State.GROUND
		speed = 0.0
		throttle = 0.0
	if not is_player or autopilot:
		_ai(dt)
		_apply_ai_commands()
	else:
		_player_script()
	if hidden:
		if _engine_sound and _engine_sound.playing:
			_engine_sound.stop()
		return
	var prev := global_position
	_fly(dt)
	if state != State.DEAD:
		world.collide(self, prev, dt)
	if state != State.DEAD and state != State.GROUND:
		_terrain_probes(prev)
	_guns(dt)
	_damage_smoke(dt)
	if _engine_sound:
		_engine_sound.pitch_scale = clampf(0.6 + speed / high_speed * 0.6, 0.5, 2.0)
		if not _engine_sound.playing:
			_engine_sound.play()


func _fly(dt: float) -> void:
	var m := flight_basis
	var fwd := m.z
	var k := clampf(speed / high_speed, 0.0, 1.5)
	var roll_lerp := lerpf(low_roll, high_roll, k)
	var pitch_lerp := lerpf(low_pitch, high_pitch, k)

	# target speed from throttle and attitude (original formula)
	var target_speed := sin(throttle * 1.57) * high_speed
	if fwd.y >= 0.0:
		target_speed -= (target_speed - climb_speed) * fwd.y
	else:
		target_speed -= (dive_speed - target_speed) * fwd.y
	if boost:
		target_speed *= 1.2
	var alt := world.height_above_ground(global_position)
	if alt > 400.0:
		target_speed -= (alt - 400.0) * 0.5
	speed = minf(speed + dt * accel, target_speed)
	if speed < 0.0:
		speed = high_speed

	if state == State.GROUND:
		speed = minf(speed + dt * accel * 2.0, target_speed)
		bank = 0.0
		if speed > (stall_speed + cruise_speed) * 0.5 and pitch_rate > 20.0:
			state = State.FLYING
	elif speed < stall_speed:
		state = State.STALL
	elif state == State.STALL:
		state = State.FLYING

	if state != State.GROUND:
		if state == State.STALL:
			bank -= 150.0 * dt  # the original rolls off and drops the nose in a stall
			pitch_rate -= m.y.y * 100.0 * 30.0 * dt
		# Each frame the rate loses 5 toward zero whatever the frame time, and may overshoot it (0x433ce6). An AI
		# plane sets its command again each frame, so a small command turns the other way, which settles it on
		# one edge of a +-5 band instead of on the aim line. The player's input integrates, so it keeps a rate.
		if (is_player and not autopilot) or is_nan(_ai_pitch):
			pitch_rate = move_toward(pitch_rate, 0.0, 150.0 * dt)
		else:
			pitch_rate -= 5.0 if pitch_rate > 0.0 else -5.0
		pitch_rate = clampf(pitch_rate, -pitch_lerp, pitch_lerp)
		# bank limits and roll-out from inverted flight
		if m.y.y > 0.0:
			bank = clampf(bank, -90.0, 90.0)
		elif absf(bank) > 90.0:
			bank -= 180.0 * signf(bank)
			m = m * Basis(Vector3.BACK, PI)
		# pitch about the wing axis (nose up = rotation about local x by -angle)
		m = m * Basis(Vector3.RIGHT, -deg_to_rad(pitch_rate * dt))
		# bank-driven turn about world up (right bank turns right = toward -x)
		var up_sign := 1.0 if m.y.y > 0.0 else -1.0
		m = Basis(Vector3.UP, -deg_to_rad(sin(deg_to_rad(bank)) * roll_lerp * up_sign * dt)) * m
		# keep the wing axis horizontal: M carries no roll
		var x := Vector3(m.x.x, 0.0, m.x.z)
		if x.length_squared() > 1e-6:
			x = x.normalized()
			var y := m.z.cross(x).normalized()
			m = Basis(x, y, x.cross(y).normalized())

	var visual := m * Basis(Vector3.BACK, deg_to_rad(bank))
	fwd = m.z
	velocity = fwd * (speed * speed / high_speed)
	if state == State.FLYING:
		velocity += visual.y * (speed * speed * mass * 10.0 / (cruise_speed * cruise_speed))
	if state != State.GROUND:
		velocity += Vector3.DOWN * mass * 10.0

	var pos := global_position + velocity * dt
	var ground := world.ground_height(pos)
	if state == State.GROUND:
		# hit point + normal * (down + 0.05) (RedAce.c:32176), the plane following the ground's slope
		var n := world.ground_normal(pos)
		pos.y = ground + (gear_height + 0.05) / maxf(n.y, 0.5)
		var flat := Vector3(fwd.x, 0, fwd.z).normalized()
		m = Basis.looking_at(-flat, Vector3.UP)  # flight stays level: no roll carried into the take-off
		var along := (flat - n * flat.dot(n)).normalized()
		pitch_rate = clampf(pitch_rate, 0.0, 30.0)
		# tail-dragger: parked nose up by atan(down / back) (original state 4),
		# the tail lifts as the plane gathers speed
		var tail := atan2(gear_height, tail_length) * (1.0 - clampf(speed / stall_speed, 0.0, 1.0))
		visual = Basis.looking_at(-along, n) * Basis(Vector3.RIGHT, -tail)
	elif pos.y - ground < gear_height:
		# the down probe (gear height along -up) meets the ground: wheels touch
		pos.y = ground + gear_height + 0.05
		flight_basis = m
		global_transform = Transform3D(visual, pos)
		# original ground contact (RedAce.c:32150): sinking faster than 10 or too fast -> crash,
		# a gentle touch-down (sinking under 5, wings near level) lands the plane
		if -velocity.y < 5.0 and speed <= high_speed and absf(bank) < 20.0 and m.z.y > -0.2:
			state = State.GROUND
		else:
			crash()
		return
	flight_basis = m
	global_transform = Transform3D(visual, pos)

	# propellers spin with the throttle (strobe like the original's per-frame rotation)
	_prop_angle = fmod(_prop_angle + (8.0 + throttle * 30.0) * TAU * dt, TAU)
	for p in _propellers:
		p.transform.basis = Basis(Vector3.BACK, _prop_angle)


## Player mouse input in mickeys this frame, original formulas (decomp FUN_004322de, control type 2):
##   bank += (s_roll * 0.25 + 0.025) * dt * highroll * dx;  pitch_rate += (s_pitch * 2.5 + 0.25) * dt * highpitch * dy
## dt is the original frame time; REF_DT fixes it at the original 30 fps so feel is independent of our frame rate.
const REF_DT := 1.0 / 30.0


func mouse_control(dx: float, dy: float, s_roll: float, s_pitch: float) -> void:
	var up_sign := 1.0 if flight_basis.y.y > 0.0 else -1.0
	bank += (s_roll * 0.25 + 0.025) * REF_DT * high_roll * dx * up_sign
	pitch_rate += (s_pitch * 2.5 + 0.25) * REF_DT * high_pitch * dy


## Player keyboard input (control type 1): -1/0/1 per axis. Releasing roll levels the wings at highroll deg/s.
func key_control(roll_axis: float, pitch_axis: float, s_roll: float, s_pitch: float, dt: float) -> void:
	key_roll(roll_axis, s_roll, dt)
	key_pitch(pitch_axis, s_pitch, dt)


func key_roll(axis: float, s: float, dt: float) -> void:
	var up_sign := 1.0 if flight_basis.y.y > 0.0 else -1.0
	if axis != 0.0:
		bank += axis * (s + 0.1) * high_roll * 7.0 * dt * up_sign
	elif absf(bank) < 0.5:
		bank = 0.0
	else:
		bank = move_toward(bank, 0.0, high_roll * dt)


func key_pitch(axis: float, s: float, dt: float) -> void:
	if axis != 0.0:
		pitch_rate += axis * (s + 0.1) * high_pitch * 100.0 * dt


## Joystick (control type 5): the stick sets the bank directly (value * s * 200) and the pitch rate
## (value * s * 300 * frame time * highpitch).
func joy_roll(v: float, s: float) -> void:
	var up_sign := 1.0 if flight_basis.y.y > 0.0 else -1.0
	bank = v * s * 200.0 * up_sign


func joy_pitch(v: float, s: float, _dt: float) -> void:
	pitch_rate = v * s * 300.0 * REF_DT * high_pitch


func _guns(dt: float) -> void:
	_secondary_cooldown -= dt
	if secondary_input and _secondary_cooldown <= 0.0 and ordnance_left > 0 and state != State.GROUND:
		_secondary_cooldown = 0.5
		if not (is_player and world.cheat_infinite):
			ordnance_left -= 1
		var b := global_transform.basis
		world.spawn_ordnance(self, ordnance_type + 1, global_position - b.y * 2.0, velocity)
		# plane.ini [sound] bomb = bombhatch.wav, rocket = rocket.wav (RedAce.c:30615)
		world.play_at(global_position, _bomb_sound if ordnance_type == 1 else _rocket_sound)

	if not fire_input or state == State.GROUND:
		# the burst clock only runs with the trigger held and is never reset (0x430444)
		_gun_sound_firing(false)
		return
	var cycle := fire_on + fire_off
	var phase := fmod(_trigger_time, cycle) if cycle > 0.0 else 0.0
	_trigger_time += dt
	if phase >= fire_on:
		_gun_sound_firing(false)
		return
	_gun_sound_firing(true)
	_shots += dt * fire_rate
	var b := global_transform.basis
	while _shots >= 1.0:
		_shots -= 1.0
		# from the plane's centre, along its nose (0x430598)
		world.spawn_ordnance(self, 1, global_position, velocity, b.z)


## Gun sound as the exe drives it each frame (RedAce.c:32021, FUN_0045f51e / FUN_0045f591): while the
## guns fire the sample is restarted whenever it is not playing, otherwise it is stopped at once.
func _gun_sound_firing(firing: bool) -> void:
	if _gun_sound == null:
		return
	if firing and not _gun_sound.playing:
		_gun_sound.play()
	elif not firing and _gun_sound.playing:
		_gun_sound.stop()


## Original plane damage (decomp FUN_0042eda0): damage accumulates; every hit adds smoke
## (damage * 25 / endurance), plays hitsound or althitsound at random and throws a cloth particle.
## At endurance the plane explodes in the air (burst, explosion sound) and spins down (state 2).
func take_damage(amount: float, attacker = null) -> void:
	if state == State.DEAD or (is_player and world.cheat_invulnerable):
		return
	health -= amount
	if health > 0.0:
		on_hit(attacker)
	_smoke_puff += amount * (5.0 / endurance) * 5.0
	if health > 0.0:
		# FUN_0042eda0: hit or alt hit sound, a cloth scrap, the 0.25 s red flash
		var snd := _hit_sound if randi() % 2 == 1 or _alt_hit_sound == null else _alt_hit_sound
		if snd and world.mission_time - _hit_sound_time > 0.08:
			_hit_sound_time = world.mission_time
			world.play_at(global_position, snd)
		world.particles.puff("cloth", global_position, Vector3(randf_range(-5, 5), -15.0,
			randf_range(-5, 5)), 2.0, Color(1, 1, 1, 1), Color(-0.1, -0.1, -0.1, -0.8), 0.0, -10.0)
		world.flash(_model)
		if is_player:
			world.hud.hit_flash = 1.0
		return
	health = 0.0
	_shot_down()


## Destroyed in the air: burst, then the falling spin (original state 2) until the ground.
func _shot_down() -> void:
	world.play_at(global_position, _blast_sound)
	world.particles.burst(global_position, 1.0)
	state = State.DEAD
	falling = true
	destroyed.emit(self)


## Hitting the ground hard (original state 3): debris burst sized endurance * 0.1, a smoke column
## and the crash sound; the wreck stays where it fell.
func crash() -> void:
	if state == State.DEAD and not falling:
		return
	var was_alive := state != State.DEAD
	state = State.DEAD
	falling = false
	crashed = was_alive
	health = 0.0
	world.particles.burst(global_position, endurance * 0.1)
	world.particles.smoke_column(global_position, 1.0)
	world.spawn_explosion(global_position, 12.0, _blast_sound)
	if was_alive:
		destroyed.emit(self)
	if _engine_sound:
		_engine_sound.stop()
	# wreck: darken the model where it lies
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _wreck_material()
	set_physics_process(false)


static var _wreck_mat: StandardMaterial3D


static func _wreck_material() -> StandardMaterial3D:
	if _wreck_mat == null:
		_wreck_mat = StandardMaterial3D.new()
		_wreck_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wreck_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wreck_mat.albedo_color = Color(0.05, 0.04, 0.03, 0.75)
	return _wreck_mat


## Spinning down after being shot (original state 2): bank += 200 deg/s, nose drops 100 deg/s.
func _fall(dt: float) -> void:
	var m := flight_basis
	bank += 200.0 * dt
	m = m * Basis(Vector3.RIGHT, deg_to_rad(100.0 * maxf(m.y.y, 0.2) * dt))
	speed = minf(speed + accel * dt, dive_speed)
	velocity = m.z * (speed * speed / high_speed) + Vector3.DOWN * mass * 10.0
	var pos := global_position + velocity * dt
	flight_basis = m.orthonormalized()
	global_transform = Transform3D(flight_basis * Basis(Vector3.BACK, deg_to_rad(bank)), pos)
	if pos.y - world.ground_height(pos) < gear_height:
		crash()
	_prop_angle = fmod(_prop_angle + 6.0 * TAU * dt, TAU)
	for p in _propellers:
		p.transform.basis = Basis(Vector3.BACK, _prop_angle)


## Damage smoke (RedAce.c:31878): puffs per second = damage * 5 / endurance + hit smoke while flying,
## 150 * 5 / endurance + hit smoke while spinning down (dark, thicker, rising faster).
func _damage_smoke(dt: float) -> void:
	var damage := endurance - health
	if damage <= 0.0 and not falling:
		return
	var rate := (150.0 if falling else damage) * (5.0 / endurance) + _smoke_puff
	_smoke_timer += dt
	var n := int(rate * _smoke_timer)
	if n >= 1:
		_smoke_timer = 0.0
		for i in mini(n, 8):
			var v := Vector3(randf_range(-5, 5), 30.0 if falling else 15.0, randf_range(-5, 5))
			if falling:
				var g := randf_range(0.3, 0.6)
				world.particles.puff("smoke", global_position, v, 4.0, Color(g, g, g * 0.95, 1.0),
					Color(-0.2, -0.2, -0.2, -0.2), 5.0)
			else:
				world.particles.puff("smoke", global_position, v, 2.0, Color(0.9, 0.9, 0.9, clampf(rate * 0.05, 0.1, 0.9)),
					Color(-0.1, -0.1, -0.1, -0.15), 3.0)
	_smoke_puff = maxf(_smoke_puff - dt * 3.5, 0.0)


func current_goal() -> Dictionary:
	return goals[goal_index] if goal_index < goals.size() else {}


# ---------------------------------------------------------------- AI
# Mission script goals ([airNgoalK]) run one at a time in order (decomp FUN_00438937: only the head of
# the pilot's goal list runs; a handler returning done removes it; new goals are pushed in front).
# Goals are built from the mission entry by exact type (decomp RedAce.c:34449); any other value
# (0, 0x21, 0x7b, 0x102 in the shipped missions) is dropped, so e.g. mission 3's player stays parked.
#   0x10 take off: full throttle until above stall speed, then pull up until flying (FUN_0043b39c)
#   0x20 fly to pos until within real horizontally (FUN_00439b85)
#   0x30 formation: hold the target's local offset pos, matching its speed (FUN_00439206)
#   0x60 evade: fly to pos for real seconds; pushed when hit or about to collide (FUN_00439c18)
#   0x70 gun attack on object targetid (FUN_00439e6f)
#   0x80 dive attack with rockets, guns once they are spent (FUN_0043a825)
#   0x90 level bombing run, guns once the bombs are spent (FUN_0043ad4b)
#   0x100 appear: move to pos keeping the heading, throttle 1, speed = highspeed, flying (FUN_0043b328)
#   0x120 stay hidden until the object targetid nearest to us is within real of pos (FUN_00439c85)
#   0x130 / 0x140 retaliate on / off: when hit, attack the attacker rather than evade (FUN_00437af6);
#     0x130's real also limits how long a 0x70 attack lasts
#   0x160 stay hidden for real seconds (FUN_00439d7f)
#   0x170 hide: the plane leaves the world (not drawn, not a target) until a 0x120 / 0x160 shows it
# targetid <= 0 selects group -targetid (bit of the groups field), the member nearest to us
# (decomp FUN_0044a881). With no goals left the plane flies to random points of the battle area
# (RedAce.c:35232); it only shoots inside an attack goal.
# Steering (FUN_00439376) works on the target direction d in the plane's frame: bank = -90 * d.right,
# full bank toward its side when the target is behind; pitch rate = 90 * d.up. Bank changes at most
# 3 * rollrate deg/s. Terrain (FUN_0043b2a8): below 120 - 90 * at.y over the ground, pull up at 20 - 70 * at.y.

const G_TAKEOFF := 0x10
const G_WAYPOINT := 0x20
const G_FORMATION := 0x30
const G_EVADE := 0x60
const G_ATTACK := 0x70
const G_DIVE_ATTACK := 0x80
const G_BOMB_RUN := 0x90
const G_APPEAR := 0x100
const G_WAIT_NEAR := 0x120
const G_RETALIATE_ON := 0x130
const G_RETALIATE_OFF := 0x140
const G_WAIT_TIME := 0x160
const G_HIDE := 0x170
const G_FREE := -1
const GOAL_TYPES := [G_TAKEOFF, G_WAYPOINT, G_FORMATION, G_EVADE, G_ATTACK, G_DIVE_ATTACK, G_BOMB_RUN, 0x110,
	G_APPEAR, G_WAIT_NEAR, G_RETALIATE_ON, G_RETALIATE_OFF, 0x150, G_WAIT_TIME, G_HIDE]
const BULLET_LEAD := 1.0 / 275.0  # 0x70 leads an aircraft by distance * 0.0036363637 * its speed

var _goal_timer := 0.0
var attack_time_limit := 0.0  # 0x130 real (pilot + 0x414); 0 = no limit
var _ai_bank := 0.0  # commanded bank, deg (pilot + 0x11c)
var _ai_pitch := NAN  # pitch rate commanded this frame, deg/s, + = nose up (pilot + 0x120, negated);
# when a goal sets none (waits) the rate decays in the flight model and the bank holds, so the plane circles


func _ai(dt: float) -> void:
	if _left_the_map():
		return
	_ai_pitch = NAN
	fire_input = false
	secondary_input = false
	var goal := current_goal()
	if _script_goal(goal, dt):
		goal = current_goal()
	if hidden:
		return
	if goal.is_empty() and (state != State.GROUND or is_player):
		_free_goal()
		goal = current_goal()
	if goal.is_empty():
		return
	var done := false
	match int(goal.type):
		G_TAKEOFF:
			throttle = 1.0
			if state == State.GROUND:
				_ai_pitch = 0.0 if speed < stall_speed else 30.0
			else:
				done = true
		G_WAYPOINT:
			done = Vector2(goal.pos.x - global_position.x, goal.pos.z - global_position.z).length() < goal.radius
			if not done:
				_steer(goal.pos)
				_avoid_terrain()
		G_EVADE:
			goal.radius -= dt
			done = goal.radius < 0.0
			if not done:
				_steer(goal.pos)
				_avoid_terrain()
		G_FORMATION:
			done = not _formation(goal)
		G_ATTACK:
			done = _attack(goal, dt)
		G_DIVE_ATTACK:
			done = _dive_attack(goal)
		G_BOMB_RUN:
			done = _bomb_run(goal)
		G_WAIT_NEAR, G_WAIT_TIME:
			# visible wait: parked planes wait to scramble, flying ones circle on their last bank
			# (the exe's wait sets no command; the low-altitude pull-up is added here)
			if state != State.GROUND:
				_avoid_terrain()
		_:
			done = true  # 0x110 / 0x150 are unused by the shipped missions
	if done and current_goal() == goal:
		_remove_goal(goal)
	if state == State.GROUND and int(goal.type) in [G_WAIT_NEAR, G_WAIT_TIME]:
		throttle = 0.0
		_ai_pitch = 0.0
	elif state == State.GROUND and int(goal.type) != G_TAKEOFF:
		# a parked plane given somewhere to go rolls and lifts off on its own
		throttle = 1.0
		_ai_pitch = 0.0 if speed < stall_speed else 30.0
	_edge_of_battle()


## Point in the plane's frame: x = toward the right wing, y = up, z = forward (unit vector).
func _local_dir(to: Vector3) -> Vector3:
	var d := to.normalized()
	var m := flight_basis
	return Vector3(-d.dot(m.x), d.dot(m.y), d.dot(m.z))


## FUN_00439376: bank toward the target side, pitch toward its elevation; behind = full bank.
func _steer(aim: Vector3) -> void:
	var l := _local_dir(aim - global_position)
	var side := l.x
	if l.z < 0.0:
		side = 1.0 if l.x >= 0.0 else -1.0
	_ai_bank = side * 90.0
	_ai_pitch = l.y * 90.0
	_avoid_collision()


## FUN_0043b2a8: pull up when low; the threshold rises when diving.
func _avoid_terrain() -> void:
	var at_y := flight_basis.z.y
	if world.height_above_ground(global_position) < 120.0 - 90.0 * at_y:
		_ai_pitch = 20.0 - 70.0 * at_y if flight_basis.y.y >= 0.0 else -(20.0 + 70.0 * at_y)


## FUN_004394df: sidestep (0x60 for 1.5 s) when close to the nearest member of group 8 (player and allies).
func _avoid_collision() -> void:
	if int(current_goal().get("type", 0)) == G_EVADE:
		return
	var o = world.object_for_goal(-8, self)
	if not (o is Aircraft):
		return
	var r: float = o.radius
	if global_position.distance_squared_to(o.global_position) < r * o.back_length * 2.5:
		var side: Vector3 = o.flight_basis.z.cross(flight_basis.y)
		_push_goal({"type": G_EVADE, "pos": global_position + side * 50.0, "radius": 1.5, "targetid": 0})


## Goal target: position, and for aircraft their speed and heading (decomp properties 1, 2, 0x1b).
func _goal_object(goal: Dictionary) -> Variant:
	return world.object_for_goal(int(goal.targetid), self)


static func _obj_pos(o) -> Vector3:
	return o.global_position if o is Aircraft else o.node.global_position


static func _airborne(o) -> bool:
	return o is Aircraft and o.state != State.GROUND


## 0x30: hold the target's local offset (stored as goal pos - target pos, y = 0) and match its speed.
func _formation(goal: Dictionary) -> bool:
	var o = _goal_object(goal)
	if o == null:
		return false
	if not goal.has("offset"):
		var tp: Vector3 = _obj_pos(o)
		goal.offset = Vector3(goal.pos.x - tp.x, 0.0, goal.pos.z - tp.z)
	var ob: Basis = o.flight_basis if o is Aircraft else o.node.global_transform.basis
	_steer(_obj_pos(o) + ob * goal.offset)
	_avoid_terrain()
	var their: float = (flight_basis.z.dot(o.flight_basis.z) * o.speed) if o is Aircraft else 0.0
	var diff := speed - their
	if diff > 1.0:
		throttle = maxf(1.0 - diff * 0.1, 0.5)
	elif diff < -1.0:
		throttle = 1.0
	return true


## 0x70 gun attack (FUN_00439e6f). Returns true when finished.
func _attack(goal: Dictionary, dt: float) -> bool:
	var o = _goal_object(goal)
	if o == null:
		return true
	var tp: Vector3 = _obj_pos(o)
	var to := tp - global_position
	var dist := to.length()
	if o is Aircraft:
		# aims ahead of the target by distance / 275 * its speed, plus 3/4 of that along the horizontal part of its
		# banked up axis, which points into its turn and vanishes in level flight (0x439f89; y is zeroed at 0x43a058;
		# properties 2 and 4 read plane + 0x110, the matrix rolled at 0x4343c9)
		var lead: float = dist * BULLET_LEAD * o.speed
		var tb: Basis = o.global_transform.basis.orthonormalized()
		to += tb.z * lead + Vector3(tb.y.x, 0.0, tb.y.z) * (lead * 0.75)
		throttle = clampf(throttle + (-0.3 if o.speed < speed else 0.5) * dt, 0.65, 1.0)
	else:
		# ground targets: the firing range is measured along the ground (0x43a141)
		dist = Vector2(to.x, to.z).length()
	var l := _local_dir(to)
	var side := l.x
	if l.z >= 0.0:
		goal.side = 0
		if flight_basis.y.y < 0.0:
			side = 1.0
		_ai_pitch = l.y * 90.0
	else:
		# target behind: commit to a hard turn to one side, chosen at random once
		if int(goal.get("side", 0)) == 0:
			goal.side = 1 if randi() % 2 else -1
		side = goal.side
	_ai_bank = clampf(side * 180.0, -90.0, 90.0)
	fire_input = l.z > 0.8 and dist < 300.0
	# not in FUN_00439e6f: the general low-altitude pull-up, since this flight model needs more room
	# than the exe's 4 s look-ahead below leaves when strafing
	_avoid_terrain()
	# attack time limit (0x130 real) and breaking off when badly damaged
	if endurance - health > endurance * 0.8:
		return true
	goal.t = goal.get("t", 0.0) + dt
	if attack_time_limit > 0.0 and goal.t > attack_time_limit:
		return true
	# ground ahead within 4 s (looking down 1.5 s): level the wings and pull up 45
	var probe := global_position + flight_basis.z * speed * 4.0 + Vector3.DOWN * speed * 1.5
	var f := world.ground_hit_fraction(global_position, probe)
	if f > 0.0:
		var ahead := speed * 4.0 * f
		if ahead < 50.0 - flight_basis.z.y * 125.0 or ahead < 10.0:
			_ai_bank = 0.0
			_ai_pitch = 45.0 if flight_basis.y.y > 0.0 else -45.0
	return false


## 0x80 dive attack (FUN_0043a825): approach ground targets 350 above, dive inside 300, rockets when
## lined up within 225; climbs away (0x20) when too low or close. Guns (0x70) once rockets are gone.
func _dive_attack(goal: Dictionary) -> bool:
	var o = _goal_object(goal)
	if o == null:
		return true
	var tp: Vector3 = _obj_pos(o)
	var to := tp - global_position
	var flat := Vector2(to.x, to.z).length()
	if not _airborne(o):
		var dy := to.y
		if flat > 300.0:
			to.y = tp.y + 350.0 - global_position.y
		if flat < 75.0 or dy > -100.0:
			var f := Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized()
			_push_goal({"type": G_WAYPOINT, "pos": Vector3(global_position.x + f.x * 350.0, tp.y + 250.0,
				global_position.z + f.z * 350.0), "radius": 40.0, "targetid": 0})
	else:
		to += o.flight_basis.z * (to.length() * 0.01 * o.speed)
	var dist := to.length()
	var l := _local_dir(to)
	if l.z < 0.0:
		l = Vector3(1.0, 0.0, l.z)
	_ai_bank = l.x * 90.0
	_ai_pitch = clampf(l.y * 180.0, -90.0, 90.0)
	if l.z > 0.98 and dist < 225.0:
		if ordnance_left > 0 and ordnance_type == 2:
			secondary_input = true
		else:
			_switch_to_guns(goal, tp, 250.0)
	_avoid_terrain()
	return false


## 0x90 level bombing run (FUN_0043ad4b): head for the target, hold 140..160 above it, release when the
## predicted impact is within 30; go round when overflying. Guns (0x70) once the bombs are gone.
func _bomb_run(goal: Dictionary) -> bool:
	var o = _goal_object(goal)
	if o == null:
		return true
	var tp: Vector3 = _obj_pos(o)
	var flat_to := Vector3(tp.x - global_position.x, 0.0, tp.z - global_position.z)
	var flat := flat_to.length()
	var h := global_position.y - tp.y
	var l := _local_dir(flat_to)
	var side := l.x
	if l.z < 0.0:
		side = 1.0 if l.x >= 0.0 else -1.0
	_ai_bank = side * 90.0
	# nudge the pitch rate by 1 deg/s outside 140..160 above the target (the exe's -1 / +1; its sign as
	# decompiled would climb when too high, so the corrective sign is used here)
	if h > 160.0:
		_ai_pitch = -1.0
	elif h < 140.0:
		_ai_pitch = 1.0
	var fwd := Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized()
	if fwd.dot(flat_to / maxf(flat, 0.001)) > 0.9 and flat < 600.0:
		var impact := world.bomb_impact(global_position, velocity)
		if Vector2(impact.x - tp.x, impact.z - tp.z).length() < 30.0:
			if ordnance_left > 0 and ordnance_type == 1:
				secondary_input = true
			else:
				_switch_to_guns(goal, tp, 200.0)
	if flat < 20.0:
		_push_goal({"type": G_WAYPOINT, "pos": global_position + fwd * (h + 300.0), "radius": 40.0, "targetid": 0})
	_avoid_terrain()
	return false


## Out of rockets / bombs: the goal becomes a gun attack, after climbing to 150 above the target.
func _switch_to_guns(goal: Dictionary, tp: Vector3, ahead: float) -> void:
	goal.type = G_ATTACK
	var f := Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized()
	_push_goal({"type": G_WAYPOINT, "pos": Vector3(global_position.x + f.x * ahead, tp.y + 150.0,
		global_position.z + f.z * ahead), "radius": 40.0, "targetid": 0})


## No goals left: fly to a random point of the battle area (radius 100). The player's autopilot
## (debug) attacks the mission objectives instead.
func _free_goal() -> void:
	if is_player and state == State.GROUND:
		var f := Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized()
		_push_goal({"type": G_WAYPOINT, "pos": global_position + f * 1000.0 + Vector3.UP * 250.0, "radius": 150.0,
			"targetid": 0})
		_push_goal({"type": G_TAKEOFF, "pos": Vector3.ZERO, "radius": 0.0, "targetid": 0})
		return
	if is_player:
		var t := world.nearest_objective(global_position)
		if not t.is_empty():
			var kind := G_BOMB_RUN if ordnance_type == 1 and ordnance_left > 0 else \
				(G_DIVE_ATTACK if ordnance_type == 2 and ordnance_left > 0 else G_ATTACK)
			_push_goal({"type": kind, "targetid": int(t.id), "pos": Vector3.ZERO, "radius": 0.0})
			return
		var e := world.nearest_enemy(self)
		if e:
			_push_goal({"type": G_ATTACK, "targetid": e.object_id, "pos": Vector3.ZERO, "radius": 0.0})
			return
	var b := world.map_bounds
	var x := randf_range(b.position.x, b.end.x)
	var z := randf_range(b.position.y, b.end.y)
	var y := world.ground_height(Vector3(x, 0.0, z)) + randf_range(100.0, 400.0)
	_push_goal({"type": G_WAYPOINT, "pos": Vector3(x, y, z), "radius": 100.0, "targetid": 0})


## Near the edge with nothing to do: evade 1.25 s toward a point 700 inside (RedAce.c:35186).
func _edge_of_battle() -> void:
	var b := world.map_bounds
	var p := global_position
	if not (p.x < b.position.x + 500.0 or p.x > b.end.x - 500.0 or p.z < b.position.y + 500.0 or p.z > b.end.y - 500.0):
		return
	var g := current_goal()
	if not g.is_empty() and int(g.type) != G_WAYPOINT:
		return
	if not g.is_empty() and b.grow(-500.0).has_point(Vector2(g.pos.x, g.pos.z)):
		return
	var tx := p.x + flight_basis.z.x * speed
	var tz := p.z + flight_basis.z.z * speed
	if p.x < b.position.x + 500.0:
		tx = b.position.x + 700.0
	if p.x > b.end.x - 500.0:
		tx = b.end.x - 700.0
	if p.z < b.position.y + 500.0:
		tz = b.position.y + 700.0
	if p.z > b.end.y - 500.0:
		tz = b.end.y - 700.0
	_push_goal({"type": G_EVADE, "pos": Vector3(tx, p.y + flight_basis.z.y * speed + 200.0, tz), "radius": 1.25,
		"targetid": 0})


## When hit (FUN_00437af6): evade toward a random point beside us for 0.5 s, or with retaliation on,
## attack whoever hit us if they are on the other side.
func on_hit(attacker) -> void:
	if is_player and not autopilot or hidden or current_goal().is_empty():
		return
	var top := int(current_goal().type)
	if not retaliate:
		if top != G_EVADE:
			var m := flight_basis
			var r := func() -> float: return float(randi() & 0x3ff) * 0.9765625 - 1.0
			var p := global_position + m.z * 50.0 + Vector3(-m.x.x * r.call(), -m.x.y * r.call(), -m.x.z * r.call())
			_push_goal({"type": G_EVADE, "pos": p, "radius": 0.5, "targetid": 0})
		return
	if attacker == null:
		return
	var their_groups: int = attacker.groups if attacker is Aircraft else int(attacker.get("groups", 0))
	if their_groups & groups:
		return
	if top != G_ATTACK:
		var id: int = attacker.object_id if attacker is Aircraft else int(attacker.get("id", 0))
		if id > 0:
			_push_goal({"type": G_ATTACK, "targetid": id, "pos": Vector3.ZERO, "radius": 0.0})


func _push_goal(g: Dictionary) -> void:
	goals.insert(goal_index, g)


func _remove_goal(g: Dictionary) -> void:
	var i := goals.find(g)
	if i >= goal_index:
		goals.remove_at(i)
	_goal_timer = 0.0


## AI commands as the original pilot applies them (RedAce.c:35213): the commanded bank moves at most
## 3 * rollrate deg/s; pitch rate is set directly. Inverted: command past 90 to roll out.
func _apply_ai_commands() -> void:
	var dt := get_physics_process_delta_time()
	if state == State.GROUND:
		pitch_rate = 0.0 if is_nan(_ai_pitch) else _ai_pitch
		return
	if flight_basis.y.y < 0.0:
		bank = 100.0 * (signf(bank) if bank != 0.0 else 1.0)
	else:
		var rate := high_roll * 3.0 * dt  # 0x438e2e
		bank = move_toward(bank, _ai_bank, rate)
	if not is_nan(_ai_pitch):
		pitch_rate = _ai_pitch


func _next_goal() -> void:
	goal_index += 1
	_goal_timer = 0.0


## Goals that change the plane's presence or mode rather than steer it. Runs them in order until a
## steering goal (or an unfinished wait) is at the head. Returns true when it advanced.
func _script_goal(goal: Dictionary, dt: float) -> bool:
	var advanced := false
	while not goal.is_empty():
		match int(goal.type):
			G_APPEAR:
				var p: Vector3 = goal.pos
				place(Transform3D(Basis.looking_at(-Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized(),
					Vector3.UP), p))
				state = State.FLYING
				throttle = 1.0
				speed = high_speed
				velocity = flight_basis.z * speed
			G_HIDE:
				_set_hidden(true)
			G_RETALIATE_ON:
				retaliate = true
				attack_time_limit = goal.radius
			G_RETALIATE_OFF:
				retaliate = false
			G_WAIT_TIME:
				_goal_timer += dt
				if _goal_timer < goal.radius:
					return advanced
				_set_hidden(false)
			G_WAIT_NEAR:
				var o = world.object_for_goal(int(goal.targetid), self)
				if o == null:
					return advanced
				var at: Vector3 = o.global_position if o is Aircraft else o.node.global_position
				if Vector2(at.x - goal.pos.x, at.z - goal.pos.z).length() >= goal.radius:
					return advanced
				_set_hidden(false)
			_:
				return advanced
		_next_goal()
		advanced = true
		goal = current_goal()
	return advanced


## Player aircraft: its script only places it (0x100 in the shipped missions); the pilot flies.
func _player_script() -> void:
	_script_goal(current_goal(), get_physics_process_delta_time())


## Shadow as the exe places it (RedAce.c:31814): the plane's drawn matrix with the y components of its
## axes zeroed (flattened onto the ground plane), at the terrain under the plane + 0.5.
func _place_shadow() -> void:
	if _shadow == null:
		return
	var g := world.ground_height(global_position)
	_shadow.visible = g > -999.0
	var b := global_transform.basis
	b.x.y = 0.0
	b.y.y = 0.0
	b.z.y = 0.0
	b.y += Vector3(0.0, 0.01, 0.0)  # keep the basis invertible
	_shadow.global_transform = Transform3D(b, Vector3(global_position.x, g + 0.5, global_position.z))


func _set_hidden(h: bool) -> void:
	hidden = h
	visible = not h
	world._count_rule_members()


## Mission rules (0x43b70a, 0x434b50): a hidden plane is not alive, and an enemy (group 9) that left
## the map is gone; any other plane that left the map still counts as alive.
func counts_as_lost() -> bool:
	if state == State.DEAD:
		return true
	return groups & (1 << 9) != 0 if left_map else hidden


## Collision probes (decomp FUN_00431607): segments from the previous position to the nose, tail,
## wingtips, top and underside, using plane.ini [collision] lengths. basis.x is the left (port) wing.
func probe_segments(prev: Vector3) -> Array:
	var b := global_transform.basis
	var p := global_position
	return [p + b.z * front_length, p - b.z * back_length, p + b.x * port_length, p - b.x * starboard_length,
		p + b.y * up_length, p - b.y * down_length].map(func(e: Vector3) -> Array: return [prev, e])


## Terrain probes of FUN_00431607: the nose segment meeting the ground crashes the plane (state 3);
## a wingtip segment meeting it adds 1 damage and sends the plane into its falling spin (state 2).
## (The exe also runs them while taxiing; here only in the air, so uneven runways do not clip wingtips.)
func _terrain_probes(prev: Vector3) -> void:
	var b := global_transform.basis
	var p := global_position
	if world.ground_hit_fraction(prev, p + b.z * front_length) > 0.0:
		crash()
		return
	for tip in [p + b.x * port_length, p - b.x * starboard_length]:
		if world.ground_hit_fraction(prev, tip) > 0.0:
			# no burst: the exe only sets state 2
			health -= 1.0
			state = State.DEAD
			falling = true
			destroyed.emit(self)
			return


## Does the segment a..b pass through this plane's collision box?
func box_hit(a: Vector3, b: Vector3) -> bool:
	var inv := global_transform.affine_inverse()
	var la := inv * a
	var lb := inv * b
	var lo := Vector3(-starboard_length, -down_length, -back_length)
	var hi := Vector3(port_length, up_length, front_length)
	if not World.segment_hits_box(la, lb, lo, hi):
		return false
	# then against the clump's triangles, as the exe's atomic test (FUN_00430295)
	if _faces.is_empty() and _model:
		var to_self := global_transform.affine_inverse()
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			var xf: Transform3D = to_self * (mi as MeshInstance3D).global_transform
			for v in (mi as MeshInstance3D).mesh.get_faces():
				_faces.append(xf * v)
	for i in range(0, _faces.size() - 2, 3):
		if Geometry3D.segment_intersects_triangle(la, lb, _faces[i], _faces[i + 1], _faces[i + 2]) != null:
			return true
	return false


## Alive and in the world: can be seen, targeted and hit.
## AI planes more than 150 outside the world box are sent away for good (0x438fb2).
func _left_the_map() -> bool:
	if left_map or hidden or is_player:
		return left_map
	var p := global_position
	var w := world.map_bounds
	if p.x < w.position.x - 150.0 or p.z < w.position.y - 150.0 or p.x >= w.end.x + 150.0 or p.z >= w.end.y + 150.0:
		left_map = true
		_set_hidden(true)
	return left_map


func present() -> bool:
	return state != State.DEAD and not hidden
