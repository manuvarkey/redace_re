extends "res://mods/redbaron/missions/objective.gd"
## Mission 4, Scramble: the original rules plus objective.gd's intro, counter and marker.
## - Brenner and a second pilot are already in the air over the field (mission file); the Baron takes off.
## - Two waves, each four RE8 bombers (one bomb each, a level run on the hangars) and three S.E.5as flying
##   1400 ahead of them at the defenders. Bombers start in the north-east corner, about 4100 out, and
##   come round by the east (about 60 s); the fighters about 30 s out. Wave 2 waits hidden and comes in
##   from the same places when wave 1 is down, or at WAVE2_AT s. Each bomber has its own dogleg point
##   (a shared one made them collide).

const WAVE1 := [3010, 3011, 3012, 3013, 3014, 3015, 3016]
const WAVE2 := [3020, 3021, 3022, 3023, 3024, 3025, 3026]
const WAVE2_AT := 150.0
# wave 1's starting places (mission file), used again for wave 2; bombers 850 high: the ground is about 550
const BOMBER_STARTS := [Vector3(9150, 850, 4850), Vector3(9250, 870, 4980), Vector3(9150, 890, 5110), Vector3(9250, 910, 5240)]
const FIGHTER_STARTS := [Vector3(9050, 880, 6300), Vector3(9150, 910, 6550), Vector3(9050, 940, 6800)]

var wave2_sent := false


func start() -> void:
	super.start()


func step(dt: float) -> void:
	super.step(dt)
	if not wave2_sent and (now() >= WAVE2_AT or WAVE1.all(func(id): return not plane(id).present())):
		send_wave2()


func send_wave2() -> void:
	wave2_sent = true
	for i in WAVE2.size():
		var q := plane(WAVE2[i])
		if q == null or not q.hidden:
			continue
		var bomber := i < 4
		var at: Vector3 = BOMBER_STARTS[i] if bomber else FIGHTER_STARTS[i - 4]
		var dogleg := Vector3(9100, 750, 7250 + i * 150)
		var then := [goal(Aircraft.G_RETALIATE_OFF), goal(Aircraft.G_WAYPOINT, 0, dogleg, 250.0),
			goal(Aircraft.G_BOMB_RUN, -3), goal(Aircraft.G_ATTACK, -8)] if bomber else [goal(Aircraft.G_ATTACK, -8)]
		reveal(q, at, then, (dogleg if bomber else Vector3(6200, 0, 7450)) - at)
	message("A second wave is coming in from the north-east!", 6.0)
