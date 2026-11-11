extends "res://mods/redbaron/mission_script.gd"
## Mission 11, Formation (reworked 11 November 2026 to the user's outline): escort a damaged two-seater home.
##   Opening      the Baron starts close behind it, Brenner and his second (Hartwig) beside him. "Join the damaged
##                two-seater. Escort it home." Two-seater and aerodrome marked; its condition on the HUD throughout.
##   Encounter 1  two Camels from behind and to one side go for the two-seater; Brenner takes one, Hartwig stays on
##                the two-seater, the Baron must take the other. Broken (down, or their attack time is up and they turn
##                for home): "First attack broken. Stay with the two-seater." Brenner and Hartwig rejoin.
##   Encounter 2  after a breathing space, as the two-seater crosses the front: three scouts ahead, one high (on the
##                Baron) and a low pair (on the two-seater). Brenner and Hartwig take the high one. Low pair
##                broken: "The way is clear. Bring them through."
##   Encounter 3  three Camels from the rear quarter, one on the Baron, two on the two-seater. After a short joint fight
##                Brenner takes the pair, with Hartwig ("Brenner is covering the rear."). Then the story moment, staged
##                apart from the fight (never set off by the Baron's position): a camera cut-in with letterbox bars
##                (about 17 s) while the Baron flies on with the two-seater (autopilot, no damage). Over Brenner's
##                shoulder he chases the Camel on Hartwig's tail and shoots it down; then over the shoulder of the other
##                Camel, closed up behind him, its burst kills him. One caption at the end: "Brenner is down. Bring his
##                second home with the two-seater." Hartwig, smoking, is now a protected objective.
##   Encounter 4  once the Baron has had a moment to find Hartwig (and the last fight has thinned out), two fresh scouts
##                across the final approach, one on each protected plane (only one if two attackers are still close).
##   Home         each protected plane landing at the aerodrome is announced; with both down, "Return to the
##                aerodrome." and the Camels left break off. Win: the Baron within HOME_AREA of the aerodrome.
##   Lost         the Baron, the two-seater (failed_defence.html) or, once protected, Hartwig (failed_second.html).
## Encounters start on route progress and the state of the fight before; timers are only safeguards.

const AERODROME := Vector3(8400, 0, 7750)
const LAND_RANGE := 350.0  # a protected plane this close to the aerodrome lands (hidden: safe)
const HOME_AREA := 600.0
const START_HEALTH := 0.7  # the two-seater is already damaged
const TWO_SEATER_SCALE := 0.25  # ... but takes a quarter of each hit: two Camels on it for a few seconds (one mistake)
# must not end the mission (a pair took it from 70 % to nothing in 12 s at full damage, 8 s at half: head-on passes)
const HARTWIG_HEALTH := 0.5  # after the burst that killed Brenner
const HARTWIG_SCALE := 0.2  # once protected he takes a fifth of each hit: one Camel on his tail killed him in about 3 s
# at full damage and still in 3 s at a third (simulated in encounter 4): no time to switch to him
const W1 := [3010, 3011]
const W2 := [3012, 3013, 3014]  # high scout, low pair
const W3 := [3015, 3016, 3017]  # on the Baron, then the pair on the two-seater
const W4 := [3018, 3019]
const GAP := 12.0  # breathing space between attacks
const SAFEGUARD := 30.0  # an attack starts this long after the last at the latest
const COVER_AFTER := 8.0  # joint fight, then Brenner takes the pair
const STORY_AFTER := 9.0  # Brenner covering, then the story moment
const ESCORT := {3002: Vector3(-70.0, 35.0, -50.0), 3003: Vector3(70.0, 25.0, -50.0)}

var brenner: Aircraft
var hartwig: Aircraft
var two_seater: Aircraft
var home_marker: Dictionary
var stage := "opening"
var stage_time := 0.0
var two_seater_home := false
var hartwig_home := false
var hartwig_protected := false
var _withdrawn := {}
var _last_landing := -100.0  # Camels that broke off
var _cine_cam: Camera3D
var _cine_target: Aircraft
var _cine_quarry: Aircraft
var _player_autopilot := false
var _player_goals: Array[Dictionary] = []


func start() -> void:
	owns_win = true
	end_messages["second"] = "Brenner's Second Lost"
	brenner = plane(3002)
	hartwig = plane(3003)
	two_seater = plane(3004)
	two_seater.health = two_seater.endurance * START_HEALTH
	two_seater.set("damage_scale", TWO_SEATER_SCALE)
	home_marker = mark_destination(AERODROME)
	mark_protect(two_seater, "Two-seater")
	mark_ally(brenner, "Brenner")
	mark_ally(hartwig, "Hartwig")
	for w in [brenner, hartwig]:
		w.set("damage_scale", 0.0)  # Brenner's death is staged; Hartwig must live to be the last objective
		_escort(w)
	objective("Join the damaged two-seater. Escort it home.", "Escort the damaged two-seater (green) to the aerodrome")
	_set_stage("opening")


func _set_stage(s: String) -> void:
	stage = s
	stage_time = now()


func _since() -> float:
	return now() - stage_time


## A wingman on the two-seater (station keeping), or on the Baron once it has landed.
func _escort(w: Aircraft) -> void:
	if w == null or not alive(w):
		return
	var lead: Aircraft = two_seater if alive(two_seater) and not two_seater_home else world.player
	formation(w, lead, ESCORT[w.object_id])


func _flat_fwd(p: Aircraft) -> Vector3:
	return Vector3(p.flight_basis.z.x, 0.0, p.flight_basis.z.z).normalized()


## A point back / side / up from a plane in its flat frame (back < 0: ahead).
func _rel(p: Aircraft, back: float, side: float, up: float) -> Vector3:
	var f := _flat_fwd(p)
	var at := p.global_position - f * back + f.cross(Vector3.UP) * side + Vector3.UP * up
	var g := world.ground_height(at)
	at.y = clampf(at.y, g + 250.0, g + 380.0)  # above 400 the original ceiling slows a plane (to a stall)
	return at


## Brings in Camel id at pos, attacking target for at most limit s, then turning for home (south).
func _bring(id: int, pos: Vector3, target: Aircraft, limit: float) -> Aircraft:
	var c := plane(id)
	if c == null:
		return null
	var home := Vector3(pos.x, pos.y, world.map_bounds.end.y + 800.0)
	reveal(c, pos, [goal(Aircraft.G_RETALIATE_ON, 0, Vector3.ZERO, limit), goal(Aircraft.G_ATTACK, target.object_id),
		goal(Aircraft.G_RETALIATE_OFF), goal(Aircraft.G_WAYPOINT, 0, home, 300.0)], target.global_position - pos)
	return c


## An attack is broken when each of its planes is down, gone, or has turned for home.
func _broken(ids: Array) -> bool:
	for id in ids:
		var c := plane(id)
		if c == null or not alive(c) or not c.present() or c.hidden:
			continue
		if int(c.current_goal().get("type", 0)) in [Aircraft.G_WAYPOINT, Aircraft.G_RETALIATE_OFF] or _withdrawn.has(c):
			continue
		return false
	return true


## Enemies still fighting (not turned for home) within r of any of the planes given.
func _enemies_near(around: Array, r: float) -> int:
	var n := 0
	for q in world.planes:
		if not (q.groups & (1 << 9)) or not q.present() or not alive(q) or q.hidden:
			continue
		if int(q.current_goal().get("type", 0)) in [Aircraft.G_WAYPOINT, Aircraft.G_RETALIATE_OFF]:
			continue
		for o in around:
			if o and alive(o) and not o.hidden and near(q, o, r):
				n += 1
				break
	return n


func step(dt: float) -> void:
	var p := world.player
	if _cine_cam:
		_update_cinematic()
	if not alive(p):
		return
	if not two_seater_home and not alive(two_seater):
		lose("defence")
		return
	if hartwig_protected and not hartwig_home and not alive(hartwig):
		lose("second")
		return
	_update_hud()
	_landings()
	match stage:
		"opening":
			if (near(p, two_seater, 450.0) and _since() > 15.0) or _since() > 25.0:
				_encounter_1()
		"e1":
			if _broken(W1) and _since() > 6.0:
				message("First attack broken. Stay with the two-seater.", 5.0)
				overlay().cue("objective")
				for w in [brenner, hartwig]:
					_escort(w)
				_set_stage("after_e1")
		"after_e1":
			if (_since() > GAP and two_seater.global_position.z < 12300.0) or _since() > SAFEGUARD:
				_encounter_2()
		"e2":
			if _broken([W2[1], W2[2]]) and _since() > 6.0:
				message("The way is clear. Bring them through.", 5.0)
				overlay().cue("objective")
				for w in [brenner, hartwig]:
					_escort(w)
				_set_stage("after_e2")
		"after_e2":
			if (_since() > GAP and two_seater.global_position.z < 10300.0) or _since() > SAFEGUARD:
				_encounter_3()
		"e3":
			if _since() > COVER_AFTER:
				_brenner_covers()
		"cover":
			if _since() > STORY_AFTER:
				_story()
		"story":
			pass  # the cut-in runs on timers
		"after_story":
			var close := _enemies_near([two_seater, hartwig], 2000.0)
			if (_since() > 8.0 and close <= 1) or _since() > 25.0:
				_encounter_4(close >= 2)
		"e4", "home":
			pass
	if two_seater_home and hartwig_home and stage != "home" and now() >= _last_landing + 3.0:
		_set_stage("home")
		objective("Both are down safely. Return to the aerodrome.", "Return to the aerodrome (blinking)")
		home_marker.pulse = true
		for q in world.planes:
			if q.groups & (1 << 9) and q.present() and alive(q):
				set_goals(q, [goal(Aircraft.G_RETALIATE_OFF),
					goal(Aircraft.G_WAYPOINT, 0, Vector3(q.global_position.x, 600.0, world.map_bounds.end.y + 800.0), 300.0)])
	if stage == "home" and near(p, AERODROME, HOME_AREA, true):
		win()


func _update_hud() -> void:
	var lines: Array[String] = []
	if not two_seater_home:
		lines.append("Two-seater %d %%" % roundi(100.0 * two_seater.health / two_seater.endurance))
	else:
		lines.append("Two-seater home")
	if hartwig_protected:
		lines.append("Hartwig home" if hartwig_home else "Hartwig %d %%" % roundi(100.0 * maxf(hartwig.health, 0.0) / hartwig.endurance))
	overlay().set_counter("\n".join(lines))


## A protected plane near the aerodrome lands (hidden: safe).
func _landings() -> void:
	if not two_seater_home and alive(two_seater) and near(two_seater, AERODROME, LAND_RANGE, true):
		two_seater_home = true
		_last_landing = now()
		hide(two_seater)
		message("The two-seater is down safely.", 4.0)
		overlay().cue("objective")
		if hartwig_protected and alive(hartwig) and not hartwig_home:
			fly_to(hartwig, Vector3(AERODROME.x, 450.0, AERODROME.z), [], 100.0)
		elif not hartwig_protected:
			hartwig_home = true  # (only if the story never ran: the two-seater came home first)
	if hartwig_protected and not hartwig_home and alive(hartwig) and near(hartwig, AERODROME, LAND_RANGE, true):
		hartwig_home = true
		_last_landing = now()
		hide(hartwig)
		message("Brenner's second is home.", 4.0)
		overlay().cue("objective")


func _encounter_1() -> void:
	_set_stage("e1")
	var a := _bring(W1[0], _rel(two_seater, 950.0, 420.0, 120.0), two_seater, 35.0)
	var b := _bring(W1[1], _rel(two_seater, 1050.0, 560.0, 160.0), two_seater, 35.0)
	warn("Two scouts behind us. Keep them off the two-seater!", 6.0)
	highlight([a, b], 8.0)
	if a and alive(brenner):
		attack(brenner, a, [])
	_escort(hartwig)


func _encounter_2() -> void:
	_set_stage("e2")
	var high := _bring(W2[0], _rel(two_seater, -1300.0, 120.0, 280.0), world.player, 45.0)
	var low1 := _bring(W2[1], _rel(two_seater, -1350.0, -150.0, -40.0), two_seater, 25.0)
	var low2 := _bring(W2[2], _rel(two_seater, -1420.0, 60.0, -60.0), two_seater, 25.0)
	warn("Scouts ahead! Two are going for the damaged machine.", 6.0)
	highlight([high, low1, low2], 8.0)
	if high:
		for w in [brenner, hartwig]:
			if alive(w):
				attack(w, high, [])


func _encounter_3() -> void:
	_set_stage("e3")
	var f := _flat_fwd(two_seater)
	var side := f.cross(Vector3.UP)
	var shown: Array = []
	shown.append(_bring(W3[0], world.player.global_position - f * 1000.0 - side * 500.0 + Vector3.UP * 150.0, world.player, 45.0))
	shown.append(_bring(W3[1], _rel(two_seater, 1050.0, -350.0, 120.0), two_seater, 35.0))
	shown.append(_bring(W3[2], _rel(two_seater, 1150.0, -100.0, 170.0), two_seater, 35.0))
	warn("Another flight coming in! Keep the two-seater moving.", 6.0)
	highlight(shown, 8.0)


func _brenner_covers() -> void:
	_set_stage("cover")
	var pair: Array[Aircraft] = []
	for id in [W3[1], W3[2]]:
		var c := plane(id)
		if c and alive(c) and c.present():
			pair.append(c)
	if alive(brenner):
		if pair.size() == 2:
			attack(brenner, pair[0], [goal(Aircraft.G_ATTACK, pair[1].object_id)])
		elif pair.size() == 1:
			attack(brenner, pair[0])
	if alive(hartwig):
		formation(hartwig, brenner, Vector3(-40.0, 0.0, -40.0))
	message("Brenner is covering the rear. Stay with the two-seater.", 5.0)


## The story moment, staged by timers in a camera cut-in (about 17 s): over Brenner's shoulder as he chases the Camel
## on Hartwig's tail and shoots it down, then over the shoulder of the Camel that has closed on Brenner as its burst
## finds him. One caption at the end, held long enough to read.
const STORY_KILL_CAMEL := 5.0  # the Camel on Hartwig goes down (if Brenner has not already shot it)
const STORY_SECOND_SHOT := 7.0  # the camera moves to the Camel behind Brenner
const STORY_KILL_BRENNER := 11.0
const STORY_CAPTION := 12.0
const STORY_END := 17.0
const STORY_LINE := "Brenner is down. Bring his second home with the two-seater."

func _story() -> void:
	_set_stage("story")
	var on_hartwig := plane(W3[2]) if alive(plane(W3[2])) and plane(W3[2]).present() else null
	var killer := plane(W3[1]) if alive(plane(W3[1])) and plane(W3[1]).present() else null
	# the scene needs both Camels: bring back any the Baron already downed (placed below, unseen until the cut)
	if on_hartwig == null:
		on_hartwig = _spare(W4[1])
	if killer == null:
		killer = _spare(W4[0])
	# line them up behind Hartwig, in his heading: Hartwig, the Camel on his tail, Brenner, and well back the killer
	var b := hartwig.flight_basis
	var line := [on_hartwig, brenner, killer]
	var back := [150.0, 330.0, 750.0]
	for i in line.size():
		var q: Aircraft = line[i]
		if q == null:
			continue
		q.global_position = _rel(hartwig, back[i], [20.0, -10.0, -30.0][i], [5.0, 15.0, 30.0][i])
		q.flight_basis = b
		q.speed = hartwig.speed
	fly_to(hartwig, _rel(hartwig, -3000.0, 0.0, 0.0), [], 200.0)  # he runs straight on, the Camel firing on him
	if on_hartwig:
		on_hartwig.set("damage_scale", 0.0)
		attack(on_hartwig, hartwig)
		attack(brenner, on_hartwig)
	if killer:
		killer.set("damage_scale", 0.0)
		attack(killer, brenner)
	_cinematic(brenner, on_hartwig if on_hartwig else hartwig)
	after(3.0, func() -> void:
		if on_hartwig and alive(on_hartwig):
			on_hartwig.set("damage_scale", 1.0))  # Brenner's own fire may bring it down from here
	after(STORY_KILL_CAMEL, func() -> void:
		if on_hartwig and alive(on_hartwig):
			damage(on_hartwig, on_hartwig.health + 1.0, brenner))
	after(STORY_SECOND_SHOT, func() -> void:
		if killer and alive(killer) and alive(brenner):
			if killer.global_position.distance_to(brenner.global_position) > 260.0:  # (a cut: unseen)
				killer.global_position = _rel(brenner, 200.0, -25.0, 12.0)
				killer.flight_basis = brenner.flight_basis
			_cine_shot(killer, brenner))
	after(STORY_KILL_BRENNER, func() -> void:
		brenner.set("damage_scale", 1.0)
		damage(brenner, brenner.health + 1.0, killer))
	after(STORY_CAPTION, func() -> void:
		overlay().letterbox_caption(STORY_LINE)
		overlay().cue("warning"))
	after(STORY_END, _after_story.bind(killer))


## A Camel from a later attack, brought in for the story when the one it needs is already down.
func _spare(id: int) -> Aircraft:
	var c := plane(id)
	if c == null or not c.hidden:
		return null
	reveal(c, _rel(brenner, 600.0, 0.0, 20.0), [goal(Aircraft.G_ATTACK, brenner.object_id)], brenner.global_position)
	return c


func _after_story(killer: Aircraft) -> void:
	_end_cinematic()
	if killer and alive(killer):
		killer.set("damage_scale", 1.0)
		attack(killer, world.player, [])  # vulnerable, and no longer fixed on anyone in particular
	hartwig_protected = true
	if alive(hartwig):
		hartwig.set("damage_scale", HARTWIG_SCALE)
		hartwig.health = hartwig.endurance * HARTWIG_HEALTH
		_escort(hartwig)
		overlay().remove_bracket(hartwig, "ally")
		mark_protect(hartwig, "Hartwig")
	overlay().set_objective("Bring the two-seater and Hartwig (green) home")  # (the caption said it)
	overlay().cue("objective")
	_set_stage("after_story")


func _encounter_4(reduced: bool) -> void:
	_set_stage("e4")
	var lead: Aircraft = two_seater if not two_seater_home else hartwig
	var dir := (AERODROME - lead.global_position)
	dir.y = 0.0
	var f := dir.normalized()
	var side := f.cross(Vector3.UP)
	var base := lead.global_position + f * minf(1100.0, dir.length() * 0.6)
	var shown: Array = []
	var a := plane(W4[0])
	if a and a.hidden and not two_seater_home:
		shown.append(_bring(W4[0], base + side * 250.0 + Vector3.UP * 120.0, two_seater, 30.0))
	var b := plane(W4[1])
	if not reduced and b and b.hidden and alive(hartwig) and not hartwig_home:
		shown.append(_bring(W4[1], base - side * 250.0 + Vector3.UP * 150.0, hartwig, 30.0))
	shown = shown.filter(func(c) -> bool: return c != null)
	if not shown.is_empty():
		warn("Scouts over the approach! Clear the way home.", 6.0)
		highlight(shown, 8.0)


# ---------------------------------------------------------------- the cut-in

## A camera cut-in over from's shoulder, looking toward its quarry, with letterbox bars; the Baron flies on with the
## two-seater meanwhile, unhurt.
func _cinematic(from: Aircraft, quarry: Aircraft) -> void:
	_cine_cam = Camera3D.new()
	_cine_cam.far = world.camera.far
	_cine_cam.fov = world.camera.fov
	world.add_child(_cine_cam)
	_cine_shot(from, quarry)
	_cine_cam.current = true
	overlay().letterbox(true, "")
	var p := world.player
	p.set("damage_scale", 0.0)
	_player_autopilot = p.autopilot
	_player_goals = p.goals.duplicate()
	p.autopilot = true
	var g := goal(Aircraft.G_FORMATION, two_seater.object_id if alive(two_seater) and not two_seater_home else 0)
	g.offset = Vector3(0.0, 60.0, -120.0)
	set_goals(p, [g] if alive(two_seater) and not two_seater_home else [goal(Aircraft.G_WAYPOINT, 0, AERODROME + Vector3.UP * 500.0, 100.0)])


## A new shot (a cut): over from's shoulder toward quarry.
func _cine_shot(from: Aircraft, quarry: Aircraft) -> void:
	_cine_target = from
	_cine_quarry = quarry
	_cine_cam.global_position = Vector3.ZERO  # (no glide from the last shot)
	_update_cinematic()


func _update_cinematic() -> void:
	if _cine_target == null or not is_instance_valid(_cine_target):
		return
	var t := _cine_target
	var f := Vector3(t.flight_basis.z.x, 0.0, t.flight_basis.z.z).normalized()
	var want := t.global_position - f * 45.0 + f.cross(Vector3.UP) * 22.0 + Vector3.UP * 14.0
	_cine_cam.global_position = want if _cine_cam.global_position == Vector3.ZERO else _cine_cam.global_position.lerp(want, 0.15)
	var look := t.global_position + f * 60.0
	if _cine_quarry and is_instance_valid(_cine_quarry) and not _cine_quarry.hidden:
		look = t.global_position.lerp(_cine_quarry.global_position, 0.6)
	if not _cine_cam.global_position.is_equal_approx(look):
		_cine_cam.look_at(look, Vector3.UP)


func _end_cinematic() -> void:
	overlay().letterbox(false, "")
	if _cine_cam:
		world.camera.current = true
		_cine_cam.queue_free()
		_cine_cam = null
	var p := world.player
	p.autopilot = _player_autopilot  # (the debug autopilot flies on)
	p.goals.assign(_player_goals)
	p.goal_index = 0
	p.set("damage_scale", 1.0)
