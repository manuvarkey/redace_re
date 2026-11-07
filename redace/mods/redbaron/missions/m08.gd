extends "res://mods/redbaron/mission_script.gd"
## Mission 8, Wounded (reworked after playtests; see IMPLEMENTATION_NOTES):
##   1. Four F.E.2ds (aircodh2_rb stand-ins with observers' guns) cross our lines and turn east for home.
##      Objective: shoot them down before they leave the map. A HUD counter shows how many are down; the
##      first one to leave the map fails the mission ("An F.E.2d Got Away").
##   2. When none is left in the air: "Return to base." Brenner forms up on the Baron.
##   3. Halfway home (flat distance to the aerodrome down to half of what it was) two Nieuports dive in
##      from behind and above; their first burst wounds the Baron: the view dims and blurs, the throttle
##      is held at half and the guns stop. From then on he takes a quarter of each hit and keeps at least
##      half his endurance. Brenner, on his wing, goes for one Nieuport at once, then the other; the
##      second attacks for 20 s, then breaks off. The Baron carries 10 rockets (ordinancetype 2).
##   4. Landing within 300 of the aerodrome wins; a crash loses (the original "plane destroyed").

const AERODROME := Vector3(6200, 0, 7450)
const HOME_RANGE := 300.0
const THROTTLE_CAP := 0.5
const BRITISH_EDGE_X := 10000.0  # well east of the map box (x up to 9358): planes leave 150 past it, before the waypoint
const PURSUIT_TIME := 20.0  # the second Nieuport attacks this long, then turns for home
const WOUND_DAMAGE := 20.0  # the ambush burst (never the last of the Baron's endurance)
const WOUNDED_DAMAGE_SCALE := 0.25  # after the wound the Baron takes a quarter of each hit ...
const WOUNDED_MIN_HEALTH := 0.5  # ... with at least half his endurance left, so Brenner has time
const MESSAGE_GAP := 4.0

var brenner: Aircraft
var fe2ds: Array[Aircraft] = []
var ambushers: Array[Aircraft] = []
var returning := false
var return_distance := 0.0
var wounded := false
var wound_time := -1.0
var last_event := -100.0


func start() -> void:
	owns_win = true
	end_messages["escaped"] = "An F.E.2d Got Away"
	brenner = plane(3002)
	ambushers.assign([plane(3020), plane(3021)])
	for p in world.planes:
		if p.plane_name == "aircodh2_rb":
			fe2ds.append(p)
	mark_on_map(AERODROME)
	message("F.E.2ds over our lines! Shoot them down before they get home.", 6.0)
	last_event = now()


func _event(text: String) -> void:
	last_event = now()
	message(text, 6.0)


func _down() -> int:
	return fe2ds.filter(func(f: Aircraft) -> bool: return not alive(f)).size()


func _escaped() -> int:
	return fe2ds.filter(func(f: Aircraft) -> bool: return alive(f) and f.left_map).size()


func step(_dt: float) -> void:
	var p := world.player
	if not alive(p):
		return
	if not returning:
		if _escaped() > 0:
			overlay().set_counter("")
			lose("escaped")  # the objective: none may get home (failed_escaped.html after the defeat page)
			return
		overlay().set_counter("F.E.2d down %d / %d" % [_down(), fe2ds.size()])
		if _down() == fe2ds.size() and now() >= last_event + MESSAGE_GAP:
			returning = true
			return_distance = distance(p, AERODROME, true)
			overlay().set_counter("")
			formation(brenner, p, Vector3(-30.0, 0.0, -30.0))
			_event("The F.E.2d flight is destroyed. Well done! Return to base.")
		return
	if not wounded:
		if now() >= last_event + MESSAGE_GAP and distance(p, AERODROME, true) <= return_distance * 0.5:
			ambush()
		return
	p.throttle = minf(p.throttle, THROTTLE_CAP)
	p.fire_input = false
	p.secondary_input = false
	if p.state == Aircraft.State.GROUND and near(p, AERODROME, HOME_RANGE, true):
		win()


## Two Nieuports dive in from behind and above; the first burst wounds the Baron.
func ambush() -> void:
	if wounded:
		return
	wounded = true
	wound_time = now()
	print("mission 8: wounded at %.1f s" % now())
	var p := world.player
	var flat := Vector3(p.flight_basis.z.x, 0.0, p.flight_basis.z.z).normalized()
	var side := flat.cross(Vector3.UP)
	for i in ambushers.size():
		var q := ambushers[i]
		if q == null or not q.hidden:
			continue
		var at := p.global_position - flat * (250.0 + 60.0 * i) + side * (120.0 - 240.0 * i) + Vector3.UP * (80.0 + 30.0 * i)
		var then := [goal(Aircraft.G_ATTACK, p.object_id)]
		if i == 1:
			then = [goal(Aircraft.G_RETALIATE_ON, 0, Vector3.ZERO, PURSUIT_TIME), goal(Aircraft.G_ATTACK, p.object_id),
				goal(Aircraft.G_WAYPOINT, 0, Vector3(BRITISH_EDGE_X, at.y, at.z), 200.0)]
		reveal(q, at, then, p.global_position - at)
	damage(p, minf(WOUND_DAMAGE, p.health - 10.0), ambushers[0])
	# the wound cripples the plane, not the airframe: from here on the Baron takes a quarter of each hit
	# and keeps at least half his endurance, which leaves Brenner the time to deal with the ambush
	p.health = maxf(p.health, p.endurance * WOUNDED_MIN_HEALTH)
	p.set("damage_scale", WOUNDED_DAMAGE_SCALE)
	overlay().wound = 1.0
	if brenner and alive(brenner) and ambushers[0]:
		var form := goal(Aircraft.G_FORMATION, p.object_id)
		form.offset = Vector3(-30.0, 0.0, -30.0)
		attack(brenner, ambushers[0], [goal(Aircraft.G_ATTACK, ambushers[1].object_id), form])
	_event("Ambush! You are hit. Land at the aerodrome.")
