extends "res://mods/redbaron/mission_script.gd"
## Mission 12, The Last Patrol (reworked 11 November 2026 to the user's brief, docs/m12_brief.md).
##   Opening      the Baron leads four young pilots west over the British side (Lenz leads the route, Vogel, Albers,
##                and Hartwig, Brenner's second from mission 11, at the rear). Scouts ahead, more far beyond them.
##   Encounter 1  three scouts from ahead and above: one on the Baron, two dive on the young pilots (Hartwig takes one).
##                Broken: "Too many coming. Take the patrol home." A larger formation shows far off on the battlefield;
##                the crossing point on the lines is marked; objective "Cover the withdrawal to friendly lines."
##   Encounter 2  a pair across the route ahead (on the pilots) and one from the rear quarter (on the Baron); Hartwig
##                holds the rear, then that scout turns on him. Route open: Albers, hit, breaks away in a defensive turn
##                and falls behind (slower). "One pilot is falling behind!"
##   Encounter 3  two scouts on Albers, staggered (behind, then from the side). Hartwig leads Lenz and Vogel on; each
##                crossing is announced. Broken: "He is clear. Stay with him!"
##   Encounter 4  as Albers nears the lines: a pair across his route, then (after a gap) a pair from the battlefield on
##                the Baron that goes for Albers if left alone. His distance to the lines on the HUD; final warning.
##   Crossing     a pilot north of SAFE_Z is across: out of the fight (no damage), on to the aerodrome. All four:
##                "All four are clear." Campaign completion saved at once (secure_progress), then the closing sequence.
##   Ending       a warning in play (a large enemy patrol coming up: the young pilots will never outrun it), then a
##                scripted sequence (about 30 s): the Baron turns back into the force lining up on him from far back
##                and into the ground fire; the frame freezes on him firing into it, slowly blurring and reddening,
##                with "He turned back." and "They made it home." over it. Then the epilogue page (no failure line, no
##                penalty). Nothing in it can fail the mission.
##   Lost         the Baron, or any of the four before he is across (failed_defence.html).
## Encounters start on route progress and the state of the fight before; timers are only safeguards. A scout the Baron
## hits while it attacks a pilot breaks off for a few seconds, then comes back on the pilot or on the Baron.

const SAFE_Z := 9300.0  # the north bank of the river: the German lines
const AERODROME := Vector3(8400, 450, 7900)
# the withdrawal: west along the British side, south-west round the battlefield, east, then north across the lines
# (about 12 km to the lines: the map is only 5 km wide where there is ground)
const ROUTE: Array[Vector3] = [Vector3(9500, 440, 13500), Vector3(8200, 440, 13500), Vector3(6700, 430, 13300),
	Vector3(6500, 430, 12200), Vector3(7200, 430, 11400), Vector3(8800, 430, 11500), Vector3(10500, 430, 11200),
	Vector3(10800, 430, 10300), Vector3(10400, 440, 9000), Vector3(8400, 450, 7900)]
const CROSSING := Vector3(10492, 440, 9300)  # where the route meets the lines (marked on the minimap)
const NAMES := {3002: "Hartwig", 3003: "Lenz", 3004: "Vogel", 3005: "Albers"}
const HARTWIG := 3002
const LEAD := 3003
const STRAGGLER := 3005
const ROOKIE_SCALE := 0.3  # the young pilots take this share of each hit: a Camel on one for about 15 s (a missed
# interception) is survivable, not two of them for long
const STRAGGLER_HEALTH := 0.55
const STRAGGLER_SPEED := 88.0  # (stall 82)
const STRAGGLER_SCALE := 0.2  # hurt and alone, he is the one the last two attacks go for: a fifth of each hit (a
# pair 1100 ahead of him took him from 42 to nothing in 4 s at 0.3)
const E1 := [3010, 3011, 3012]  # on the Baron, then the two diving on the pilots
const E2 := [3013, 3014, 3015]  # the crossing pair, then the rear-quarter scout
const E3 := [3016, 3017]
const E4 := [3018, 3019, 3020, 3021]  # the pair across his route, then the pair from the battlefield
const FAR := [3030, 3031, 3032, 3033, 3034, 3035, 3036, 3037, 3038, 3039, 3040, 3041]
const GAP := 12.0
const SAFEGUARD := 30.0
const BREAK_OFF := 6.0  # a scout hit by the Baron while on a pilot evades this long
const ESCORT := {3004: Vector3(-45.0, 5.0, -40.0), 3005: Vector3(45.0, 0.0, -45.0), 3002: Vector3(0.0, 15.0, -110.0)}

var rookies: Array[Aircraft] = []
var stage := "opening"
var stage_time := 0.0
var across := {}  # Aircraft -> true
var landed := {}
var straggling := false
var crossing_marker: Dictionary
var _route_of := {}  # Aircraft -> next ROUTE index while flying the route itself
var _evade_until := {}  # Aircraft -> time
var _broke_off := {}  # Camel -> times broken off
var _announced := []  # rookies whose crossing has been announced
var _say: Array[Array] = []  # [text, seconds, cue] waiting their turn
var _say_free := 0.0
var _check := 0.0
var _follow_watch := {}  # second-pair Camel -> time the Baron was last close
var _warned_near := false
var _hold_time := -1.0


func start() -> void:
	owns_win = true
	end_messages["epilogue"] = ""
	result_pages["epilogue"] = "campaigns\\redbaron\\epilogue.html"
	for id in [HARTWIG, LEAD, 3004, STRAGGLER]:
		var r := plane(id)
		rookies.append(r)
		r.set("damage_scale", ROOKIE_SCALE)
		mark_protect(r, NAMES[id])
		r.damaged.connect(_on_rookie_hit.bind(r))
	for id in E1 + E2 + E3 + E4:
		plane(id).damaged.connect(_on_camel_hit.bind(plane(id)))
	for t in world.targets:
		if t.turret:
			t.aa_range = 0.0  # silent until the closing sequence
	after(0.2, func() -> void:  # (after the mission's own 0x100 goals put them in the air: every plane starts parked)
		_fly_route(plane(LEAD), 0)
		for id in [3004, STRAGGLER, HARTWIG]:
			formation(plane(id), plane(LEAD), ESCORT[id]))
	objective("Lead the patrol. Keep your pilots together.", "Lead the patrol: keep the four young pilots (green) together")
	# far ahead, more aircraft against the horizon (scenery: never part of the fight)
	_show_far(FAR.slice(0, 4), world.player.global_position + Vector3(-2600.0, 150.0, -300.0), Vector3(0, 0, 1), 26.0)
	after(9.0, func() -> void:
		if stage == "opening":
			warn("Enemy scouts ahead. More aircraft beyond them.", 5.0))
	_set_stage("opening")


func _set_stage(s: String) -> void:
	stage = s
	stage_time = now()


func _since() -> float:
	return now() - stage_time


# ---------------------------------------------------------------- the young pilots

## Flies p along ROUTE from index i (the last point is the aerodrome).
func _fly_route(p: Aircraft, i: int) -> void:
	i = clampi(i, 0, ROUTE.size() - 1)
	_route_of[p] = i
	var list: Array = []
	for k in range(i, ROUTE.size()):
		list.append(goal(Aircraft.G_WAYPOINT, 0, ROUTE[k], 150.0))
	set_goals(p, list)


## The ROUTE index p is heading for (nearest point ahead along the route).
func _route_index(p: Aircraft) -> int:
	var best := 0
	var best_d := INF
	for k in ROUTE.size() - 1:
		var a := Vector2(ROUTE[k].x, ROUTE[k].z)
		var b := Vector2(ROUTE[k + 1].x, ROUTE[k + 1].z)
		var c := Geometry2D.get_closest_point_to_segment(Vector2(p.global_position.x, p.global_position.z), a, b)
		var d := c.distance_to(Vector2(p.global_position.x, p.global_position.z))
		if d < best_d:
			best_d = d
			best = k + 1
	return best


## Distance along the route from p to the lines.
func _to_lines(p: Aircraft) -> float:
	if p.global_position.z < SAFE_Z:
		return 0.0
	var i := _route_index(p)
	var at := Vector2(p.global_position.x, p.global_position.z)
	var d := 0.0
	for k in range(i, ROUTE.size()):
		var nxt := Vector2(ROUTE[k].x, ROUTE[k].z)
		if ROUTE[k].z <= SAFE_Z:
			return d + at.distance_to(Vector2(CROSSING.x, CROSSING.z))
		d += at.distance_to(nxt)
		at = nxt
	return d


## A pilot's normal job: the route (the leader, or Albers once he straggles) or formation on the leader.
func _resume(r: Aircraft) -> void:
	if not alive(r) or r.hidden:
		return
	if across.has(r):
		fly_to(r, AERODROME, [], 200.0)
		return
	var lead := _group_leader()
	if r == lead or (r.object_id == STRAGGLER and straggling) or lead == null:
		_fly_route(r, _route_index(r))
	else:
		formation(r, lead, ESCORT.get(r.object_id, Vector3(-40.0, 0.0, -60.0)))


## The pilot the others follow: Lenz while he is with them, else whoever of the group is still flying.
func _group_leader() -> Aircraft:
	for id in [LEAD, 3004, HARTWIG]:
		var r := plane(id)
		if alive(r) and not across.has(r):
			return r
	return null


## A pilot with a scout close behind him turns hard away for a moment, then rejoins (they defend themselves, and
## lose the formation doing it).
func _defend() -> void:
	for r in rookies:
		if not alive(r) or across.has(r) or now() < float(_evade_until.get(r, -100.0)) + 6.0:
			continue
		var c := _attacker_of(r, 260.0)
		if c == null:
			continue
		var to := c.global_position - r.global_position
		if to.normalized().dot(r.flight_basis.z) > -0.3:
			continue  # not behind him
		var side := r.flight_basis.z.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
		_evade_until[r] = now() + 2.5
		fly_to(r, r.global_position + side * 450.0 + r.flight_basis.z * 150.0, [], 60.0)
		after(2.5, _resume.bind(r))


## The nearest scout attacking r within range (or null).
func _attacker_of(r: Aircraft, within: float) -> Aircraft:
	var best: Aircraft = null
	for q in world.planes:
		if not _enemy(q) or int(q.current_goal().get("type", 0)) != Aircraft.G_ATTACK:
			continue
		if int(q.current_goal().targetid) != r.object_id or not near(q, r, within):
			continue
		if best == null or q.global_position.distance_to(r.global_position) < best.global_position.distance_to(r.global_position):
			best = q
	return best


func _enemy(q: Aircraft) -> bool:
	return q.groups & (1 << 9) and q.present() and alive(q) and not q.hidden and not (q.object_id in FAR)


func _on_rookie_hit(_p: Aircraft, _amount: float, _attacker: Variant, r: Aircraft) -> void:
	pass  # (the HUD shows it; kept for tuning probes)


# ---------------------------------------------------------------- the scouts

## Brings in Camel id at pos on target for at most limit s, then (then_player > 0) on the Baron for that long, then
## home to the south.
func _bring(id: int, pos: Vector3, target: Aircraft, limit: float, then_player := 0.0) -> Aircraft:
	var c := plane(id)
	if c == null or not c.hidden:
		return null
	var g := world.ground_height(pos)
	pos.y = clampf(pos.y, g + 220.0, g + 380.0)  # above 400 the original ceiling slows a plane (to a stall)
	reveal(c, pos, _attack_goals(target, limit, then_player), target.global_position - pos)
	return c


func _attack_goals(target: Aircraft, limit: float, then_player := 0.0) -> Array:
	var list := [goal(Aircraft.G_RETALIATE_ON, 0, Vector3.ZERO, limit), goal(Aircraft.G_ATTACK, target.object_id)]
	if then_player > 0.0 and target != world.player:
		list += [goal(Aircraft.G_RETALIATE_ON, 0, Vector3.ZERO, then_player), goal(Aircraft.G_ATTACK, world.player.object_id)]
	return list + [goal(Aircraft.G_RETALIATE_OFF), goal(Aircraft.G_WAYPOINT, 0, Vector3(target.global_position.x, 500.0,
		world.map_bounds.end.y + 800.0), 300.0)]


## A scout the Baron hits while it is on one of the pilots breaks off (evades away for BREAK_OFF s), then comes back:
## every other time on the Baron instead, so they do not all go straight back for the pilots.
func _on_camel_hit(_p: Aircraft, amount: float, attacker: Variant, c: Aircraft) -> void:
	if amount <= 0.0 or attacker != world.player or not alive(c) or stage == "ending":
		return
	var g := c.current_goal()
	if int(g.get("type", 0)) != Aircraft.G_ATTACK:
		return
	var tgt := plane(int(g.targetid))
	if tgt == null or not (tgt in rookies):
		return
	var n := int(_broke_off.get(c, 0)) + 1
	_broke_off[c] = n
	var away := c.global_position - world.player.global_position
	away.y = 0.0
	var to := c.global_position + away.normalized() * 600.0 + Vector3.UP * 60.0
	set_goals(c, [goal(Aircraft.G_RETALIATE_OFF), goal(Aircraft.G_WAYPOINT, 0, to, 80.0)])
	after(BREAK_OFF, func() -> void:
		if alive(c) and not c.hidden and stage != "ending":
			var back: Aircraft = world.player if n % 2 == 1 or not alive(tgt) or across.has(tgt) else tgt
			set_goals(c, _attack_goals(back, 25.0)))


## Scouts of ids still on the pilots (attacking one, not turned home).
func _pressing(ids: Array) -> int:
	var n := 0
	for id in ids:
		var c := plane(id)
		if c and _enemy(c) and int(c.current_goal().get("type", 0)) == Aircraft.G_ATTACK:
			var t := plane(int(c.current_goal().targetid))
			if t in rookies and not across.has(t):
				n += 1
	return n


## Scouts still fighting (attacking anyone, or about to) within r of p.
func _fighting_near(p: Aircraft, r: float) -> int:
	var n := 0
	for q in world.planes:
		if _enemy(q) and int(q.current_goal().get("type", 0)) in [Aircraft.G_ATTACK, Aircraft.G_RETALIATE_ON] and near(q, p, r):
			n += 1
	return n


## A point ahead / to the side / up from p in its flat frame (ahead > 0).
func _rel(p: Aircraft, ahead: float, side: float, up: float) -> Vector3:
	var f := Vector3(p.flight_basis.z.x, 0.0, p.flight_basis.z.z).normalized()
	return p.global_position + f * ahead + f.cross(Vector3.UP) * side + Vector3.UP * up


## A point ahead along the route from p (distance d along the remaining legs).
func _ahead_on_route(p: Aircraft, d: float) -> Vector3:
	var at := p.global_position
	for k in range(_route_index(p), ROUTE.size()):
		var leg := ROUTE[k] - at
		leg.y = 0.0
		if leg.length() >= d:
			return at + leg.normalized() * d
		d -= leg.length()
		at = Vector3(ROUTE[k].x, at.y, ROUTE[k].z)
	return at


## Distant aircraft for scale: shown at around pos, flying along dir, hidden again after seconds.
func _show_far(ids: Array, pos: Vector3, dir: Vector3, seconds: float) -> void:
	var k := 0
	for id in ids:
		var c := plane(id)
		if c == null or not c.hidden:
			continue
		var at := pos + Vector3(dir.z, 0.0, -dir.x) * (k * 90.0 - 135.0) + Vector3(0.0, (k % 2) * 40.0, -(k % 2) * 60.0)
		at.y = minf(at.y, world.ground_height(at) + 380.0)
		reveal(c, at, [goal(Aircraft.G_WAYPOINT, 0, at + dir * 6000.0, 300.0)], dir)
		c.set("damage_scale", 0.0)
		k += 1
	after(seconds, func() -> void:
		for id in ids:
			if stage != "ending" and alive(plane(id)) and not plane(id).hidden:
				hide(plane(id)))


# ---------------------------------------------------------------- the flight

func step(dt: float) -> void:
	var p := world.player
	_say_next()
	if stage == "ending":
		_ending_step(dt)
		return
	if not alive(p):
		return
	for r in rookies:
		if not alive(r) and not across.has(r):
			lose("defence")
			return
	_crossings()
	_check += dt
	if _check >= 0.5:
		_check = 0.0
		_defend()
		_second_pair_follow()
	_update_hud()
	match stage:
		"opening":
			if _since() > 22.0:
				_encounter_1()
		"e1":
			if _since() > 10.0 and _pressing(E1) == 0:
				objective("Too many coming. Take the patrol home.", "Cover the withdrawal to friendly lines")
				crossing_marker = mark_destination(CROSSING, true)
				var f := plane(LEAD).global_position
				_show_far(FAR.slice(4, 10), Vector3(f.x + 300.0, 440.0, minf(f.z + 2600.0, world.map_bounds.end.y - 150.0)),
					Vector3(-1, 0, 0), 22.0)
				for r in rookies:
					_resume(r)
				_set_stage("after_e1")
		"after_e1":
			if (_since() > GAP and _route_index(plane(LEAD)) >= 3) or _since() > SAFEGUARD:
				_encounter_2()
		"e2":
			if _hold_time < 0.0 and _since() > 18.0:
				_hold_time = now()
				var rear := plane(E2[2])
				if rear and _enemy(rear) and alive(plane(HARTWIG)):
					set_goals(rear, _attack_goals(plane(HARTWIG), 25.0))
			var crossing_pair := [E2[0], E2[1]]
			if (_since() > 8.0 and _pressing(crossing_pair) == 0) or _since() > 60.0:
				_straggle()
		"straggle":
			if _since() > 6.0:
				_encounter_3()
		"e3":
			if (_since() > 10.0 and _pressing(E3) == 0) or across.has(plane(STRAGGLER)):
				if not across.has(plane(STRAGGLER)):
					say("He is clear. Stay with him!", 5.0, "objective")
				_set_stage("after_e3")
		"after_e3":
			var s := plane(STRAGGLER)
			var d := _to_lines(s)
			var close := _fighting_near(s, 1200.0)
			if not across.has(s) and ((_since() > GAP and close <= 1 and d < 2600.0) or _since() > 25.0):
				_encounter_4()
		"e4", "all_clear":
			pass
	var s2 := plane(STRAGGLER)
	if stage in ["after_e3", "e4"] and not across.has(s2) and not _warned_near and _to_lines(s2) < 500.0:
		_warned_near = true
		warn("Almost across. Hold them a little longer!", 4.0)
	if across.size() == rookies.size() and stage != "all_clear":
		_all_clear()


## Messages one at a time, each held long enough to read.
func say(text: String, seconds := 4.0, cue := "") -> void:
	_say.append([text, seconds, cue])


func _say_next() -> void:
	if _say.is_empty() or now() < _say_free:
		return
	var m: Array = _say.pop_front()
	message(m[0], m[1])
	if m[2] != "":
		overlay().cue(m[2])
	_say_free = now() + float(m[1])


## A pilot north of SAFE_Z is across: out of the fight, on to the aerodrome; landing there hides him.
func _crossings() -> void:
	for r in rookies:
		if not alive(r):
			continue
		if not across.has(r) and r.global_position.z < SAFE_Z:
			across[r] = true
			r.set("damage_scale", 0.0)
			fly_to(r, AERODROME, [], 200.0)
			for q in world.planes:  # whoever was on him lets go
				if _enemy(q) and int(q.current_goal().get("type", 0)) == Aircraft.G_ATTACK and int(q.current_goal().targetid) == r.object_id:
					set_goals(q, _attack_goals(world.player, 20.0))
			if r.object_id == STRAGGLER:
				pass  # announced by _all_clear (he is the last)
			else:
				_announce_crossings()
		if across.has(r) and not landed.has(r) and near(r, AERODROME, 250.0, true) and stage != "ending":
			landed[r] = true
			hide(r)


## "First pilot across." / "Second pilot across." / "Brenner's second is safe. One still to bring home." (Hartwig is
## announced after the other two of the group, whatever the order they crossed in).
func _announce_crossings() -> void:
	var group := rookies.filter(func(r): return r.object_id != STRAGGLER)
	var others := group.filter(func(r): return r.object_id != HARTWIG and across.has(r) and not (r in _announced))
	for r in others:
		_announced.append(r)
		var n := _announced.filter(func(q): return q.object_id != HARTWIG).size()
		say("First pilot across." if n == 1 else "Second pilot across.", 3.5, "objective")
	var h := plane(HARTWIG)
	var done := group.filter(func(r): return r.object_id != HARTWIG).all(func(r): return across.has(r) or not alive(r))
	if across.has(h) and not (h in _announced) and done:
		_announced.append(h)
		say("Brenner's second is safe. One still to bring home." if not across.has(plane(STRAGGLER))
			else "Brenner's second is safe.", 5.0, "objective")


func _update_hud() -> void:
	var lines: Array[String] = []
	var row: Array[String] = []
	for r in rookies:
		var t: String = NAMES[r.object_id]
		if across.has(r):
			t += " across"
		else:
			t += " %d %%" % roundi(100.0 * maxf(r.health, 0.0) / r.endurance)
			if _attacker_of(r, 700.0):
				t += " (under attack)"
		row.append(t)
		if row.size() == 2:
			lines.append("   ".join(row))
			row = []
		var m: Dictionary = _tracked.get(r, {})
		if not m.is_empty():
			m.pulse = not across.has(r) and _attacker_of(r, 700.0) != null
	var s := plane(STRAGGLER)
	if straggling and not across.has(s):
		lines.append("Albers %.1f km from the lines" % (_to_lines(s) / 1000.0))
		if stage in ["straggle", "e3", "after_e3"]:
			var lead := _group_leader()
			if lead and not across.has(lead):
				lines.append("Main group %.1f km from the lines" % (_to_lines(lead) / 1000.0))
	overlay().set_counter("\n".join(lines))


func _encounter_1() -> void:
	_set_stage("e1")
	var lead := plane(LEAD)
	var a := _bring(E1[0], _rel(world.player, 1300.0, 380.0, 220.0), world.player, 40.0)
	var b := _bring(E1[1], _rel(lead, 1300.0, -480.0, 260.0), plane(3004), 35.0, 12.0)
	var c := _bring(E1[2], _rel(lead, 1400.0, 440.0, 280.0), plane(STRAGGLER), 35.0, 12.0)
	warn("They are coming through the formation! Protect your pilots.", 6.0)
	highlight([a, b, c], 8.0)
	if b and alive(plane(HARTWIG)):
		after(4.0, func() -> void:
			if alive(b) and stage == "e1":
				attack(plane(HARTWIG), b, []))  # he helps keep them together


func _encounter_2() -> void:
	_set_stage("e2")
	var lead := plane(LEAD)
	var ahead := _ahead_on_route(lead, 1500.0)
	var f := (ahead - lead.global_position)
	f.y = 0.0
	f = f.normalized()
	var side := f.cross(Vector3.UP)
	# the crossing pair: well ahead and off to one side, flying across the route (no opening burst they cannot avoid)
	var a := _bring(E2[0], ahead + side * 700.0 + Vector3.UP * 60.0, lead, 30.0, 12.0)
	var b := _bring(E2[1], ahead + side * 820.0 + f * 120.0 + Vector3.UP * 90.0, plane(3004), 30.0, 12.0)
	var c := _bring(E2[2], world.player.global_position - _flat(world.player) * 950.0 - side * 450.0 + Vector3.UP * 120.0,
		world.player, 40.0)
	warn("Two scouts across their path. Clear the way!", 6.0)
	highlight([a, b, c], 8.0)
	var h := plane(HARTWIG)
	if c and alive(h):
		attack(h, c, [])
		after(6.5, func() -> void:
			if stage == "e2":
				say("Brenner's second is holding the rear. Help the others through.", 5.0, "warning"))


func _flat(p: Aircraft) -> Vector3:
	return Vector3(p.flight_basis.z.x, 0.0, p.flight_basis.z.z).normalized()


## The route is open: Albers, hit in the fight, breaks away in a defensive turn and falls behind; Hartwig rejoins and
## leads the other two on.
func _straggle() -> void:
	_set_stage("straggle")
	var s := plane(STRAGGLER)
	var h := plane(HARTWIG)
	if alive(h) and not across.has(h):
		_resume(h)
	if not alive(s) or across.has(s):
		_set_stage("after_e3")
		return
	straggling = true
	if s.health > s.endurance * STRAGGLER_HEALTH:
		s.health = s.endurance * STRAGGLER_HEALTH  # (smoking: the damage he took breaking away)
	s.set("high_speed", STRAGGLER_SPEED)
	s.set("damage_scale", STRAGGLER_SCALE)
	var away := s.global_position - s.flight_basis.z * 500.0 + s.flight_basis.z.cross(Vector3.UP).normalized() * 450.0
	_evade_until[s] = now() + 7.0
	fly_to(s, away, [], 80.0)
	after(7.0, _resume.bind(s))
	warn("Albers is falling behind!", 5.0)


func _encounter_3() -> void:
	_set_stage("e3")
	var s := plane(STRAGGLER)
	var behind := _bring(E3[0], _rel(s, -850.0, 120.0, 90.0), s, 35.0, 12.0)
	highlight([behind], 8.0)
	say("The main group is nearly through. Bring the last man back.", 5.0, "warning")
	after(8.0, func() -> void:  # staggered: the second from the side
		if alive(s) and not across.has(s) and stage in ["e3", "after_e3"]:
			var side := _bring(E3[1], _rel(s, 250.0, -800.0, 60.0), s, 35.0, 12.0)
			highlight([side], 6.0))


func _encounter_4() -> void:
	_set_stage("e4")
	var s := plane(STRAGGLER)
	var ahead := _ahead_on_route(s, 900.0)
	var f := ahead - s.global_position
	f.y = 0.0
	f = f.normalized()
	var side := f.cross(Vector3.UP)
	# across his route, well out to one side: they must turn in (no opening burst he cannot avoid)
	var a := _bring(E4[0], ahead + side * 750.0 + Vector3.UP * 70.0, s, 30.0, 12.0)
	var b := _bring(E4[1], ahead + side * 880.0 + f * 150.0 + Vector3.UP * 100.0, s, 30.0, 12.0)
	warn("Another flight! Keep them off him until he crosses.", 6.0)
	highlight([a, b], 8.0)
	after(16.0, func() -> void:  # the second pair, from the battlefield, after a gap
		if across.has(s) or not alive(s) or stage != "e4":
			return
		var back := s.global_position - f * 1300.0 + Vector3.UP * 100.0
		var c := _bring(E4[2], back - side * 150.0, world.player, 40.0)
		var d := _bring(E4[3], back + side * 150.0 + Vector3.UP * 40.0, world.player, 40.0)
		for q in [c, d]:
			if q:
				_follow_watch[q] = now()
		highlight([c, d], 8.0))


## The second pair of encounter 4 go on to Albers if the Baron leaves them alone (8 s without coming within 900).
func _second_pair_follow() -> void:
	var s := plane(STRAGGLER)
	for q in _follow_watch.keys():
		if not _enemy(q) or not alive(s) or across.has(s):
			continue
		if near(q, world.player, 900.0):
			_follow_watch[q] = now()
		elif now() - float(_follow_watch[q]) > 8.0 and int(q.current_goal().get("targetid", 0)) == world.player.object_id:
			set_goals(q, _attack_goals(s, 25.0))


func _all_clear() -> void:
	_set_stage("all_clear")
	_say.clear()
	message("All four are clear.", 4.0)
	overlay().cue("objective")
	overlay().set_objective("")
	secure_progress()
	world.player.set("damage_scale", 0.0)  # from here nothing can bring up a failure screen
	_bring_force()  # far behind the withdrawal for now: on the minimap, coming up
	after(4.5, func() -> void:
		warn(WARNING_LINE, WARNING_TIME))
	after(4.5 + WARNING_TIME, _start_ending)


# ---------------------------------------------------------------- the closing sequence
# A warning in play ("A large enemy patrol ... will never outrun it."), then, with the HUD gone and letterbox bars:
#   turn     behind and above the Baron as he banks back toward the force, which comes up in rows from far back
#   line-up  settled behind him: the rows line up on him and open fire; the ground guns under his path open up
#   freeze   the frame holds (the Baron firing into the force, the scouts firing, the guns firing), slowly blurring
#            and reddening, sound muffled; "He turned back.", "They made it home." over it; black; the epilogue.

const WARNING_LINE := "A large enemy patrol is coming up behind us. The young pilots will never outrun it."
const WARNING_TIME := 6.0
const FORCE_ROWS := 3
const FORCE_BACK := 2000.0  # the first row's distance from the Baron when the sequence starts (they "start further
# back": the view distance is opened up for the sequence so they can be seen lining up)
const FREEZE_RANGE := 240.0  # the frame holds when the nearest scout ahead of him is this close (or at FREEZE_LATEST):
# the front row fills the view ahead of him, the rows behind it still in the shot
const FREEZE_LATEST := 18.0
const VIEW_IN_ENDING := 2200.0  # (the ground's edges are at least 2500 away from ENDING_AT east and west)
const ENDING_AT := Vector3(8700, 0, 10300)  # the middle of the ground on this map (x 6200..11200)

var _cam: Camera3D
var _shot := ""
var _end_t := 0.0
var _force: Array[Aircraft] = []
var _force_dir := Vector3.FORWARD  # from the Baron toward the force
var _freeze_t := -1.0
var _cam_fwd := Vector3(0, 0, -1)  # the camera's heading: follows his slowly, so the turn shows
var _decoy: Aircraft  # what the ground guns aim at in the sequence


## The force: twelve scouts in rows far back toward the battlefield (south of the Baron), coming up the corridor the
## young pilots escaped along. Scenery for the sequence (no damage; never part of the fight's budget).
func _bring_force() -> void:
	var p := world.player
	var south := Vector3(0.0, 0.0, 1.0)
	var origin := p.global_position + south * (FORCE_BACK + 1600.0)  # moves up while the warning shows
	origin.z = minf(origin.z, world.map_bounds.end.y - 100.0)
	var side := Vector3(1.0, 0.0, 0.0)
	var k := 0
	for id in FAR:
		var c := plane(id)
		if c == null:
			continue
		if not c.hidden:
			hide(c)
		var row := k / 4
		var col := k % 4
		var at := origin + south * (row * 220.0) + side * ((col - 1.5) * 110.0 + (row % 2) * 55.0)
		at.y = world.ground_height(at) + 230.0 + col * 25.0 + row * 30.0
		var tgt := Vector3(at.x, at.y, at.z - 9000.0)
		reveal(c, at, [goal(Aircraft.G_WAYPOINT, 0, tgt, 200.0)], tgt - at)
		c.set("damage_scale", 0.0)
		_force.append(c)
		k += 1


func _start_ending() -> void:
	_set_stage("ending")
	_end_t = 0.0  # (mission time since stage_time: _ending_step)
	var p := world.player
	p.set("damage_scale", 0.0)
	p.autopilot = true
	world.hud.visible = false
	world.message_label.visible = false
	overlay().set_counter("")
	overlay().set_objective("")
	overlay().letterbox(true, "")
	if not crossing_marker.is_empty():
		unmark(crossing_marker)
	for q in world.planes:  # the fight is over: what is left of it turns away
		if _enemy(q):
			set_goals(q, [goal(Aircraft.G_RETALIATE_OFF), goal(Aircraft.G_WAYPOINT, 0,
				Vector3(q.global_position.x, 500.0, world.map_bounds.end.y + 800.0), 300.0)])
	for r in rookies:  # home: out of the picture
		r.set("damage_scale", 0.0)
		if not r.hidden:
			hide(r)
	# the sequence is staged over the middle of the ground (a cut: the letterbox comes in), far from the map's edges so
	# the view is open all round: the Baron heading home (north), the force coming up from the battlefield (south)
	var at0 := ENDING_AT
	at0.y = world.ground_height(at0) + 320.0
	p.global_position = at0
	p.flight_basis = Basis.looking_at(Vector3(0, 0, 1), Vector3.UP)  # (looking_at's -z: his nose to the north)
	p.speed = maxf(p.speed, 105.0)
	_force_dir = Vector3(0, 0, 1)
	# the ground guns aim at a stand-in just above and ahead of him (unseen): their fire bursts close round him
	_decoy = _force.pop_back()
	_decoy.groups = 1 << 8
	_decoy.visible = false
	set_goals(_decoy, [])
	var side := _force_dir.cross(Vector3.UP)
	for k in _force.size():
		var c := _force[k]
		var row := k / 4
		var col := k % 4
		var at := p.global_position + _force_dir * (FORCE_BACK + row * 260.0) + side * ((col - 1.5) * 120.0 + (row % 2) * 60.0)
		at.y = p.global_position.y + 15.0 + col * 18.0 + row * 30.0  # level with him and above: against the sky
		c.global_position = at
		c.flight_basis = Basis.looking_at(_force_dir, Vector3.UP)  # (looking_at's -z: facing back up the corridor)
		c.speed = c.high_speed
		set_goals(c, [goal(Aircraft.G_ATTACK, p.object_id)])
	# the U-turn: back toward the battle
	var ahead := p.global_position + _force_dir * 6000.0 + Vector3(300.0, 0.0, 0.0)
	ahead.y = p.global_position.y
	set_goals(p, [goal(Aircraft.G_WAYPOINT, 0, ahead, 100.0)])
	_cam_fwd = Vector3(0, 0, -1)
	_place_guns()
	_widen_view(VIEW_IN_ENDING)
	_cam = Camera3D.new()
	_cam.far = VIEW_IN_ENDING
	_cam.fov = world.camera.fov
	world.add_child(_cam)
	_cam.current = true
	_shot = "turn"


## Opens the view distance (fog and far clip) so the force can be seen lining up from far back.
func _widen_view(d: float) -> void:
	RenderingServer.global_shader_parameter_set("ra_fog_far", d)
	for we in world.find_children("*", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment.fog_depth_end = d
	world.camera.far = d


func _ending_step(_dt: float) -> void:
	_end_t = _since()
	var p := world.player
	if _decoy and is_instance_valid(_decoy):
		_decoy.global_position = p.global_position + p.flight_basis.z * 70.0 + Vector3.UP * 45.0
		_decoy.flight_basis = p.flight_basis
		_decoy.speed = p.speed
		for t in world.targets:
			if t.turret:
				t.aa_target = _decoy
	if _shot == "turn" and ((_end_t >= 5.0 and p.flight_basis.z.dot(_force_dir) > 0.93) or _end_t >= 9.0):
		_shot = "lineup"
		_cam.fov = 42.0  # closer in: the scouts coming at him read as aircraft, not specks
	if _shot == "lineup":
		# he holds straight and level at them (left to itself, the autopilot breaks away from a head-on pass)
		var front := Vector3.ZERO
		var n := 0
		for c in _force.slice(0, 4):
			front += c.global_position
			n += 1
		var to := front / maxf(n, 1.0) - p.global_position
		to.y *= 0.3
		if to.length() > 1.0:
			p.flight_basis = p.flight_basis.slerp(Basis.looking_at(-to.normalized(), Vector3.UP), 0.25).orthonormalized()
			p.set("bank", 0.0)
			p.set("_ai_bank", 0.0)
			p.set("_last_ai_bank", 0.0)
		var nearest := INF
		var nearest_ahead := INF
		for c in _force:
			var rel := c.global_position - p.global_position
			var d := rel.length()
			nearest = minf(nearest, d)
			if rel.normalized().dot(p.flight_basis.z) > 0.85:
				nearest_ahead = minf(nearest_ahead, d)
			c.set("force_fire", d < 900.0)  # every one of them firing as it lines up on him
		p.set("force_fire", nearest < 800.0)
		if nearest_ahead < FREEZE_RANGE or nearest < FREEZE_RANGE * 0.5 or _end_t >= FREEZE_LATEST:
			_freeze()
	if _shot == "freeze":
		var f := now() - _freeze_t
		var k := clampf(f / 6.0, 0.0, 1.0)
		overlay().freeze_amount(k)
		overlay().muffle(k)
		if f < 2.0:
			overlay().title("")
		elif f < 7.0:
			overlay().title("He turned back.", clampf(minf((f - 2.0) / 0.8, (7.0 - f) / 0.8), 0.0, 1.0))
		elif f < 12.5:
			overlay().title("They made it home.", clampf(minf((f - 7.0) / 0.8, (12.5 - f) / 0.8), 0.0, 1.0))
		else:
			overlay().title("")
			overlay().fade(clampf((f - 12.5) / 1.5, 0.0, 1.0))
			if f >= 14.5:
				_shot = "done"
				lose("epilogue")
	_update_camera(p)


## The frame holds: what the camera sees now stays on the screen (the flight runs on underneath, unseen).
func _freeze() -> void:
	_shot = "freeze"
	_freeze_t = now()
	overlay().jolt(0.3, 1.2)
	var img: Image = null
	var tex := world.get_viewport().get_texture()
	if tex:
		img = tex.get_image()
	overlay().freeze(img)


## The ground positions under the Baron's path toward the force: they open up as he comes over them.
func _place_guns() -> void:
	var p := world.player
	var side := _force_dir.cross(Vector3.UP)
	var k := 0
	for t in world.targets:
		if not t.turret:
			continue
		var at := p.global_position + _force_dir * (1100.0 + (k / 2) * 300.0) + side * (200.0 if k % 2 == 0 else -240.0)
		at.y = world.ground_height(at)
		(t.node as Node3D).global_position = at
		t.aa_range = 900.0
		t.aa_target = null
		k += 1


func _update_camera(p: Aircraft) -> void:
	if _cam == null or not is_instance_valid(_cam) or _shot in ["freeze", "done"]:
		return
	var back := 34.0
	var up := 7.0
	var look := p.global_position + p.flight_basis.z * 300.0 + Vector3.UP * 30.0  # the force against the sky
	if _shot == "turn":  # behind and above him as he makes his U-turn back toward the battle
		back = 60.0
		up = 26.0
		look = p.global_position + p.flight_basis.z * 80.0
	var fwd := Vector3(p.flight_basis.z.x, 0.0, p.flight_basis.z.z).normalized()
	_cam_fwd = _cam_fwd.slerp(fwd, 0.025 if _shot == "turn" else 0.15).normalized()
	fwd = _cam_fwd
	var want := p.global_position - fwd * back + Vector3.UP * up
	_cam.global_position = want if _cam.global_position == Vector3.ZERO else _cam.global_position.lerp(want, 0.2)
	if not _cam.global_position.is_equal_approx(look):
		_cam.look_at(look, Vector3.UP)


func outcome(stock: String) -> String:
	if stock == "death" and world.progress_was_secured:
		return "epilogue"  # (cannot happen in the ending: no damage there)
	return super.outcome(stock)
