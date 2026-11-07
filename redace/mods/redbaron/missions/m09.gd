extends "res://mods/redbaron/missions/objective.gd"
## Mission 9, Dusk Raiders: the original rules plus objective.gd (intro, counter, target icons, the yard
## marker). Three Handley Pages fly well apart (a staggered vic, 500+ between them); five Camels escort them
## at the bombers' speed (keepstation):
##   close escorts  one per bomber, a slot off its wing; a German within ENGAGE_RANGE of the bomber or of
##                  the escort (or a hit on the bomber) turns it on the nearest German; it forms up again
##                  when none is within RELEASE_RANGE. With its bomber down it hunts.
##   sweep          two Camels SWEEP_AHEAD in front of the lead bomber, clearing the way: they turn on a
##                  German within SWEEP_ENGAGE of themselves and go back on station when none is within
##                  SWEEP_RELEASE, or when the fight has drawn them SWEEP_LEASH from the lead bomber.

const BOMBERS := [3010, 3011, 3012]
## Slots in the leader's frame (x left, y up, z ahead); the O/100 spans 76, the Camel 16.
const CLOSE := {
	3020: [3010, Vector3(-110.0, 30.0, -40.0)],
	3021: [3011, Vector3(110.0, 30.0, -40.0)],
	3022: [3012, Vector3(-110.0, 30.0, -40.0)],
}
const SWEEP_AHEAD := 700.0
const SWEEP := {3023: Vector3(150.0, 60.0, SWEEP_AHEAD), 3024: Vector3(-150.0, 60.0, SWEEP_AHEAD)}
const ENGAGE_RANGE := 800.0
const RELEASE_RANGE := 1600.0
const SWEEP_ENGAGE := 1000.0
const SWEEP_RELEASE := 1800.0
const SWEEP_LEASH := 2500.0

var escorts: Array[Aircraft] = []
var _check := 0.0


func start() -> void:
	super.start()
	for id in CLOSE:
		_station(plane(id), plane(CLOSE[id][0]), CLOSE[id][1])
	for id in SWEEP:
		_station(plane(id), plane(BOMBERS[0]), SWEEP[id])
	for id in BOMBERS:
		var b := plane(id)
		if b:
			b.damaged.connect(func(_p, _a, _attacker): _check = 0.0)


## Puts an escort on its slot (the appear goal: flying, at full speed), then the formation goal.
func _station(e: Aircraft, leader: Aircraft, offset: Vector3) -> void:
	if e == null or leader == null:
		return
	escorts.append(e)
	e.flight_basis = leader.flight_basis
	var f := goal(Aircraft.G_FORMATION, leader.object_id)
	f.offset = offset
	set_goals(e, [goal(Aircraft.G_APPEAR, 0, leader.global_position + leader.flight_basis * offset), f])


func _germans_near(o: Aircraft, r: float) -> Aircraft:
	var best: Aircraft = null
	for q in world.planes:
		if q.allied and q.present() and near(q, o, r) and (best == null or distance(q, o) < distance(best, o)):
			best = q
	return best


func _lead_bomber() -> Aircraft:
	for id in BOMBERS:
		if plane(id) and plane(id).present():
			return plane(id)
	return null


func step(dt: float) -> void:
	super.step(dt)
	_check -= dt
	if _check > 0.0:
		return
	_check = 0.5
	for e in escorts:
		if not e.present():
			continue
		var type := int(e.current_goal().get("type", 0))
		if type == Aircraft.G_APPEAR:
			continue  # not in the air yet
		var attacking := type == Aircraft.G_ATTACK
		var leader: Aircraft
		var offset: Vector3
		var threat: Aircraft
		var stay := false  # a German still near enough to keep fighting
		if CLOSE.has(e.object_id):
			leader = plane(CLOSE[e.object_id][0])
			offset = CLOSE[e.object_id][1]
			if leader == null or not leader.present():
				if not attacking:
					attack(e, -8)
				continue
			threat = _germans_near(leader, ENGAGE_RANGE)
			if threat == null:
				threat = _germans_near(e, ENGAGE_RANGE)
			stay = _germans_near(leader, RELEASE_RANGE) != null
		else:
			leader = _lead_bomber()
			offset = SWEEP[e.object_id]
			if leader == null:
				if not attacking:
					attack(e, -8)
				continue
			var leashed := distance(e, leader) < SWEEP_LEASH
			threat = _germans_near(e, SWEEP_ENGAGE) if leashed else null
			stay = leashed and _germans_near(e, SWEEP_RELEASE) != null
		if threat:
			if not attacking:
				attack(e, threat)
		elif not (attacking and stay) and not (type == Aircraft.G_FORMATION and int(e.current_goal().targetid) == leader.object_id):
			formation(e, leader, offset)
