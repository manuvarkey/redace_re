extends "res://mods/redbaron/mission_script.gd"
## Mission 2, First Sortie. Each step of the story has its own HUD line, at least MESSAGE_GAP apart:
##   1. 6 s: Brenner breaks off from the Baron's wing after a decoy Bristol Scout flying east toward the
##      British AA ("Brenner breaks off after a Scout!"). He is faster than the Baron (125 against 110)
##      and flies at it flat out (a waypoint on the Scout, not a gun attack, which matches its speed).
##   2. Brenner closes within 300 of the Scout, or the Scout goes down: "Brenner is over the British
##      guns! Get him out of there." Only from here does catching him count.
##   3. The Baron within 200 of Brenner: he forms up ("Brenner joins. Return to the aerodrome.").
##   4. Halfway home (flat distance to the aerodrome down to half of what it was at the rejoin), two
##      hidden Nieuports are revealed ahead and to the side and attack the Baron and Brenner.
##   Win: both within 300 of the aerodrome (marked on the minimap). Brenner lost fails it (Group2 = 100).
##   The decoy, the ambush over the AA and the interceptors are optional kills.

const AERODROME := Vector3(6200, 0, 7450)
const BREAK_AT := 6.0
const SCOUT_RANGE := 300.0  # Brenner this close to the Scout: in danger, catching him now counts
const REJOIN_RANGE := 200.0
const HOME_RANGE := 300.0
const MESSAGE_GAP := 4.0  # seconds between story steps, so no two lines replace each other at once

var brenner: Aircraft
var decoy: Aircraft
var interceptors: Array[Aircraft] = []
var broke_off := false
var armed := false  # Brenner is near the Scout: closing on him now counts as catching him
var rejoined := false
var intercepted := false
var last_event := -100.0
var rejoin_distance := 0.0


func start() -> void:
	owns_win = true
	brenner = plane(3002)
	decoy = plane(3003)
	interceptors.assign([plane(3006), plane(3007)])
	mark_on_map(AERODROME)


func _event(text: String) -> void:
	last_event = now()
	message(text, 6.0)


func step(_dt: float) -> void:
	var p := world.player
	if brenner == null or not alive(brenner) or not alive(p):
		return  # the original rules end it (Brenner: mission critical; the Baron: plane destroyed)
	var ready := now() >= last_event + MESSAGE_GAP
	if not broke_off:
		if now() >= BREAK_AT:
			broke_off = true
			_chase()
			_event("Brenner breaks off after a Scout! Catch him to call him back.")
	elif not armed:
		_chase()
		if ready and (not alive(decoy) or near(brenner, decoy, SCOUT_RANGE)):
			armed = true
			attack(brenner, decoy if alive(decoy) else -9)
			_event("Brenner is over the British guns! Get him out of there.")
	elif not rejoined:
		if ready and near(p, brenner, REJOIN_RANGE):
			rejoined = true
			rejoin_distance = distance(p, AERODROME, true)
			formation(brenner, p, Vector3(-30.0, 0.0, -30.0))
			_event("Brenner joins. Return to the aerodrome.")
	else:
		if not intercepted and ready and distance(p, AERODROME, true) <= rejoin_distance * 0.5:
			intercepted = true
			_intercept(p)
		if near(p, AERODROME, HOME_RANGE, true) and near(brenner, AERODROME, HOME_RANGE, true):
			win()


## Brenner runs for the Scout flat out: a waypoint on it, renewed every step (a gun attack would match the
## Scout's speed and keep him level with the Baron). He attacks once he is on it.
func _chase() -> void:
	if not alive(decoy):
		return
	var g := brenner.current_goal()
	if int(g.get("type", 0)) == Aircraft.G_WAYPOINT:
		g.pos = decoy.global_position
	else:
		fly_to(brenner, decoy.global_position, [], 50.0)
	brenner.throttle = 1.0


## Two Nieuports dive in from ahead and to the right of the way home, one on the Baron, one on Brenner.
func _intercept(p: Aircraft) -> void:
	var home := AERODROME - p.global_position
	home.y = 0.0
	home = home.normalized()
	var side := home.cross(Vector3.UP)
	var targets: Array[Aircraft] = [p, brenner]
	for i in interceptors.size():
		var q := interceptors[i]
		if q and q.hidden:
			var at := p.global_position + home * 500.0 + side * (350.0 + 60.0 * i) + Vector3.UP * (90.0 + 20.0 * i)
			reveal(q, at, [goal(Aircraft.G_ATTACK, targets[i].object_id)], targets[i].global_position - at)
	_event("Enemy scouts ahead! Protect Brenner.")
