extends "res://mods/redbaron/mission_script.gd"
## Mission 8, Wounded (reworked after playtests; see IMPLEMENTATION_NOTES):
##   1. Four F.E.2ds (aircodh2_rb stand-ins with observers' guns) cross our lines and turn east for home.
##      Objective: shoot them down before they leave the map. A HUD counter shows how many are down; the
##      first one to leave the map fails the mission ("An F.E.2d Got Away").
##   2. When none is left in the air: "Return to base." Brenner forms up on the Baron.
##   3. Halfway home (flat distance to the aerodrome down to half of what it was) two Nieuports appear behind and
##      above, AMBUSH_BACK out, so they can be seen coming: "Scouts diving behind us!", a short minimap and bracket
##      highlight, and Brenner turns to engage. They close and open fire (tracers and their guns); the first hit
##      from either (or, failing that, once one is within FIRE_RANGE after WOUND_FALLBACK s, WOUND_CAP at the latest)
##      is the wound: an impact sound and a
##      jolt, then the view dims and blurs, the throttle is held at half, the guns stop and the HUD says "You are
##      hit. Land at the aerodrome." Until then the ambushers dive at AMBUSH_SPEED and take no damage (they must live to
##      close and fire); afterwards they fly and take damage as normal.
##      From the wound on the Baron takes a quarter of each hit and keeps at least half his endurance; Brenner, the
##      pale blue bracket, fights them off (HUD lines when he engages and for each kill), then forms up on the Baron.
##      The aerodrome blinks on the minimap. The second Nieuport attacks for PURSUIT_TIME, then turns for home.
##      The Baron carries 10 rockets (ordinancetype 2).
##   4. Landing within 300 of the aerodrome wins; a crash loses (the original "plane destroyed").

const AERODROME := Vector3(6200, 0, 7450)
const HOME_RANGE := 450.0  # the field reaches about 400 from the marker: a landing at the far end of the strip counts
const THROTTLE_CAP := 0.5
const BRITISH_EDGE_X := 10000.0  # well east of the map box (x up to 9358): planes leave 150 past it, before the waypoint
const PURSUIT_TIME := 20.0  # the second Nieuport attacks this long, then turns for home
const WOUND_DAMAGE := 20.0  # the ambush burst (never the last of the Baron's endurance)
const WOUNDED_DAMAGE_SCALE := 0.25  # after the wound the Baron takes a quarter of each hit ...
const WOUNDED_MIN_HEALTH := 0.5  # ... with at least half his endurance left, so Brenner has time
const MESSAGE_GAP := 4.0
const AMBUSH_BACK := 450.0  # how far behind the ambushers appear (they were 250: on top of him at once; at 750
const AMBUSH_UP := 220.0  # they never caught a Baron flying home at full throttle)
const AMBUSH_SPEED := 130.0  # diving in, faster than the Albatros (110): they close in about 10 s
const FIRE_RANGE := 350.0
const CLOSE_IN := 280.0
const WOUND_FALLBACK := 15.0  # no hit by then: the wound comes once one of them is within FIRE_RANGE ...
const WOUND_CAP := 30.0  # ... or at the latest this long after they appear
const AMBUSHER_SCALE := 0.0  # damage the ambushers take before the wound: they must live to close and fire

var brenner: Aircraft
var fe2ds: Array[Aircraft] = []
var ambushers: Array[Aircraft] = []
var returning := false
var return_distance := 0.0
var ambushed := false
var ambush_time := -1.0
var wounded := false
var wound_time := -1.0
var last_event := -100.0
var home_marker: Dictionary
var _brenner_kills := 0
var _stock_speeds := {}


func start() -> void:
	owns_win = true
	end_messages["escaped"] = "An F.E.2d Got Away"
	brenner = plane(3002)
	ambushers.assign([plane(3020), plane(3021)])
	for p in world.planes:
		if p.plane_name == "aircodh2_rb":
			fe2ds.append(p)
	home_marker = mark_destination(AERODROME)
	for f in fe2ds:
		mark_priority(f, "F.E.2d")
	objective("F.E.2ds over our lines! Shoot them down before they get home.", "Shoot down the four F.E.2ds (marked red)")
	last_event = now()
	for a in ambushers:
		if a:
			a.damaged.connect(_on_ambusher_damaged)
			a.destroyed.connect(_on_ambusher_down)
	var p := world.player
	if p and p.has_signal("damaged"):
		p.damaged.connect(_on_player_damaged)


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
			mark_ally(brenner, "Brenner")
			home_marker.pulse = true
			_event("The F.E.2d flight is destroyed. Well done! Return to base.")
			overlay().cue("objective")
			overlay().set_objective("Return to the aerodrome (blinking)")
		return
	if not ambushed:
		if now() >= last_event + MESSAGE_GAP and distance(p, AERODROME, true) <= return_distance * 0.5:
			ambush()
		return
	if not wounded:
		_close_in(p)
		var closest: Aircraft = null
		for a in ambushers:
			if a and alive(a) and (closest == null or distance(a, p) < distance(closest, p)):
				closest = a
		if now() >= ambush_time + WOUND_CAP or (now() >= ambush_time + WOUND_FALLBACK and closest and near(closest, p, FIRE_RANGE)):
			wound(closest if closest else ambushers[0])
		return
	p.throttle = minf(p.throttle, THROTTLE_CAP)
	p.fire_input = false
	p.secondary_input = false
	if p.state == Aircraft.State.GROUND and near(p, AERODROME, HOME_RANGE, true):
		win()


## Before the wound the ambushers dive straight at the Baron at full throttle (a gun attack matches the target's
## speed, so from behind they never closed), and open fire (their goals from the ambush) inside CLOSE_IN.
func _close_in(p: Aircraft) -> void:
	for i in ambushers.size():
		var a := ambushers[i]
		if a == null or not alive(a) or a.hidden or int(a.current_goal().get("type", 0)) == Aircraft.G_APPEAR:
			continue
		if distance(a, p) > CLOSE_IN:
			a.throttle = 1.0
			if int(a.current_goal().get("type", 0)) != Aircraft.G_WAYPOINT:
				a._push_goal(goal(Aircraft.G_WAYPOINT, 0, p.global_position, 30.0))
			a.current_goal().pos = p.global_position + p.flight_basis.z * 40.0
		elif int(a.current_goal().get("type", 0)) == Aircraft.G_WAYPOINT:
			a._remove_goal(a.current_goal())


## Two Nieuports appear behind and above, far enough out to be seen diving in; Brenner turns to meet them.
func ambush() -> void:
	if ambushed:
		return
	ambushed = true
	ambush_time = now()
	var p := world.player
	var flat := Vector3(p.flight_basis.z.x, 0.0, p.flight_basis.z.z).normalized()
	var side := flat.cross(Vector3.UP)
	var shown: Array[Aircraft] = []
	for i in ambushers.size():
		var q := ambushers[i]
		if q == null or not q.hidden:
			continue
		var at := p.global_position - flat * (AMBUSH_BACK + 80.0 * i) + side * (110.0 - 220.0 * i) + Vector3.UP * (AMBUSH_UP + 30.0 * i)
		var then := [goal(Aircraft.G_ATTACK, p.object_id)]
		if i == 1:
			then = [goal(Aircraft.G_RETALIATE_ON, 0, Vector3.ZERO, PURSUIT_TIME), goal(Aircraft.G_ATTACK, p.object_id),
				goal(Aircraft.G_WAYPOINT, 0, Vector3(BRITISH_EDGE_X, at.y, at.z), 200.0)]
		_stock_speeds[q] = q.high_speed
		q.high_speed = AMBUSH_SPEED
		reveal(q, at, then, p.global_position - at)
		q.set("damage_scale", AMBUSHER_SCALE)
		q.set("persistent", 1)  # no dodging Brenner's fire on the way in
		shown.append(q)
	highlight(shown, 7.0, "Nieuport")
	warn("Scouts diving behind us!", 4.0)
	if brenner and alive(brenner) and ambushers[0]:
		var form := goal(Aircraft.G_FORMATION, p.object_id)
		form.offset = Vector3(-30.0, 0.0, -30.0)
		attack(brenner, ambushers[0], [goal(Aircraft.G_ATTACK, ambushers[1].object_id), form])
	last_event = now()


func _on_player_damaged(_p: Aircraft, _amount: float, attacker: Variant) -> void:
	if ambushed and not wounded and attacker in ambushers:
		wound(attacker)


func _on_ambusher_damaged(q: Aircraft, _amount: float, attacker: Variant) -> void:
	if ambushed and attacker == brenner and once("brenner_on"):
		message("Brenner is on his tail!", 3.0)


func _on_ambusher_down(_q: Aircraft) -> void:
	_brenner_kills += 1
	if not wounded:
		return
	if ambushers.all(func(a: Aircraft) -> bool: return a == null or not alive(a)):
		message("Both Nieuports down. Brenner is on your wing. Land at the aerodrome." if alive(brenner)
			else "Both Nieuports down. Land at the aerodrome.", 5.0)
	elif alive(brenner):
		message("One Nieuport down! Brenner is after the other.", 4.0)


## The burst that wounds the Baron: impact and jolt, then the impaired view and the order to land.
func wound(attacker: Variant) -> void:
	if wounded:
		return
	wounded = true
	wound_time = now()
	print("mission 8: wounded at %.1f s" % now())
	var p := world.player
	overlay().cue("rico2.wav")
	overlay().cue("knock1.wav")
	overlay().jolt(0.4, 1.4)
	damage(p, minf(WOUND_DAMAGE, p.health - 10.0), attacker)
	# the wound cripples the plane, not the airframe: from here on the Baron takes a quarter of each hit
	# and keeps at least half his endurance, which leaves Brenner the time to deal with the ambush
	p.health = maxf(p.health, p.endurance * WOUNDED_MIN_HEALTH)
	p.set("damage_scale", WOUNDED_DAMAGE_SCALE)
	for a in ambushers:
		if a:
			a.set("damage_scale", 1.0)
			a.high_speed = _stock_speeds.get(a, a.high_speed)
			a.set("persistent", -1)
	after(0.35, func() -> void:
		overlay().wound = 1.0
		_event("You are hit. Land at the aerodrome.")
		overlay().set_objective("Land at the aerodrome (blinking). Brenner covers you"))
