extends "res://mods/redbaron/mission_script.gd"
## Mission 8, Wounded: an ordinary attack on four F.E.2ds (aircodh2 stand-ins with observers' guns).
## The first observer hit after 30 s, while the player is within 150 of an F.E.2d, wounds him: the view
## dims and blurs, the throttle is held at half and the guns stop. The F.E.2ds turn for home; one
## Nieuport is revealed behind the Baron and attacks for 25 s before breaking off, and Brenner goes for
## it 12 s after the wound. Landing within 300 of the aerodrome wins; a crash loses
## (the original "plane destroyed"). If the player brings all four down unhurt, the last one's parting
## burst wounds him (the story needs the wound; see IMPLEMENTATION_NOTES).

const AERODROME := Vector3(6200, 0, 7450)
const WOUND_AFTER := 30.0
const WOUND_RANGE := 150.0
const HOME_RANGE := 300.0
const THROTTLE_CAP := 0.5
const BRITISH_EDGE_X := 9600.0  # east of the map box (x up to 9358): planes sent here leave the battle
const PURSUIT_TIME := 25.0  # the Nieuport that gets through attacks this long, then turns for home
const BRENNER_DELAY := 12.0  # Brenner turns on the Nieuport this long after the wound

var brenner: Aircraft
var pursuer: Aircraft
var fe2ds: Array[Aircraft] = []
var wounded := false
var wound_time := -1.0
var _escort_check := 0.0


func start() -> void:
	owns_win = true
	brenner = plane(3002)
	pursuer = plane(3020)
	for p in world.planes:
		if p.plane_name == "aircodh2":
			fe2ds.append(p)
			p.destroyed.connect(_on_fe2d_down)
	world.player.damaged.connect(_on_player_hit)
	mark_on_map(AERODROME)


func _on_player_hit(_p: Aircraft, _amount: float, attacker: Variant) -> void:
	if wounded or now() < WOUND_AFTER or not (attacker is Aircraft) or not fe2ds.has(attacker):
		return
	if near(world.player, attacker, WOUND_RANGE):
		wound()


func _on_fe2d_down(_p: Aircraft) -> void:
	if not wounded and fe2ds.all(func(f: Aircraft) -> bool: return not alive(f)):
		wound()


func wound() -> void:
	if wounded:
		return
	wounded = true
	wound_time = now()
	print("mission 8: wounded at %.1f s" % now())
	overlay().wound = 1.0
	message("You are wounded! Land at the aerodrome.", 6.0)
	var p := world.player
	# the F.E.2ds have done their work and turn for home (east, off the map); their observers only fire
	# at what is behind or above them, so they no longer chase the Baron
	for f in fe2ds:
		if f.present():
			set_goals(f, [goal(Aircraft.G_RETALIATE_OFF), goal(Aircraft.G_WAYPOINT, 0,
				Vector3(BRITISH_EDGE_X, f.global_position.y, f.global_position.z), 200.0)])
	# one Nieuport gets through: it attacks for PURSUIT_TIME, then breaks off for home
	var flat := Vector3(p.flight_basis.z.x, 0.0, p.flight_basis.z.z).normalized()
	if pursuer and pursuer.hidden:
		var at := p.global_position - flat * 450.0 + Vector3.UP * 60.0
		reveal(pursuer, at, [goal(Aircraft.G_RETALIATE_ON, 0, Vector3.ZERO, PURSUIT_TIME),
			goal(Aircraft.G_ATTACK, p.object_id),
			goal(Aircraft.G_WAYPOINT, 0, Vector3(BRITISH_EDGE_X, at.y, at.z), 200.0)], p.global_position - at)


func step(dt: float) -> void:
	var p := world.player
	if not alive(p):
		return
	if wounded:
		p.throttle = minf(p.throttle, THROTTLE_CAP)
		p.fire_input = false
		p.secondary_input = false
		_escort(dt)
		if p.state == Aircraft.State.GROUND and near(p, AERODROME, HOME_RANGE, true):
			win()


## Brenner holds formation on the wounded Baron; BRENNER_DELAY after the wound he goes for the
## Nieuport while it is near the Baron, then forms up again.
func _escort(dt: float) -> void:
	_escort_check -= dt
	if brenner == null or not alive(brenner) or _escort_check > 0.0:
		return
	_escort_check = 1.0
	var p := world.player
	var g := brenner.current_goal()
	var threat := pursuer if pursuer and pursuer.present() and near(pursuer, p, 900.0) \
		and now() >= wound_time + BRENNER_DELAY else null
	if threat:
		if int(g.get("type", 0)) != Aircraft.G_ATTACK or int(g.get("targetid", 0)) != threat.object_id:
			attack(brenner, threat)
	elif int(g.get("type", 0)) != Aircraft.G_FORMATION:
		formation(brenner, p, Vector3(-30.0, 0.0, -30.0))
