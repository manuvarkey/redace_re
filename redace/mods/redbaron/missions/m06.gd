extends "res://mods/redbaron/missions/objective.gd"
## Mission 6, Balloon Busting: the original rules plus objective.gd (intro, counter, target icons).
## Three Halberstadt CL.IIs bomb the AA guns. After a pass the original bombing AI pushes a go-round
## waypoint with a 40 radius that a wide-turning two-seater can circle for ever; a CL that has been on a
## waypoint for STUCK_AFTER s with bombs left is put back on a bombing run at the nearest gun.

const CL := [3030, 3031, 3032]
const STUCK_AFTER := 10.0

var _on_waypoint := {}  # plane -> seconds on a waypoint goal


func step(dt: float) -> void:
	super.step(dt)
	for id in CL:
		var p := plane(id)
		if p == null or not alive(p) or p.ordnance_left <= 0:
			continue
		if int(p.current_goal().get("type", 0)) == Aircraft.G_WAYPOINT:
			_on_waypoint[p] = _on_waypoint.get(p, 0.0) + dt
			if _on_waypoint[p] > STUCK_AFTER:
				_on_waypoint[p] = 0.0
				set_goals(p, [goal(Aircraft.G_BOMB_RUN, -6)])
		else:
			_on_waypoint[p] = 0.0
