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


func take_damage(amount: float, attacker = null) -> void:
	super.take_damage(amount, attacker)
	damaged.emit(self, amount, attacker)
