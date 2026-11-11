extends Aircraft
## Red Baron aircraft: the stock Aircraft plus defensive gunners on two-seaters and bombers
## (mods/shared/defensive_gunners.gd, as the Battle of Britain He 111) and a damaged signal for
## mission scripts. Gunners are on by default for the folders in GUNNER_PLANES; a mission's
## [airN] gunners = 0 / 1 overrides that (the aircodh2_rb stands in for the two-seat F.E.2d in mission 8
## but flies as the single-seat DH.2 in mission 1).

const DefensiveGunners := preload("res://mods/shared/defensive_gunners.gd")
const GUNNER_PLANES := ["re8", "handleypage", "halberstadt", "halberstadt_rb"]
# tempered after playtests (Britain's: 450, 5 rounds/s, no pauses): 3 rounds/s in bursts of 6 (2 s),
# then 1.5 s to re-aim, out to 380
const GUNNER_RANGE := 380.0
const GUNNER_INTERVAL := 1.0 / 3.0
const GUNNER_BURST := 6
const GUNNER_PAUSE := 1.5
## Gun stations of the big bombers (historical positions): the Handley Page O/100's nose gunner (Scarff ring,
## forward arc), dorsal gunner (behind the wings, upper and rear arc) and ventral trap-door gun (lower rear).
## Each fires on its own: 4 rounds/s in bursts of 8, then 1 s, out to 450. Planes listed here use these in
## place of the two-seater gunner.
const GUN_STATIONS := {
	"handleypage": [
		{"origin": Vector3(0, 3.5, 19.0), "axis": Vector3(0, 0.1, 1), "cos": 0.2},
		{"origin": Vector3(0, 3.8, -1.0), "axis": Vector3(0, 0.7, -0.7), "cos": -0.1},
		{"origin": Vector3(0, -2.5, -3.0), "axis": Vector3(0, -0.6, -0.8), "cos": 0.3},
	],
}
const STATION_RANGE := 450.0
const STATION_INTERVAL := 0.25
const STATION_BURST := 8
const STATION_PAUSE := 1.0
## Heavy bombers turn like the Britain mod's He 111: bank held to HEAVY_BANK, rolled in at HEAVY_ROLL_RATE,
## pitch held to HEAVY_PITCH; they do not dodge when hit.
const HEAVY_PLANES := ["handleypage"]
const HEAVY_BANK := 18.0
const HEAVY_ROLL_RATE := 10.0
const HEAVY_PITCH := 8.0
var _stations: Array = []  # {origin, axis, cos, cooldown, fired}

signal damaged(plane: Aircraft, amount: float, attacker: Variant)

var gunners_enabled := false
var damage_scale := 1.0  # mission scripts: fraction of incoming damage taken (e.g. a wounded Baron)
## Persistent pilots (not in the original): a hit no longer makes them dodge for half a second (the
## original evade, FUN_00437af6), so attackers keep at it; with retaliation on they still turn on whoever
## hit them. Off by default (the original behaviour); [airN] persistent = 1 turns it on (Scramble's bombers).
var persistent := -1  # -1 default, 0 off, 1 on
## Bombsight (not in the original): a level bombing run that aims with the bombs' real fall (gravity 60 from
## the plane's velocity; the exe's estimate lands them long) at 150 above the target, releases when the
## predicted impact is within BOMB_MISS, and after overflying flies on 700 and comes back for another pass
## (the original pushes a 40-radius go-round point a two-seater can circle for ever). [airN] bombsight = 1.
var bombsight := false
const BOMB_MISS := 25.0
## Station keeping (not in the original): [airN] keepstation = 1 (default for the player's wingmen, keeps_station). A formation goal holds its slot at the
## leader's speed: the wingman steers at a point STATION_LEAD ahead of the slot on the leader's heading and
## sets the throttle for the leader's speed plus STATION_GAIN per unit it is behind (minus ahead) of the
## slot, never below 1.1 x its stall speed (adding back the flight step's high-altitude speed cut, which
## otherwise stalls a fast fighter throttled back to a bomber's speed). The original goes to full throttle whenever the leader is slower,
## so a fast escort on a slow bomber overshoots and circles 50-500 away.
var keep_station := false
var station_set := false  # [airN] keepstation given; otherwise the player's wingmen keep station by default
const STATION_LEAD := 150.0
const STATION_GAIN := 0.2
const BOMB_HEIGHT := 150.0
var _gunners := DefensiveGunners.new(GUNNER_RANGE, GUNNER_INTERVAL)


## Damage stages (as the Battle of Britain aircraft): plane.ini damagedff1 / damagedff2 / deaddff swap in at
## 35 % and 70 % damage and when shot down; the airframe stays rigid, the paint scorches. Folders without
## them (all the stock models) keep the one model.
var _damage_paths: Array[String] = []
var _damage_stage := 0
var _visual_ambient := 0.4
var _visual_diffuse := 1.0


func setup(name_: String, main: World) -> void:
	super.setup(name_, main)
	var dir := "objects/planes/%s/" % plane_name
	var app: Dictionary = Ini.load_file(Ini.data_path(dir + "plane.ini")).get("appearance", {})
	_visual_ambient = Ini.num(app, "ambient", 0.4)
	_visual_diffuse = Ini.num(app, "diffuse", 1.0)
	_damage_paths.clear()
	for key in ["damagedff1", "damagedff2", "deaddff"]:
		var dff := str(app.get(key, ""))
		_damage_paths.append(dir + dff.get_basename().to_lower() + ".gltf" if not dff.is_empty() else "")
	_gunners.burst = GUNNER_BURST
	_gunners.pause = GUNNER_PAUSE
	_stations.clear()
	for st in GUN_STATIONS.get(plane_name, []):
		var s2: Dictionary = st.duplicate()
		s2.cooldown = 0.0
		s2.fired = 0
		_stations.append(s2)
	gunners_enabled = plane_name in GUNNER_PLANES


func set_gunner_rate(rounds_per_second: float) -> void:
	_gunners.interval = 1.0 / maxf(rounds_per_second, 0.01)


func _guns(dt: float) -> void:
	super._guns(dt)
	if not gunners_enabled or is_player or state == State.DEAD or hidden:
		return
	if _stations.is_empty():
		if _gunners.update(self, dt):
			_gun_sound_firing(true)
		return
	if state == State.GROUND:
		return
	for st in _stations:
		st.cooldown = maxf(0.0, st.cooldown - dt)
		if st.cooldown > 0.0:
			continue
		var shot := DefensiveGunners.station_shot(self, st.origin, st.axis, st.cos, STATION_RANGE)
		if shot.is_empty():
			continue
		world.spawn_ordnance(self, 1, shot.origin, velocity, shot.direction)
		st.cooldown = STATION_INTERVAL
		st.fired += 1
		if st.fired >= STATION_BURST:
			st.fired = 0
			st.cooldown = STATION_PAUSE
		_gun_sound_firing(true)


func _heavy() -> bool:
	return plane_name in HEAVY_PLANES and state != State.DEAD and state != State.GROUND


func _steer(aim: Vector3) -> void:
	if not _heavy():
		super._steer(aim)
		return
	var flat := aim - global_position
	flat.y = 0.0
	var forward := Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized()
	var turn := forward.signed_angle_to(flat.normalized(), Vector3.UP) if flat.length_squared() > 1.0 else 0.0
	_ai_bank = clampf(-rad_to_deg(turn) * 0.8, -HEAVY_BANK, HEAVY_BANK)
	var wanted := clampf((aim.y - global_position.y) * 0.12, -HEAVY_PITCH, HEAVY_PITCH)
	_ai_pitch = clampf((wanted - rad_to_deg(asin(clampf(flight_basis.z.y, -1.0, 1.0)))) * 1.5, -4.0, 4.0)


## The player's AI wingmen roll at most WINGMAN_ROLL_RATE deg/s. The original gun attack steers bang-bang (bank +-90
## as soon as the target is off the nose) and the Dr.I's 3 x 112 deg/s roll flipped it from side to side every few
## tenths of a second: the "swirling" escorts of Cambrai. Station keeping (keeps_station) settles formation flight;
## this settles the fight.
const WINGMAN_ROLL_RATE := 110.0
var force_fire := false  # a mission script holds the guns open whatever the aim (mission 12's closing shot)


func _apply_ai_commands() -> void:
	if keeps_station() and not station_set and state != State.GROUND and not _heavy():
		_ai_bank = move_toward(_last_ai_bank, _ai_bank, minf(high_roll * 3.0, WINGMAN_ROLL_RATE) * get_physics_process_delta_time())
	if _heavy():
		var dt := get_physics_process_delta_time()
		_ai_bank = move_toward(_last_ai_bank, clampf(_ai_bank, -HEAVY_BANK, HEAVY_BANK), HEAVY_ROLL_RATE * dt)
		_last_ai_bank = clampf(_last_ai_bank, -HEAVY_BANK, HEAVY_BANK)
		if not is_nan(_ai_pitch):
			_ai_pitch = clampf(_ai_pitch, -4.0, 4.0)
	super._apply_ai_commands()
	if force_fire:
		fire_input = true


func _fly(dt: float) -> void:
	if _heavy():
		# as the Britain mod's He 111: hold the commanded small pitch rate inside the pitch limit and cancel the
		# flight step's per-frame 5 decay, which otherwise turns small commands into a steady dive
		var pitch := rad_to_deg(asin(clampf(flight_basis.z.y, -1.0, 1.0)))
		var rate := clampf(pitch_rate, -4.0, 4.0)
		if dt > 0.0:
			rate = clampf(rate, (-HEAVY_PITCH - pitch) / dt, (HEAVY_PITCH - pitch) / dt)
		pitch_rate = rate + (5.0 if rate >= 0.0 else -5.0)
		_ai_pitch = pitch_rate
		_rate_set = true
	super._fly(dt)
	if _heavy():
		bank = clampf(bank, -HEAVY_BANK, HEAVY_BANK)
		var heading := Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized()
		if not heading.is_zero_approx():
			var pitch := clampf(asin(clampf(flight_basis.z.y, -1.0, 1.0)), -deg_to_rad(HEAVY_PITCH), deg_to_rad(HEAVY_PITCH))
			flight_basis = Basis.looking_at(-heading, Vector3.UP) * Basis(Vector3.RIGHT, -pitch)
			basis = flight_basis * Basis(Vector3.BACK, deg_to_rad(bank))


func _bomb_run(goal: Dictionary) -> bool:
	if not bombsight or ordnance_type != 1 or ordnance_left <= 0:
		return super._bomb_run(goal)
	var o = _goal_object(goal)
	if o == null:
		return true
	var tp: Vector3 = _obj_pos(o)
	var fwd := Vector3(flight_basis.z.x, 0.0, flight_basis.z.z).normalized()
	var flat_to := Vector3(tp.x - global_position.x, 0.0, tp.z - global_position.z)
	if flat_to.dot(fwd) < 0.0 and flat_to.length() < 500.0:
		_push_goal({"type": G_WAYPOINT, "pos": global_position + fwd * 700.0, "radius": 200.0, "targetid": 0})
		return false
	_steer(Vector3(tp.x, tp.y + BOMB_HEIGHT, tp.z))
	_avoid_terrain()
	var h := global_position.y - tp.y
	var v := velocity
	var t := (v.y + sqrt(maxf(v.y * v.y + 120.0 * h, 0.0))) / 60.0
	var impact := global_position + Vector3(v.x, 0.0, v.z) * t
	if Vector2(impact.x - tp.x, impact.z - tp.z).length() < BOMB_MISS:
		secondary_input = true
	return false


## The player's AI wingmen (group 8, not the player) keep station unless the mission says otherwise: with the
## original formation step a wingman faster than its leader (a Dr.I on a cruising Baron, Brenner at 125 on the Albatros)
## overshoots the slot, then banks 90 degrees back toward it, and zig-zags across the leader's track (measured:
## 17 bank reversals in 30 s on a gentle turn at 105 against the Dr.I's 120; none with station keeping).
func keeps_station() -> bool:
	if station_set:
		return keep_station
	return not is_player and groups & (1 << 8) != 0


func _formation(goal: Dictionary) -> bool:
	var o = _goal_object(goal)
	if not keeps_station() or not (o is Aircraft):
		return super._formation(goal)
	if not goal.has("offset"):
		goal.offset = Vector3.ZERO
	var fwd := Vector3(o.flight_basis.z.x, 0.0, o.flight_basis.z.z).normalized()
	var slot: Vector3 = o.global_position + o.flight_basis * goal.offset
	_steer(slot + fwd * STATION_LEAD)
	_avoid_terrain()
	var behind := (slot - global_position).dot(fwd)
	var want := maxf(o.speed + behind * STATION_GAIN, stall_speed * 1.1)
	want += maxf(ahead_alt - 400.0, 0.0) * 0.5  # undo _altitude_limited_speed
	throttle = asin(clampf(want / high_speed, 0.0, 1.0)) / 1.57
	return true


## The player's AI wingmen steer their gun attack in proportion while the target is ahead (bank = 110 x its sideways
## offset, the original saturates at +-90 from half that): with the Dr.I's roll the original hunted from side to side.
func _attack(goal: Dictionary, dt: float) -> bool:
	var done := super._attack(goal, dt)
	if done or station_set or not keeps_station() or is_zero_approx(_ai_bank):
		return done  # (bank 0: the pull-up from the ground is in charge)
	var o = _goal_object(goal)
	if o != null:
		var l := _local_dir(_obj_pos(o) - global_position)
		if l.z >= 0.0 and flight_basis.y.y >= 0.0:
			_ai_bank = clampf(l.x * 110.0, -90.0, 90.0)
	return done


func is_persistent() -> bool:
	if persistent >= 0:
		return persistent == 1
	return false  # original behaviour unless a mission asks (user: massed persistent attackers caused trouble)


func on_hit(attacker) -> void:
	if plane_name in HEAVY_PLANES:
		return  # the gunners defend a heavy bomber; its pilot holds the bombing course (as the Britain mod)
	if not is_persistent():
		super.on_hit(attacker)
		return
	if is_player and not autopilot or hidden or current_goal().is_empty() or not retaliate or attacker == null:
		return
	var their_groups: int = attacker.groups if attacker is Aircraft else int(attacker.get("groups", 0))
	if their_groups & groups or int(current_goal().type) == G_ATTACK:
		return
	var id: int = attacker.object_id if attacker is Aircraft else int(attacker.get("id", 0))
	if id > 0:
		_push_goal({"type": G_ATTACK, "targetid": id, "pos": Vector3.ZERO, "radius": 0.0})


func take_damage(amount: float, attacker = null) -> void:
	if attacker is Aircraft and attacker == self and not is_player:
		return  # an AI plane's own bomb or rocket blast (the engine gives the firer 5 %): it killed bombers
	if attacker is Aircraft and attacker != self and attacker.allied == allied and not attacker.is_player:
		return  # AI fire never hurts its own side (the engine's rounds hit anyone; bomber gunners and
		# wingmen kept shooting their own formation down)
	if attacker is Dictionary and world._mod:
		amount *= float(world._mod.get("aa_damage"))  # [mod] aadamage: AA guns and tanks
	amount *= damage_scale
	super.take_damage(amount, attacker)
	_update_damage_model()
	damaged.emit(self, amount, attacker)


func _shot_down() -> void:
	super._shot_down()
	_update_damage_model()


func _update_damage_model() -> void:
	if _damage_paths.is_empty() or _damage_paths.all(func(p): return p.is_empty()):
		return
	var damage := 1.0 - health / maxf(endurance, 0.001)
	var stage := 3 if state == State.DEAD else (2 if damage >= 0.7 else (1 if damage >= 0.35 else 0))
	if stage <= _damage_stage:
		return
	_damage_stage = stage
	var path := _damage_paths[stage - 1]
	if path.is_empty() or not ResourceLoader.exists(Ini.data_path(path)):
		return
	var replacement := World.load_model(path)
	if replacement == null:
		return
	World.apply_lighting(replacement, _visual_ambient, _visual_diffuse)
	var show_model := _model == null or _model.visible
	if _model:
		_model.visible = false
		_model.queue_free()
	_propellers.clear()
	_faces.clear()
	_model = replacement
	add_child(_model)
	_model.visible = show_model
	_find_propellers(_model)
