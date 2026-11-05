extends "res://mods/redbaron/mission_script.gd"
## Mission 11, Formation (design "11. Formation"):
##   1. At 60 s Camels A and B dive on the Baron. Brenner takes A, his second (a rookie) takes B; once A
##      is down (or 15 s on) Brenner chases B away, 1500 east of the two-seater's route, his second with
##      him. "Stay with the two-seater."
##   2. Leaving the two-seater more than 900 away for 5 s before it is home brings two Camels down on it
##      (the two-seater cannot survive alone: the player's duty, not a scripted inability).
##   3. When the two-seater is within 300 of the aerodrome it lands (hidden: safe) and Camels C-E come for
##      Brenner, far off; his position is marked on the minimap. He holds until the Baron is within 400,
##      then the burst that downs him lands: "Lt. Brenner is down." His second breaks for home. C-E take
##      no damage before that (spread out, they still collided and fell before the Baron arrived).
##   4. Win: two-seater home and C-E destroyed. Two-seater lost: failed_defence.html. The debriefing is the
##      letter to Brenner's mother.

const AERODROME := Vector3(8400, 0, 7750)
const HOME_RANGE := 300.0
const DIVE_AT := 60.0
const AWAY := 1500.0
const LEAVE_RANGE := 900.0
const LEAVE_TIME := 5.0
const CLOSE_RANGE := 400.0

var brenner: Aircraft
var second: Aircraft
var two_seater: Aircraft
var camel_a: Aircraft
var camel_b: Aircraft
var attackers: Array[Aircraft] = []  # C-E
var stalkers: Array[Aircraft] = []
var stage := 0  # 0 cruise, 1 dive, 2 Brenner away, 3 Brenner in trouble, 4 Brenner down
var dive_time := 0.0
var safe := false
var _away_from_two_seater := 0.0
var _stalked := false


func start() -> void:
	owns_win = true
	brenner = plane(3002)
	second = plane(3003)
	two_seater = plane(3004)
	camel_a = plane(3010)
	camel_b = plane(3011)
	attackers.assign([plane(3012), plane(3013), plane(3014)])
	stalkers.assign([plane(3015), plane(3016)])
	mark_on_map(AERODROME)
	message("Bring the two-seater home. Brenner and his second have your tail.", 6.0)


func _behind(p: Aircraft, back: float, side: float, up: float) -> Vector3:
	var f := Vector3(p.flight_basis.z.x, 0.0, p.flight_basis.z.z).normalized()
	return p.global_position - f * back + f.cross(Vector3.UP) * side + Vector3.UP * up


func step(dt: float) -> void:
	track_markers()
	var p := world.player
	if not alive(p):
		return
	match stage:
		0:
			if now() >= DIVE_AT:
				stage = 1
				dive_time = now()
				reveal(camel_a, _behind(p, 300.0, -60.0, 120.0), [goal(Aircraft.G_ATTACK, p.object_id)], p.global_position - _behind(p, 300.0, -60.0, 120.0))
				reveal(camel_b, _behind(p, 340.0, 80.0, 140.0), [goal(Aircraft.G_ATTACK, p.object_id)], p.global_position - _behind(p, 340.0, 80.0, 140.0))
				if alive(brenner):
					attack(brenner, camel_a)
				if alive(second):
					attack(second, camel_b)
				message("Camels on your tail!", 5.0)
		1:
			if not alive(camel_a) or now() >= dive_time + 15.0:
				stage = 2
				var away := two_seater.global_position + Vector3(AWAY, 0.0, 0.0)
				away.x = minf(away.x, world.map_bounds.end.x - 400.0)
				away.y = 600.0
				if alive(brenner):
					fly_to(brenner, away, [goal(Aircraft.G_ATTACK, camel_b.object_id)], 200.0)
					brenner.set("damage_scale", 0.0)  # he must live until the end; his death is scripted
				if alive(second):
					formation(second, brenner, Vector3(-30.0, 0.0, -30.0))
				if alive(camel_b):
					attack(camel_b, brenner)
				message("Brenner chases the other one away. Stay with the two-seater.", 6.0)
		2, 3, 4:
			pass
	if not safe:
		_guard_two_seater(dt)
		if stage >= 2 and two_seater and alive(two_seater) and near(two_seater, AERODROME, HOME_RANGE, true):
			safe = true
			hide(two_seater)  # landed
			_brenner_in_trouble()
	if stage == 3 and alive(brenner) and near(p, brenner, CLOSE_RANGE):
		stage = 4
		brenner.set("damage_scale", 1.0)
		damage(brenner, brenner.health + 1.0, attackers[0])
		message("Lt. Brenner is down.", 6.0)
		if alive(second):
			fly_to(second, Vector3(AERODROME.x, 500.0, AERODROME.z), [goal(Aircraft.G_RETALIATE_OFF)], 300.0)
		for a in attackers:
			if alive(a):
				a.set("damage_scale", 1.0)
				attack(a, p)
	if stage == 4 and attackers.all(func(a): return not alive(a)):
		win()


## Before it is home: leaving the two-seater for long brings two Camels down on it.
func _guard_two_seater(dt: float) -> void:
	if _stalked or two_seater == null or not alive(two_seater) or stage < 2:
		return
	_away_from_two_seater = _away_from_two_seater + dt if not near(world.player, two_seater, LEAVE_RANGE) else 0.0
	if _away_from_two_seater > LEAVE_TIME:
		_stalked = true
		for i in stalkers.size():
			var at := _behind(two_seater, 350.0, (i * 2 - 1) * 80.0, 100.0)
			reveal(stalkers[i], at, [goal(Aircraft.G_ATTACK, two_seater.object_id)], two_seater.global_position - at)
		message("Camels on the two-seater!", 5.0)


func _brenner_in_trouble() -> void:
	stage = 3
	message("The two-seater is down safely. Brenner is in trouble!", 6.0)
	if brenner == null or not alive(brenner):
		return
	track_on_map(brenner)
	for i in attackers.size():
		var at := _behind(brenner, 400.0 + i * 120.0, (i - 1) * 320.0, 80.0 + i * 40.0)
		reveal(attackers[i], at, [goal(Aircraft.G_ATTACK, brenner.object_id)], brenner.global_position - at)
		attackers[i].set("damage_scale", 0.0)  # they must still be there when the Baron arrives
