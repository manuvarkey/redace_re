extends "res://mods/redbaron/missions/objective.gd"
## Mission 6, Balloon Busting: the original rules plus objective.gd (intro, counter, priority marks on the balloons).
## The tactical choice is when to go in, with the friendly bombing attack or ahead of it:
##   - Three Halberstadt CL.IIs, one per balloon ring, each bomb their own guns on the near (north) side of the
##     ring: 8 of the 15 guns (west 3, centre 2, east 3). That opens an approach to every balloon while the guns
##     left (south side) still cover the balloon and a careless exit.
##   - A Halberstadt moves on from a gun once it is silenced or after TARGET_TIME (about two passes); after its last
##     gun it turns for home (off the north edge). It does not circle until every gun is gone.
##   - When all three are done: "Bombing run complete. Remaining guns still active—attack the balloons!"
##   - The British patrol comes up at 60 s and a second pair at 150 s (mission file): waiting means less AA, but
##     more fighters. Each arrival is announced and highlighted.
##   - HUD: silenced guns per ring, and a grey cross on the minimap where a gun was silenced.

const BOMBERS := {
	3030: {"ring": "West", "guns": [3100, 3104, 3101]},
	3031: {"ring": "Centre", "guns": [3105, 3109]},
	3032: {"ring": "East", "guns": [3110, 3114, 3111]},
}
const RINGS := {"West": [3100, 3101, 3102, 3103, 3104], "Centre": [3105, 3106, 3107, 3108, 3109],
	"East": [3110, 3111, 3112, 3113, 3114]}
const PATROLS := [[3020, 3021], [3022, 3023]]
const TARGET_TIME := 35.0
const HOME_Z := 6400.0  # north of the map (z from 7109): off the map, safely home
const COMPLETE_DELAY := 3.0  # after the last Halberstadt's own line
const COMPLETE_TEXT := "The Halberstadts are turning for home. Some guns are still firing: go for the balloons!"

var _state := {}  # bomber id -> {index, since, done}
var _announced := false
var _all_done_at := -1.0
var _patrols_seen := {}
var _patrols_hidden := {}


func start() -> void:
	super.start()
	for id in BOMBERS:
		var b := plane(id)
		if b == null:
			continue
		_state[id] = {"index": -1, "since": 0.0, "done": false}
		_next_target(id)
	for ring in RINGS:
		for gid in RINGS[ring]:
			var g = object(gid)
			if g is Dictionary:
				_track_object(g, "", Color.WHITE, false, 0.9, SILENCED_ICON)  # nothing drawn until silenced


func _next_target(id: int) -> void:
	var b := plane(id)
	var st: Dictionary = _state[id]
	var guns: Array = BOMBERS[id].guns
	st.index += 1
	while st.index < guns.size() and not alive(object(guns[st.index])):
		st.index += 1
	st.since = now()
	if st.index >= guns.size():
		_withdraw(id)
		return
	set_goals(b, [goal(Aircraft.G_RETALIATE_OFF), goal(Aircraft.G_BOMB_RUN, guns[st.index])])


func _withdraw(id: int) -> void:
	var b := plane(id)
	var st: Dictionary = _state[id]
	if st.done:
		return
	st.done = true
	if b and alive(b):
		fly_to(b, Vector3(b.global_position.x, 650.0, HOME_Z), [], 200.0)
		var ring: String = BOMBERS[id].ring
		message("%s balloon: the Halberstadt has silenced %d of 5 guns and is turning for home." % [ring, _silenced(ring)], 5.0)


func _silenced(ring: String) -> int:
	return RINGS[ring].filter(func(gid: int) -> bool: return not alive(object(gid))).size()


func extra_lines() -> Array[String]:
	return ["Guns silenced   West %d/5   Centre %d/5   East %d/5" % [_silenced("West"), _silenced("Centre"), _silenced("East")]]


func step(dt: float) -> void:
	super.step(dt)
	for id in _state:
		var st: Dictionary = _state[id]
		if st.done:
			continue
		var b := plane(id)
		if b == null or not alive(b):
			st.done = true
			continue
		var guns: Array = BOMBERS[id].guns
		if not alive(object(guns[st.index])) or now() - st.since > TARGET_TIME:
			_next_target(id)
	if _all_done_at < 0.0 and not _state.is_empty() and _state.values().all(func(st: Dictionary) -> bool: return st.done):
		_all_done_at = now()
	if not _announced and _all_done_at >= 0.0 and now() >= _all_done_at + COMPLETE_DELAY:
		_announced = true
		objective(COMPLETE_TEXT, "Burn the three balloons (marked red)")
	for pair in PATROLS:
		var key := str(pair[0])
		if _patrols_seen.has(key):
			continue
		var planes: Array = pair.map(func(id: int) -> Aircraft: return plane(id)).filter(func(q) -> bool: return q != null)
		if planes.any(func(q: Aircraft) -> bool: return q.hidden):
			_patrols_hidden[key] = true  # waiting (their hide goal has run): announce them when they appear
			continue
		planes = planes.filter(func(q: Aircraft) -> bool: return q.present())
		if _patrols_hidden.has(key) and not planes.is_empty():
			_patrols_seen[key] = true
			warn("British scouts coming up from the south!" if _patrols_seen.size() == 1 else "More British scouts from the south!", 5.0)
			highlight(planes, 8.0)
