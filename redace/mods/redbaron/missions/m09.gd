extends "res://mods/redbaron/missions/objective.gd"
## Mission 9, Dusk Raiders: the original rules plus objective.gd (intro, counter, target icons, the yard
## marker). Five Camels escort the three Handley Pages in formation; a German plane within ENGAGE_RANGE of
## a bomber (or a hit on a bomber) turns them on the nearest German; they form up on their bomber again when
## no German is within RELEASE_RANGE of it.

const BOMBERS := [3010, 3011, 3012]
const ENGAGE_RANGE := 800.0
const RELEASE_RANGE := 1600.0

var escorts: Array[Aircraft] = []
var _formation := {}  # escort -> its formation goal from the mission file
var _check := 0.0


func start() -> void:
	super.start()
	for p in world.planes:
		if p.plane_name == "sopwithcamel":
			escorts.append(p)
			var g := p.goals.filter(func(x): return x.type == Aircraft.G_FORMATION)
			if not g.is_empty():
				_formation[p] = (g[0] as Dictionary).duplicate()
	for id in BOMBERS:
		var b := plane(id)
		if b:
			b.damaged.connect(func(_p, _a, _attacker): _check = 0.0)


func _germans_near(b: Aircraft, r: float) -> Aircraft:
	var best: Aircraft = null
	for q in world.planes:
		if q.allied and q.present() and near(q, b, r) and (best == null or distance(q, b) < distance(best, b)):
			best = q
	return best


func step(dt: float) -> void:
	super.step(dt)
	_check -= dt
	if _check > 0.0:
		return
	_check = 0.5
	for e in escorts:
		if not e.present() or not _formation.has(e):
			continue
		var lead := plane(int(_formation[e].targetid))
		var g := e.current_goal()
		var attacking := int(g.get("type", 0)) == Aircraft.G_ATTACK
		var bomber := lead if lead and lead.present() else null
		if bomber == null:
			for id in BOMBERS:
				if plane(id) and plane(id).present():
					bomber = plane(id)
					break
		if bomber == null:
			if not attacking:
				attack(e, -8)
			continue
		var threat := _germans_near(bomber, ENGAGE_RANGE)
		if threat and not attacking:
			attack(e, threat)
		elif attacking and _germans_near(bomber, RELEASE_RANGE) == null:
			var f: Dictionary = _formation[e].duplicate()
			f.targetid = bomber.object_id
			set_goals(e, [f])
