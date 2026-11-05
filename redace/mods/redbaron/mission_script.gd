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

## The mod's screen overlay (wound effect, counter line), made on first use.
func overlay() -> CanvasLayer:
	if mod.get("overlay") == null:
		mod.overlay = load("res://mods/redbaron/overlay.gd").new()
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


func track_on_map(p: Aircraft, icon := "smalltarget") -> void:
	if not _tracked.has(p):
		_tracked[p] = mark_on_map(p.global_position, icon)
		_tracked[p].size = 1.0


func track_markers() -> void:
	for p in _tracked.keys():
		var m: Dictionary = _tracked[p]
		if not is_instance_valid(p) or not p.present():
			unmark(m)
			_tracked.erase(p)
		else:
			m.pos = p.global_position


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
