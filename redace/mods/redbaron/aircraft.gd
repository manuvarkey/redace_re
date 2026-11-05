extends Aircraft
## Red Baron aircraft: the stock Aircraft plus defensive gunners on two-seaters and bombers
## (mods/shared/defensive_gunners.gd, as the Battle of Britain He 111) and a damaged signal for
## mission scripts. Gunners are on by default for the folders in GUNNER_PLANES; a mission's
## [airN] gunners = 0 / 1 overrides that (the aircodh2 stands in for the two-seat F.E.2d in mission 8
## but flies as the single-seat DH.2 in mission 1).

const DefensiveGunners := preload("res://mods/shared/defensive_gunners.gd")
const GUNNER_PLANES := ["re8", "handleypage", "halberstadt"]
# tempered after playtests (Britain's: 450, 5 rounds/s, no pauses): 3 rounds/s in bursts of 6 (2 s),
# then 1.5 s to re-aim, out to 380
const GUNNER_RANGE := 380.0
const GUNNER_INTERVAL := 1.0 / 3.0
const GUNNER_BURST := 6
const GUNNER_PAUSE := 1.5

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
const BOMB_HEIGHT := 150.0
var _gunners := DefensiveGunners.new(GUNNER_RANGE, GUNNER_INTERVAL)


func setup(name_: String, main: World) -> void:
	super.setup(name_, main)
	_gunners.burst = GUNNER_BURST
	_gunners.pause = GUNNER_PAUSE
	gunners_enabled = plane_name in GUNNER_PLANES


func set_gunner_rate(rounds_per_second: float) -> void:
	_gunners.interval = 1.0 / maxf(rounds_per_second, 0.01)


func _guns(dt: float) -> void:
	super._guns(dt)
	if not gunners_enabled or is_player or state == State.DEAD or hidden:
		return
	if _gunners.update(self, dt):
		_gun_sound_firing(true)


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


func is_persistent() -> bool:
	if persistent >= 0:
		return persistent == 1
	return false  # original behaviour unless a mission asks (user: massed persistent attackers caused trouble)


func on_hit(attacker) -> void:
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
	if attacker == self and not is_player:
		return  # an AI plane's own bomb or rocket blast (the engine gives the firer 5 %): it killed bombers
	amount *= damage_scale
	super.take_damage(amount, attacker)
	damaged.emit(self, amount, attacker)
