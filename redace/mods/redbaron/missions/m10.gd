extends "res://mods/redbaron/missions/objective.gd"
## Mission 10, Cambrai: the original rules (six of eight tanks within five minutes) plus objective.gd (intro,
## counter with "need 6", priority marks on the tanks). The squadron's part: Brenner and the rookie (pale blue
## brackets) fight the Camels so the Baron can work on the tanks.
##   - Each wingman starts on his own Camel (not the nearest of the group, re-picked every step); one with nothing to
##     fight goes for the nearest Camel; with none left he forms up on the Baron
##     (station keeping: no zig-zag).
##   - The four Camels over the tanks go for the nearest German. At SECOND_WAVE s (or when two of them are down)
##     a second pair comes in from the south for the wingmen: "More Camels from the south! Brenner has them."

const WINGMEN := [3002, 3003]
const SECOND := [3024, 3025]
const SECOND_WAVE := 100.0
const SLOTS := {3002: Vector3(-35.0, 5.0, -35.0), 3003: Vector3(35.0, -5.0, -35.0)}

var _second_in := false
var _check := 0.0


func start() -> void:
	super.start()
	mark_ally(plane(3002), "Brenner")
	mark_ally(plane(3003), "Rookie")
	# each wingman takes his own Camel and keeps it until it falls (a group target re-picks the nearest Camel every
	# step, so they swapped targets mid-turn)
	var camels := _camels().filter(func(c: Aircraft) -> bool: return not c.object_id in SECOND)
	for i in WINGMEN.size():
		var w := plane(WINGMEN[i])
		if w == null or camels.is_empty():
			continue
		var c: Aircraft = camels[mini(i, camels.size() - 1)]
		var plan := [goal(Aircraft.G_ATTACK, c.object_id)]
		var head := w.current_goal()
		if int(head.get("type", 0)) == Aircraft.G_APPEAR:
			plan.push_front(head)
		set_goals(w, plan)


func _camels() -> Array[Aircraft]:
	var out: Array[Aircraft] = []
	for q in world.planes:
		if q.plane_name == "sopwithcamel_rb" and q.present() and alive(q):
			out.append(q)
	return out


func step(dt: float) -> void:
	super.step(dt)
	var p := world.player
	if not alive(p):
		return
	if not _second_in:
		var down := 0
		for id in [3020, 3021, 3022, 3023]:
			if plane(id) and not alive(plane(id)):
				down += 1
		if now() >= SECOND_WAVE or down >= 2:
			_second_in = true
			_bring_second(p)
	_check -= dt
	if _check > 0.0:
		return
	_check = 1.0
	var camels := _camels()
	for id in WINGMEN:
		var w := plane(id)
		if w == null or not alive(w):
			continue
		var type := int(w.current_goal().get("type", 0))
		if type == Aircraft.G_ATTACK or type == Aircraft.G_EVADE or type == Aircraft.G_APPEAR:
			continue
		var best: Aircraft = null
		for c in camels:
			if best == null or distance(c, w) < distance(best, w):
				best = c
		if best:
			attack(w, best)
		elif type != Aircraft.G_FORMATION:
			formation(w, p, SLOTS[id])


func _bring_second(p: Aircraft) -> void:
	var shown: Array[Aircraft] = []
	var anchor: Aircraft = plane(3002) if plane(3002) and alive(plane(3002)) else p
	for i in SECOND.size():
		var c := plane(SECOND[i])
		if c == null:
			continue
		var at := Vector3(anchor.global_position.x + (i * 2 - 1) * 150.0, maxf(anchor.global_position.y + 120.0, 500.0),
			minf(anchor.global_position.z + 1200.0, world.map_bounds.end.y - 300.0))
		var w := plane(WINGMEN[i])
		var target: Aircraft = w if w and alive(w) else p
		reveal(c, at, [goal(Aircraft.G_ATTACK, target.object_id)], target.global_position - at)
		shown.append(c)
	warn("More Camels from the south! Brenner has them.", 5.0)
	highlight(shown, 7.0)
