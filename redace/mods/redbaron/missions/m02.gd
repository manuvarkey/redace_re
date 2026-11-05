extends "res://mods/redbaron/mission_script.gd"
## Mission 2, First Sortie: Brenner breaks off after a decoy toward the British AA. The player must
## catch him (within 150), which puts him back in formation, and lead him home: the win is both within
## 300 of the aerodrome. Brenner lost fails it (Group2 = 100). The decoy and the ambush are optional kills.

const AERODROME := Vector3(6200, 0, 7450)
const REJOIN_RANGE := 150.0
const HOME_RANGE := 300.0

var brenner: Aircraft
var armed := false  # Brenner has broken away, so closing on him now counts as catching him
var rejoined := false


func start() -> void:
	owns_win = true
	brenner = plane(3002)


func step(_dt: float) -> void:
	var p := world.player
	if brenner == null or not alive(brenner) or not alive(p):
		return  # the original rules end it (Brenner: mission critical; the Baron: plane destroyed)
	if not rejoined:
		if not armed and (distance(p, brenner) > 300.0 or now() > 20.0):
			armed = true
		if armed and near(p, brenner, REJOIN_RANGE):
			rejoined = true
			formation(brenner, p, Vector3(-30.0, 0.0, -30.0))
			message("Brenner rejoins")
	elif near(p, AERODROME, HOME_RANGE, true) and near(brenner, AERODROME, HOME_RANGE, true):
		win()
