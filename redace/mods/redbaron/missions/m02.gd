extends "res://mods/redbaron/mission_script.gd"
## Mission 2, First Sortie: Brenner breaks off after a decoy toward the British AA. Once he is away
## (250 from the Baron, or after 10 s) the HUD says so; the player then catches him (within 200), which
## puts him back in formation ("Brenner joins. Return to base."), and leads him home: the win is both
## within 300 of the aerodrome, which is marked on the minimap. Brenner lost fails it (Group2 = 100).
## The decoy and the ambush are optional kills.

const AERODROME := Vector3(6200, 0, 7450)
const REJOIN_RANGE := 200.0
const BREAK_RANGE := 250.0
const BREAK_TIME := 10.0
const HOME_RANGE := 300.0

var brenner: Aircraft
var armed := false  # Brenner has broken away, so closing on him now counts as catching him
var rejoined := false


func start() -> void:
	owns_win = true
	brenner = plane(3002)
	mark_on_map(AERODROME)


func step(_dt: float) -> void:
	var p := world.player
	if brenner == null or not alive(brenner) or not alive(p):
		return  # the original rules end it (Brenner: mission critical; the Baron: plane destroyed)
	if not rejoined:
		if not armed and (distance(p, brenner) > BREAK_RANGE or now() > BREAK_TIME):
			armed = true
			message("Brenner breaks off after the Scout! Fly close to him to call him back.", 6.0)
		if armed and near(p, brenner, REJOIN_RANGE):
			rejoined = true
			formation(brenner, p, Vector3(-30.0, 0.0, -30.0))
			message("Brenner joins. Return to base.", 6.0)
	elif near(p, AERODROME, HOME_RANGE, true) and near(brenner, AERODROME, HOME_RANGE, true):
		win()
