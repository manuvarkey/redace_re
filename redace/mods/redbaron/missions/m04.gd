extends "res://mods/redbaron/missions/objective.gd"
## Mission 4, Scramble: the original rules plus objective.gd's intro, counter and marker. Brenner waits
## on the runway behind the Baron and takes off once the Baron is airborne (a plane with no goals stays
## parked), then goes for the raiders.

const AIRBORNE_HEIGHT := 15.0

var brenner: Aircraft
var launched := false


func start() -> void:
	super.start()
	brenner = plane(3002)


func step(dt: float) -> void:
	super.step(dt)
	var p := world.player
	if launched or brenner == null or not alive(brenner):
		return
	if p.state != Aircraft.State.GROUND and world.height_above_ground(p.global_position) > AIRBORNE_HEIGHT:
		launched = true
		set_goals(brenner, [goal(Aircraft.G_TAKEOFF), goal(Aircraft.G_ATTACK, -9)])
