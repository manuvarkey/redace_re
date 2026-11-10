extends "res://mods/redbaron/missions/objective.gd"
## Mission 1, Hawker: a duel with no one else in the sky. The original rules (Hawker is the destroy group, the
## time limit a cap) plus objective.gd (intro, priority bracket, escape fails at once with a warning near the edge).
## Hawker out-turns the Albatros but is slower in a straight line (mission file). This script flies him:
##   duel     gun attack on the Baron. When the Baron settles on his tail (inside SETTLE_RANGE, in Hawker's rear
##            cone, nose on him) for SETTLE_TIME, Hawker breaks hard to one side and down for EVADE_TIME, then
##            fights on; he cannot break again for RECOVERY s, which is the Baron's window.
##   opening  he first carries on across the Baron's track, climbing, for OPENING s, then turns in.
##   retreat  at RETREAT_AT s, or once he has lost RETREAT_DAMAGE of his endurance (from DAMAGE_RETREAT_AFTER s on), he
##            gives up the fight: rolls
##            away and dives for the British lines (south) at full throttle, retaliation off, no more breaks.
##            HUD: "Hawker breaks away ...". Slower than the Albatros, he can be caught before the edge.

const HAWKER := 3002
const SETTLE_RANGE := 320.0
const SETTLE_TIME := 1.2
const EVADE_TIME := 1.8
const RECOVERY := 7.0
const RETREAT_AT := 200.0
const RETREAT_DAMAGE := 0.6
const DAMAGE_RETREAT_AFTER := 90.0  # a lucky early burst does not end the duel at once
const OPENING := 7.0  # he first crosses ahead of the Baron, climbing, so the fight opens as a turning fight
const RETREAT_HEIGHT := 260.0

var hawker: Aircraft
var retreating := false
var _settled := 0.0
var _next_break := 0.0
var _check := 0.0


func start() -> void:
	super.start()
	hawker = plane(HAWKER)
	# opening: carry on across the Baron's track, climbing, then turn in to attack (not nose to nose from the start)
	var cross := hawker.global_position + hawker.flight_basis.z * (hawker.high_speed * OPENING) + Vector3.UP * 80.0
	var plan := [goal(Aircraft.G_RETALIATE_ON), goal(Aircraft.G_WAYPOINT, 0, cross, 150.0),
		goal(Aircraft.G_ATTACK, world.player.object_id)]
	var head := hawker.current_goal()
	if int(head.get("type", 0)) == Aircraft.G_APPEAR:
		plan.push_front(head)  # still to be put in the air
	set_goals(hawker, plan)


func step(dt: float) -> void:
	super.step(dt)
	if hawker == null or not alive(hawker) or not hawker.present():
		return
	var p := world.player
	if not alive(p):
		return
	if not retreating and (now() >= RETREAT_AT or (now() >= DAMAGE_RETREAT_AFTER
			and hawker.health <= hawker.endurance * (1.0 - RETREAT_DAMAGE))):
		_retreat()
		return
	if retreating:
		return
	_check -= dt
	if _check > 0.0:
		return
	_check = 0.1
	if _on_his_tail(p):
		_settled += 0.1
	else:
		_settled = maxf(_settled - 0.2, 0.0)
	if _settled >= SETTLE_TIME and now() >= _next_break and int(hawker.current_goal().get("type", 0)) == Aircraft.G_ATTACK:
		_settled = 0.0
		_next_break = now() + EVADE_TIME + RECOVERY
		var f := hawker.flight_basis
		var side := f.x * (1.0 if randf() < 0.5 else -1.0)
		var to := hawker.global_position + f.z * 120.0 + side * 220.0 + Vector3.DOWN * 60.0
		if world.height_above_ground(to) < 120.0:
			to.y += 120.0
		hawker._push_goal({"type": Aircraft.G_EVADE, "pos": to, "radius": EVADE_TIME, "targetid": 0})


## The Baron is close behind Hawker with his nose on him.
func _on_his_tail(p: Aircraft) -> bool:
	var to_p := p.global_position - hawker.global_position
	var d := to_p.length()
	if d > SETTLE_RANGE or d < 1.0:
		return false
	var behind := -hawker.flight_basis.z.dot(to_p / d)  # 1 = straight behind him
	var aimed := p.flight_basis.z.dot(-to_p / d)  # 1 = the Baron's nose on him
	return behind > 0.6 and aimed > 0.9


func _retreat() -> void:
	retreating = true
	var b := world.map_bounds
	var at := hawker.global_position
	var home := Vector3(clampf(at.x, b.position.x + 600.0, b.end.x - 600.0), world.ground_height(at) + RETREAT_HEIGHT,
		b.end.y + 600.0)
	hawker.throttle = 1.0
	set_goals(hawker, [goal(Aircraft.G_RETALIATE_OFF), goal(Aircraft.G_WAYPOINT, 0, home, 200.0)])
	objective("Hawker breaks away for his lines! Cut him off before he crosses.", "Catch Hawker before he reaches his lines")
