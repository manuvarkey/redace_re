extends "res://mods/redbaron/missions/objective.gd"
## Mission 5, The Plates: the original rules plus objective.gd (intro, target icon, escape = fail).
## The two S.E.5a escorts fly in formation on the recon plane; when the Baron engages it (comes within
## ENGAGE_RANGE of it, or it is hit) they turn on him. If he falls back beyond RELEASE_RANGE they form up
## on the recon plane again.

const RECON := 3010
const ESCORTS := [3020, 3021]
const ENGAGE_RANGE := 700.0
const RELEASE_RANGE := 1500.0

var recon: Aircraft
var escorts: Array[Aircraft] = []
var engaged := false
var _offsets := {}  # escort -> its formation offset from the mission file
var _check := 0.0


func start() -> void:
	super.start()
	recon = plane(RECON)
	for id in ESCORTS:
		var e := plane(id)
		if e:
			escorts.append(e)
			var g := e.goals.filter(func(x): return x.type == Aircraft.G_FORMATION)
			_offsets[e] = g[0].get("offset", Vector3(-40, 0, -40)) if not g.is_empty() else Vector3(-40, 0, -40)
	recon.damaged.connect(func(_p, _a, _attacker): _engage())


func _engage() -> void:
	if engaged:
		return
	engaged = true
	for e in escorts:
		if alive(e):
			attack(e, world.player)


func step(dt: float) -> void:
	super.step(dt)
	_check -= dt
	if _check > 0.0 or recon == null or not alive(recon):
		return
	_check = 0.5
	var p := world.player
	if not engaged and near(p, recon, ENGAGE_RANGE):
		_engage()
	elif engaged and not near(p, recon, RELEASE_RANGE):
		engaged = false
		for e in escorts:
			if alive(e):
				var g := goal(Aircraft.G_FORMATION, RECON)
				g.offset = _offsets[e]
				set_goals(e, [g])
