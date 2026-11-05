extends "res://mods/redbaron/missions/objective.gd"
## Mission 4, Scramble: the original rules plus objective.gd's intro, counter and marker.
## - Brenner waits on the runway behind the Baron and takes off once the Baron is airborne (a plane with
##   no goals stays parked), then goes for the raiders.
## - Two waves, each four RE8 bombers (one bomb each, a level run on the hangars) and three S.E.5as flying
##   700 ahead of them at the defenders. Wave 1 starts about 3000 east; wave 2 waits hidden and comes in
##   from the same place when wave 1 is down, or at WAVE2_AT s.

const AIRBORNE_HEIGHT := 15.0
const WAVE1 := [3010, 3011, 3012, 3013, 3014, 3015, 3016]
const WAVE2 := [3020, 3021, 3022, 3023, 3024, 3025, 3026]
const WAVE2_AT := 150.0
const WAVE_HEIGHT := 600.0

var brenner: Aircraft
var launched := false
var wave2_sent := false


func start() -> void:
	super.start()
	brenner = plane(3002)


func step(dt: float) -> void:
	super.step(dt)
	var p := world.player
	if not launched and brenner and alive(brenner) and p.state != Aircraft.State.GROUND \
			and world.height_above_ground(p.global_position) > AIRBORNE_HEIGHT:
		launched = true
		set_goals(brenner, [goal(Aircraft.G_TAKEOFF), goal(Aircraft.G_ATTACK, -9)])
	if not wave2_sent and (now() >= WAVE2_AT or WAVE1.all(func(id): return not plane(id).present())):
		send_wave2()


func send_wave2() -> void:
	wave2_sent = true
	for id in WAVE2:
		var q := plane(id)
		if q == null or not q.hidden:
			continue
		var at := Vector3(q.global_position.x, WAVE_HEIGHT + (id % 10) * 20.0, q.global_position.z)
		var bomber := q.plane_name == "re8"
		var then := [goal(Aircraft.G_RETALIATE_OFF), goal(Aircraft.G_BOMB_RUN, -3), goal(Aircraft.G_ATTACK, -8)] \
			if bomber else [goal(Aircraft.G_ATTACK, -8)]
		reveal(q, at, then, Vector3.LEFT)
	message("A second wave is coming in from the east!", 6.0)
