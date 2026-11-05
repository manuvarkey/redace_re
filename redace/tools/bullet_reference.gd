extends World
## Test/benchmark oracle: bullet methods frozen from 4bb147d. Never used by the game.


func _bullet_hits(b: Dictionary, from: Vector3, to: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	if not b.aa and _bullet_hits_scenery(b, from, to, space):
		return true
	for p in planes:
		if p.proximity_groups == 0 or is_same(p, b.owner) or not p.present():
			continue
		if p.global_position.distance_squared_to(to) < p.hit_radius_sq:
			for k in p.proximity_groups:
				p.take_damage(b.damage, b.owner)
	return false


func _bullet_hits_scenery(b: Dictionary, from: Vector3, to: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	for t in _targets_near(to):
		var inv: Transform3D = t.node.global_transform.affine_inverse()
		var a: Vector3 = inv * from
		var c: Vector3 = inv * to
		if segment_hits_box(a, c, t.aabb.position, t.aabb.end) and _segment_hits_faces(t, a, c):
			if not t.dead:
				_last_damage_source = "bullet from " + (b.owner.plane_name if b.owner is Aircraft else "gun")
				_damage_target(t, b.damage)
			particles.puff("hit", to - b.vel * 0.02, Vector3.ZERO, 4.0, Color(1, 1, 1, 0.5), Color(0, 0, 0, -1.0), 4.0)
			return true
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return false
	# bullet in the ground: maroon dust puff 8 above the impact (FUN_0044cd2a)
	particles.puff("maroon", hit.position + Vector3.UP * 8.0, Vector3(0, 4, 0), 4.0, Color(1, 1, 1, 0.5),
		Color(0, 0, 0, -0.8), 6.0)
	# BulletGround1 (the exe gives it 4 voices); here at most 8 per second
	if mission_time - _bullet_sound_time > 0.125:
		_bullet_sound_time = mission_time
		play_at(hit.position, _bullet_ground_sound)
	return true


func _draw_bullets() -> void:
	_bullets_mesh.clear_surfaces()
	if bullets.is_empty() or camera == null:
		return
	var eye := camera.global_position
	var col := Color(1, 1, 1, 0xc4 / 255.0)
	_bullets_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in bullets:
		var p: Vector3 = b.pos
		var d: Vector3 = (b.vel as Vector3).normalized()
		var tip := p + d * BULLET_STREAK
		var side := (eye - p).cross(d)
		if side.length_squared() < 1e-8:
			continue
		side = side.normalized() * (0.5 if b.aa else 0.3)
		var q := [p + side, tip + side, tip - side, p - side]
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for k in [0, 1, 2, 0, 2, 3]:
			_bullets_mesh.surface_set_color(col)
			_bullets_mesh.surface_set_uv(uv[k])
			_bullets_mesh.surface_add_vertex(q[k])
	_bullets_mesh.surface_end()


func _update_bullets(dt: float, space: PhysicsDirectSpaceState3D) -> void:
	var i := bullets.size() - 1
	while i >= 0:
		var b: Dictionary = bullets[i]
		var from: Vector3 = b.pos
		var to: Vector3 = from + b.vel * dt
		b.life -= dt
		if b.life <= 0.0 or not in_bounds(to, 0.0) or _bullet_hits(b, from, to, space):
			bullets[i] = bullets[bullets.size() - 1]
			bullets.pop_back()
		else:
			b.pos = to
		i -= 1
