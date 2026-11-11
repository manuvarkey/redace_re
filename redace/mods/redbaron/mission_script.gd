extends RefCounted
## Base of the Red Baron mission scripts (missions/mNN.gd). init.gd makes one per flight and calls
## run_step every physics step (after the player's input, before the rules) and outcome() with the
## rules' decision. A script overrides start() and step(dt) and uses the helpers below.
## Objects are Aircraft, ground objects (World target dictionaries) or positions (Vector3).

var world: World
var mod: Node  # init.gd
var owns_win := false  # true: the rules' "won" (e.g. all enemies destroyed) is ignored; win() decides
var end_messages := {}  # result -> end-of-flight line ("" = none); missing = the original line
var result_pages := {}  # result -> menu page path after the flight; missing = the original page
var started := false
var _result := ""
var _timers: Array[Dictionary] = []  # {at, fn}
var _flags := {}


## Called once, on the first physics step (all objects exist by then).
func start() -> void:
	pass


## Called every physics step after start().
func step(_dt: float) -> void:
	pass


func run_step(dt: float) -> void:
	if not started:
		started = true
		start()
	var due := _timers.filter(func(t: Dictionary) -> bool: return now() >= t.at)
	_timers = _timers.filter(func(t: Dictionary) -> bool: return now() < t.at)
	for t in due:
		(t.fn as Callable).call()
	step(dt)
	track_markers()


func outcome(stock: String) -> String:
	if _result != "":
		return _result
	if owns_win and stock == "won":
		return ""
	return stock


func page_for(result: String, _campaign: bool) -> String:
	return str(result_pages.get(result, ""))


# ---------------------------------------------------------------- time

func now() -> float:
	return world.mission_time


## Runs fn once, seconds from now.
func after(seconds: float, fn: Callable) -> void:
	_timers.append({"at": now() + seconds, "fn": fn})


## True the first time it is asked for key, false afterwards.
func once(key: String) -> bool:
	if _flags.has(key):
		return false
	_flags[key] = true
	return true


func flag(key: String) -> bool:
	return _flags.has(key)


# ---------------------------------------------------------------- objects and distances

func plane(id: int) -> Aircraft:
	var o = world.objects_by_id.get(id)
	return o if o is Aircraft else null


func object(id: int) -> Variant:
	return world.objects_by_id.get(id)


static func position(o: Variant) -> Vector3:
	if o is Aircraft:
		return (o as Aircraft).global_position
	if o is Dictionary:
		return (o.node as Node3D).global_position
	return o as Vector3


## Distance between objects or positions; flat = along the ground.
static func distance(a: Variant, b: Variant, flat := false) -> float:
	var d := position(a) - position(b)
	if flat:
		d.y = 0.0
	return d.length()


static func near(a: Variant, b: Variant, within: float, flat := false) -> bool:
	return distance(a, b, flat) < within


static func alive(o: Variant) -> bool:
	if o is Aircraft:
		return (o as Aircraft).state != Aircraft.State.DEAD
	return o is Dictionary and not o.dead


func planes_in_group(group: int) -> Array[Aircraft]:
	var out: Array[Aircraft] = []
	for p in world.planes:
		if p.groups & (1 << group):
			out.append(p)
	return out


# ---------------------------------------------------------------- goals

## A goal as the mission files give it: type (decimal), targetid (> 0 object id, <= 0 group -id), pos, real.
static func goal(type: int, target := 0, pos := Vector3.ZERO, real := 50.0) -> Dictionary:
	return {"type": type, "targetid": target, "pos": pos, "radius": real}


## Replaces a plane's whole goal list; the first goal runs from the next AI step.
static func set_goals(p: Aircraft, list: Array) -> void:
	var goals: Array[Dictionary] = []
	for g in list:
		goals.append((g as Dictionary).duplicate())
	p.goals = goals
	p.goal_index = 0
	p.set("_goal_timer", 0.0)


## Gun attack (0x70) on an aircraft, a ground object, an object id or a group (-N), then the goals after.
static func attack(p: Aircraft, target: Variant, then := []) -> void:
	set_goals(p, [goal(Aircraft.G_ATTACK, _target_id(target))] + then)


## Formation (0x30) on leader at offset (leader's flat frame: x left, z ahead).
static func formation(p: Aircraft, leader: Aircraft, offset := Vector3(-25.0, 0.0, -25.0)) -> void:
	var g := goal(Aircraft.G_FORMATION, leader.object_id)
	g.offset = offset
	set_goals(p, [g])


## Fly to pos (0x20), then the goals after.
static func fly_to(p: Aircraft, pos: Vector3, then := [], within := 100.0) -> void:
	set_goals(p, [goal(Aircraft.G_WAYPOINT, 0, pos, within)] + then)


static func _target_id(target: Variant) -> int:
	if target is Aircraft:
		return (target as Aircraft).object_id
	if target is Dictionary:
		return int(target.id)
	return int(target)


## Brings a hidden plane into the world at pos, flying at full speed (0x100), then the goals after.
## face: direction to head (flattened); zero keeps the heading it was placed with.
static func reveal(p: Aircraft, pos: Vector3, then := [], face := Vector3.ZERO) -> void:
	var flat := Vector3(face.x, 0.0, face.z)
	if flat.length_squared() > 0.01:
		p.flight_basis = Basis.looking_at(-flat.normalized(), Vector3.UP)
	set_goals(p, [goal(Aircraft.G_APPEAR, 0, pos)] + then)
	p._set_hidden(false)


## Takes a plane out of the world (0x170): not drawn, targeted or hit.
static func hide(p: Aircraft) -> void:
	p._set_hidden(true)


## Damage as a hit does it (smoke, sounds, shot down at endurance).
static func damage(p: Aircraft, amount: float, attacker: Variant = null) -> void:
	p.take_damage(amount, attacker)


# ---------------------------------------------------------------- HUD, environment, results

## The mod's screen overlay (wound effect, counter and objective lines, brackets, cues), made on first use.
func overlay() -> CanvasLayer:
	if mod.get("overlay") == null:
		mod.overlay = load("res://mods/redbaron/overlay.gd").new()
		mod.overlay.world = world
		mod.add_child(mod.overlay)
	return mod.overlay


func message(text: String, seconds := 3.0) -> void:
	world.show_message(text, seconds)


## A minimap icon at pos (drawn like the map's other icons, held at the rim when far away). Returns the
## marker, which unmark() removes.
func mark_on_map(pos: Vector3, icon := "res://mods/redbaron/aerodrome_icon.png") -> Dictionary:
	var m := {"pos": pos, "icon": icon, "size": 1.5}
	world.map_markers.append(m)
	return m


func unmark(m: Dictionary) -> void:
	world.map_markers.erase(m)


## The original target icon on the minimap for a plane, moved with it every step (track_markers) and
## removed once it is no longer in the world. The minimap draws aircraft only for groups 8 and 9, so
## a target plane in group 4 + 7 (Hawker, the plates) would otherwise not show.
var _tracked := {}  # Aircraft -> marker
var _tracked_objects: Array[Dictionary] = []  # {target (ground object), marker, dead_icon}


func track_on_map(p: Aircraft, icon := "smalltarget", colour := Color.WHITE, pulse := false, size := 1.0) -> Dictionary:
	if not _tracked.has(p):
		_tracked[p] = mark_on_map(p.global_position, icon)
	var m: Dictionary = _tracked[p]
	m.icon = icon
	m.size = size
	m.color = colour
	m.pulse = pulse
	return m


func untrack(p: Aircraft) -> void:
	if _tracked.has(p):
		unmark(_tracked[p])
		_tracked.erase(p)


func track_markers() -> void:
	for p in _tracked.keys():
		var m: Dictionary = _tracked[p]
		if not is_instance_valid(p) or not p.present():
			unmark(m)
			_tracked.erase(p)
		else:
			m.pos = p.global_position
	for m in _highlights:
		var f = m.get("follow")
		if is_instance_valid(f):
			m.pos = (f as Node3D).global_position
	for e in _tracked_objects:
		if e.target.dead and not e.get("done", false):
			e.done = true
			if e.dead_icon == "":
				unmark(e.marker)
			else:
				e.marker.icon = e.dead_icon
				e.marker.color = Color(0.75, 0.75, 0.75, 0.8)
				e.marker.pulse = false


# ---------------------------------------------------------------- consistent markers (every mission alike)
# priority  the targets the objective names: red-orange target icon (slow blink) on the minimap, red-orange bracket
# protect   what must survive: green ring on the minimap, green bracket with distance (and an edge arrow for planes)
# ally      a wingman whose cover matters: pale blue bracket with distance
# threat    a short warning: yellow blinking enemy icon and bracket for a few seconds
# destination  where to go: the aerodrome icon on the minimap (blinking while it is the objective)

const PROTECT_ICON := "res://mods/redbaron/protect_icon.png"
const SILENCED_ICON := "res://mods/redbaron/silenced_icon.png"
const AERODROME_ICON := "res://mods/redbaron/aerodrome_icon.png"
const PRIORITY_COLOUR := Color(1.0, 0.38, 0.2)
const PROTECT_COLOUR := Color(0.45, 1.0, 0.45)
const THREAT_COLOUR := Color(1.0, 0.9, 0.2)


static func _node_of(o: Variant) -> Node3D:
	if o is Aircraft:
		return o
	if o is Dictionary:
		return o.node
	return null


func _track_object(t: Dictionary, icon: String, colour: Color, pulse: bool, size: float, dead_icon := "") -> void:
	var m := mark_on_map(position(t), icon)
	m.color = colour
	m.pulse = pulse
	m.size = size
	_tracked_objects.append({"target": t, "marker": m, "dead_icon": dead_icon})


## A target the objective names (an Aircraft or a ground object).
func mark_priority(o: Variant, label := "", arrow := false) -> void:
	if o is Aircraft:
		track_on_map(o, "smalltarget", PRIORITY_COLOUR, true, 1.2)
	elif o is Dictionary:
		_track_object(o, "smalltarget", PRIORITY_COLOUR, true, 1.0)
	overlay().add_bracket(_node_of(o), "priority", label, arrow)


## Something that must survive (an Aircraft or a ground object). Ground objects: dead_icon marks the ruin.
func mark_protect(o: Variant, label := "", arrow := true, dead_icon := SILENCED_ICON) -> void:
	if o is Aircraft:
		track_on_map(o, PROTECT_ICON, PROTECT_COLOUR, false, 1.4)
		overlay().add_bracket(o, "protect", label, arrow, 0.0, 6000.0)
	elif o is Dictionary:
		_track_object(o, PROTECT_ICON, PROTECT_COLOUR, false, 0.9, dead_icon)
		overlay().add_bracket(_node_of(o), "protect", label, false, 0.0, 1200.0)


## A wingman whose cover the player should see (bracket only; the minimap shows him as an ally already).
func mark_ally(p: Aircraft, label: String) -> void:
	overlay().add_bracket(p, "ally", label, false, 0.0, 3000.0)


## A short warning highlight on planes coming in: blinking yellow on the minimap and in the view.
func highlight(planes: Array, seconds := 8.0, label := "") -> void:
	for p in planes:
		if p == null:
			continue
		var m := mark_on_map(position(p), "smallenemy")
		m.color = THREAT_COLOUR
		m.pulse = true
		m.size = 1.6
		m.follow = p
		_highlights.append(m)
		overlay().add_bracket(p, "threat", label, true, seconds)
		after(seconds, func() -> void:
			unmark(m)
			_highlights.erase(m))


var _highlights: Array[Dictionary] = []


## The aerodrome (or another safe place) on the minimap; blinks while active is true.
func mark_destination(pos: Vector3, active := false) -> Dictionary:
	var m := mark_on_map(pos, AERODROME_ICON)
	m.pulse = active
	return m


## A new objective: HUD message, cue sound, and the objective line (line, or the message itself).
func objective(text: String, line := "", seconds := 6.0) -> void:
	message(text, seconds)
	overlay().cue("objective")
	overlay().set_objective(line if line != "" else text)


## A warning: HUD message and a warning cue.
func warn(text: String, seconds := 5.0) -> void:
	message(text, seconds)
	overlay().cue("warning")


## Lays a long, flat ground object (a rail segment) on the terrain: both ends on the ground (half_length along its
## stored `at`, scale included), so neighbouring segments meet at the same height; rolled to the slope across it.
func lay_on_ground(t: Dictionary, half_length: float) -> void:
	var node: Node3D = t.node
	var b := node.global_transform.basis
	var p := node.global_position
	var along := Vector3(b.z.x, 0.0, b.z.z)
	var reach := along.length() * half_length
	var dir := along.normalized()
	var a := p - dir * reach
	var e := p + dir * reach
	a.y = world.ground_height(a)
	e.y = world.ground_height(e)
	var mid := (a + e) * 0.5
	# a hump between the ends: lift the segment over it rather than let the ground show through
	var lift := 0.0
	for f in [0.25, 0.5, 0.75]:
		var q: Vector3 = a.lerp(e, f)
		lift = maxf(lift, world.ground_height(q) - q.y)
	mid.y += minf(lift, 1.2)  # capped: a bigger lift leaves a visible step at the joints
	var fwd := (e - a).normalized()
	var n := world.ground_normal(mid)
	var right := n.cross(fwd).normalized()
	var up := fwd.cross(right).normalized()
	var sc := b.get_scale()
	node.global_transform = Transform3D(Basis(right * sc.x, up * sc.y, fwd * ((e - a).length() / (2.0 * half_length))), mid)


## Puts a ground object on the terrain under it (scenery placed by a mission at height 0); tilt: lie along the slope.
func snap_to_ground(t: Dictionary, lift := 0.0, tilt := false) -> void:
	var node: Node3D = t.node
	var p := node.global_position
	var h := world.ground_height(p)
	var b := node.global_transform.basis
	if tilt:
		var n := world.ground_normal(p)
		var sc := b.get_scale()
		var at := (b.z.normalized() - n * b.z.normalized().dot(n)).normalized()
		var right := n.cross(at).normalized()
		b = Basis(right * sc.x, n * sc.y, at * sc.z)
	node.global_transform = Transform3D(b, Vector3(p.x, h + lift, p.z))


func set_fog(colour: Color) -> void:
	mod.set_fog(colour)


func set_sky(dir: String) -> void:
	mod.set_sky(dir)


## Ends the flight as a win at the next rules check.
func win() -> void:
	if _result == "":
		_result = "won"


## Ends the flight as a loss at the next rules check: "death", "time", "defence" or a script's own name.
func lose(result := "defence") -> void:
	if _result == "":
		_result = result


func secure_progress() -> void:
	world.secure_progress()
