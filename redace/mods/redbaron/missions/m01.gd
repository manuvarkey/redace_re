extends "res://mods/redbaron/missions/objective.gd"
## Mission 1, Hawker: a duel with no one else in the sky. The original rules (Hawker is the destroy group, the
## time limit a cap) plus objective.gd (intro, priority bracket, escape fails at once with a warning near the edge).
## Hawker out-turns the Albatros but is slower in a straight line (mission file). This script flies him:
##   duel     gun attack on the Baron. When the Baron settles on his tail (inside SETTLE_RANGE, in Hawker's rear
##            cone, nose on him) for SETTLE_TIME, Hawker breaks hard to one side and down for EVADE_TIME, then
##            fights on; he cannot break again for RECOVERY s, which is the Baron's window.
##   opening  he first carries on across the Baron's track, climbing a little, for OPENING s, then turns in; if the
##            Baron points at him inside OPENING_REACT first, he breaks into a climbing turn and fights at once.
##   head-on  the Baron nose-on in front of him inside HEAD_ON_RANGE: he breaks to one side (HEAD_ON_COOLDOWN between),
##            so a head-on pass is no free kill: the Baron has to get behind him.
##   early    for the first EARLY_TIME s he takes EARLY_SCALE of each hit: one good burst in the first pass does not
##            end the duel (the autopilot Baron still downed him in 17 s with full damage).
##   escape   within EDGE_ESCAPE of the south edge in his retreat he is away (the ground ends there and the original
##            ceiling, reading the void below, stalled him on the edge for a minute and a half).
## Both start about 330-360 over the ground and his opening stays under the original ceiling (above 400 over the ground
## the target speed drops by half the excess: he bled from 87 to 63 and died in 11 s, 11 November 2026).
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
const OPENING_CLIMB := 20.0
const CEILING_MARGIN := 370.0  # keep him under the ceiling (400 over the ground)
const OPENING_REACT := 700.0
const HEAD_ON_RANGE := 450.0
const HEAD_ON_COOLDOWN := 3.0
const EARLY_TIME := 45.0
const EARLY_SCALE := 0.6
const EDGE_ESCAPE := 300.0

var hawker: Aircraft
var retreating := false
var _settled := 0.0
var _next_break := 0.0
var _check := 0.0
var _opening := true
var _next_head_on := 0.0


func start() -> void:
	super.start()
	hawker = plane(HAWKER)
	# opening: carry on across the Baron's track, climbing, then turn in to attack (not nose to nose from the start)
	var cross := hawker.global_position + hawker.flight_basis.z * (hawker.high_speed * OPENING) + Vector3.UP * OPENING_CLIMB
	cross.y = minf(cross.y, world.ground_height(cross) + CEILING_MARGIN)
	var plan := [goal(Aircraft.G_RETALIATE_ON), goal(Aircraft.G_WAYPOINT, 0, cross, 150.0),
		goal(Aircraft.G_ATTACK, world.player.object_id)]
	var head := hawker.current_goal()
	if int(head.get("type", 0)) == Aircraft.G_APPEAR:
		plan.push_front(head)  # still to be put in the air
	set_goals(hawker, plan)
	hawker.set("damage_scale", EARLY_SCALE)
	after(EARLY_TIME, func() -> void:
		if hawker and alive(hawker):
			hawker.set("damage_scale", 1.0))


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
		if hawker.global_position.z > world.map_bounds.end.y - EDGE_ESCAPE:
			hawker.left_map = true  # away over his lines (objective.gd ends it: "escaped")
		return
	_check -= dt
	if _check > 0.0:
		return
	_check = 0.1
	var goal_type := int(hawker.current_goal().get("type", 0))
	if _opening and goal_type == Aircraft.G_ATTACK:
		_opening = false
	if _opening and goal_type == Aircraft.G_WAYPOINT and _pointed_at(p, OPENING_REACT, 0.3):
		_opening = false  # the Baron comes straight for him: he turns to fight now
		set_goals(hawker, [goal(Aircraft.G_RETALIATE_ON), goal(Aircraft.G_ATTACK, p.object_id)])
		_break(p, 40.0)
	elif not _opening and now() >= _next_head_on and goal_type == Aircraft.G_ATTACK and _pointed_at(p, HEAD_ON_RANGE, 0.7):
		_next_head_on = now() + HEAD_ON_COOLDOWN
		_break(p, -20.0 if randf() < 0.5 else 30.0)
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


## The Baron in front of Hawker (cos of the angle off his nose > front), inside range, his nose on Hawker.
func _pointed_at(p: Aircraft, within: float, front: float) -> bool:
	var to_p := p.global_position - hawker.global_position
	var d := to_p.length()
	if d > within or d < 1.0:
		return false
	return hawker.flight_basis.z.dot(to_p / d) > front and p.flight_basis.z.dot(-to_p / d) > 0.95


## A hard break out of the Baron's line of fire, toward the side the Baron is not on, climbing by up.
func _break(p: Aircraft, up: float) -> void:
	var f := hawker.flight_basis
	var side := f.x if f.x.dot(p.global_position - hawker.global_position) < 0.0 else -f.x
	var to := hawker.global_position + f.z * 120.0 + side * 240.0 + Vector3.UP * up
	to.y = clampf(to.y, world.ground_height(to) + 120.0, world.ground_height(to) + CEILING_MARGIN)
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
