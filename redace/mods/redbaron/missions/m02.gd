extends "res://mods/redbaron/mission_script.gd"
## Mission 2, First Sortie: Brenner starts on the Baron's wing, heading north on patrol. At 6 s he breaks
## off after a decoy Bristol Scout flying east toward the British AA, and the HUD says so. He is faster
## than the Baron (highspeed 118 against 110). Once he has been 300 away (or 15 s after the break) the
## player can catch him: within 200 he forms up again ("Brenner joins. Return to base."). The win is
## both within 300 of the aerodrome, marked on the minimap. Brenner lost fails it (Group2 = 100).
## The decoy and the ambush are optional kills.

const AERODROME := Vector3(6200, 0, 7450)
const BREAK_AT := 6.0  # Brenner breaks off after the decoy
const AWAY_RANGE := 300.0  # he must have been this far away before catching him counts
const AWAY_TIME := 15.0  # ... or this long after the break
const REJOIN_RANGE := 200.0
const HOME_RANGE := 300.0

var brenner: Aircraft
var broke_off := false
var broke_time := 0.0
var armed := false  # Brenner has got away, so closing on him now counts as catching him
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
		if not broke_off:
			if now() < BREAK_AT:
				return
			broke_off = true
			broke_time = now()
			var decoy := plane(3003)
			attack(brenner, decoy if alive(decoy) else -9)
			message("Brenner breaks off after a Scout! Catch him to call him back.", 6.0)
		if not armed and (distance(p, brenner) > AWAY_RANGE or now() > broke_time + AWAY_TIME):
			armed = true
		if armed and near(p, brenner, REJOIN_RANGE):
			rejoined = true
			formation(brenner, p, Vector3(-30.0, 0.0, -30.0))
			message("Brenner joins. Return to base.", 6.0)
	elif near(p, AERODROME, HOME_RANGE, true) and near(brenner, AERODROME, HOME_RANGE, true):
		win()
