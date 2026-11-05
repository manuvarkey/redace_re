extends Aircraft
## Red Baron aircraft: the stock Aircraft plus defensive gunners on two-seaters and bombers
## (mods/shared/defensive_gunners.gd, as the Battle of Britain He 111) and a damaged signal for
## mission scripts. Gunners are on by default for the folders in GUNNER_PLANES; a mission's
## [airN] gunners = 0 / 1 overrides that (the aircodh2 stands in for the two-seat F.E.2d in mission 8
## but flies as the single-seat DH.2 in mission 1).

const DefensiveGunners := preload("res://mods/shared/defensive_gunners.gd")
const GUNNER_PLANES := ["re8", "handleypage", "halberstadt"]
const GUNNER_RANGE := 450.0
const GUNNER_INTERVAL := 0.2

signal damaged(plane: Aircraft, amount: float, attacker: Variant)

var gunners_enabled := false
var damage_scale := 1.0  # mission scripts: fraction of incoming damage taken (e.g. a wounded Baron)
## Persistent pilots (not in the original): a hit no longer makes them dodge for half a second (the
## original evade, FUN_00437af6), so attackers keep at it; with retaliation on they still turn on whoever
## hit them. Off by default (the original behaviour); [airN] persistent = 1 turns it on (Scramble's bombers).
var persistent := -1  # -1 default, 0 off, 1 on
var _gunners := DefensiveGunners.new(GUNNER_RANGE, GUNNER_INTERVAL)


func setup(name_: String, main: World) -> void:
	super.setup(name_, main)
	gunners_enabled = plane_name in GUNNER_PLANES


func set_gunner_rate(rounds_per_second: float) -> void:
	_gunners.interval = 1.0 / maxf(rounds_per_second, 0.01)


func _guns(dt: float) -> void:
	super._guns(dt)
	if not gunners_enabled or is_player or state == State.DEAD or hidden:
		return
	if _gunners.update(self, dt):
		_gun_sound_firing(true)


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
	amount *= damage_scale
	super.take_damage(amount, attacker)
	damaged.emit(self, amount, attacker)
