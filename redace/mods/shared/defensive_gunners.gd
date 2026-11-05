extends RefCounted
## Defensive gunners for mod aircraft (not in the original: its AI only fires inside an attack goal).
## Shared by mods; first written for the Battle of Britain He 111 and moved here unchanged.
## One instance per aircraft. update() fires one round of the existing bullet ordnance (kind 1) at the
## nearest present enemy inside range, at most once per interval, from the tail (rear sector) or the
## dorsal position (upper sector). Forward, low and wing-level broadside sectors are masked by the airframe.
## Rounds are withheld when terrain or a present friendly aircraft is in the line of fire.

var max_range := 450.0
var interval := 0.2  # seconds between rounds: five rounds per second
var cooldown := 0.0


func _init(range_ := 450.0, interval_ := 0.2) -> void:
	max_range = range_
	interval = interval_


## Counts the cooldown down and fires when a shot is available. Returns true when a round was fired.
func update(plane: Aircraft, dt: float) -> bool:
	cooldown = maxf(0.0, cooldown - dt)
	if plane.state == Aircraft.State.GROUND or cooldown > 0.0:
		return false
	var shot := shot_for(plane, max_range)
	if shot.is_empty():
		return false
	plane.world.spawn_ordnance(plane, 1, shot.origin, plane.velocity, shot.direction)
	cooldown = interval
	return true


## The best shot for plane's gunners: {origin, direction}, or {} when no enemy can be engaged.
static func shot_for(plane: Aircraft, max_range: float) -> Dictionary:
	var world := plane.world
	var best := {}
	var closest := max_range * max_range
	var frame := plane.global_transform.basis.orthonormalized()
	var bullet_speed := Ini.num(world.ordnance.get(1, {}), "releasespeed", 250.0)
	for enemy in world.planes:
		if enemy == plane or enemy.allied == plane.allied or not enemy.present():
			continue
		var to := enemy.global_position - plane.global_position
		var distance := to.length_squared()
		if distance < 30.0 * 30.0 or distance > closest:
			continue
		var aim := to + (enemy.velocity - plane.velocity) * (sqrt(distance) / maxf(bullet_speed, 1.0))
		var local := frame.inverse() * aim.normalized()
		var origin: Vector3
		if local.z < -0.65 and local.y > -0.15 and local.y < 0.7:
			origin = plane.global_position - frame.z * (plane.back_length + 1.0) + frame.y * plane.up_length
		elif local.y > 0.35 and local.z < 0.35:
			origin = plane.global_position + frame.y * (plane.up_length + 1.0)
		else:
			continue  # Forward, low and wing-level broadside sectors are masked by the airframe.
		var end := plane.global_position + aim
		if world.ground_hit_fraction(origin, end) > 0.0:
			continue
		var safe := true
		for friend in world.planes:
			if friend == plane or friend.allied != plane.allied or not friend.present():
				continue
			var near := Geometry3D.get_closest_point_to_segment(friend.global_position, origin, end)
			if near.distance_to(friend.global_position) < friend.radius + 3.0:
				safe = false
				break
		if safe:
			closest = distance
			best = {"origin": origin, "direction": (end - origin).normalized()}
	return best
