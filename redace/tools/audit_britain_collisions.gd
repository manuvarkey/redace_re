extends SceneTree
## Seeded 90-second diagnostic with AI player and mission ending disabled.
## godot --headless --path redace --log-file /tmp/britain-loss-audit.log -s tools/audit_britain_collisions.gd
class AuditWorld extends World:
	var phase := "update"
	func _check_rules() -> void:
		pass
	func _on_plane_destroyed(_p: Aircraft) -> void:
		pass
	func collide(p: Aircraft, prev: Vector3, dt: float) -> void:
		phase = "object contact"
		super.collide(p, prev, dt)
		phase = "update"
var w: AuditWorld
var bullet_losses := 0
var contact_losses := 0
var other_losses := 0
func _initialize() -> void:
	start.call_deferred()
func start() -> void:
	seed(12345)
	w = AuditWorld.new()
	w.standalone = false
	root.add_child(w)
	w.load_mission(26)
	await physics_frame
	await physics_frame
	w.autopilot = true
	w.player.autopilot = true
	w.set_physics_process(false)
	w.set_process(false)
	for p in w.planes:
		p.set_physics_process(false)
		p.set_process(false)
		p.destroyed.connect(record_loss)
	for tick in 5400:
		w.phase = "bullets"
		w._physics_process(1.0 / 60.0)
		w.phase = "update"
		for p in w.planes:
			p._physics_process(1.0 / 60.0)
		if tick % 1000 == 0:
			print("AUDIT t=",w.mission_time)
	print("AUDIT COMPLETE: bullets=%d contacts=%d other=%d" % [bullet_losses, contact_losses, other_losses])
	w.free()
	World._scene_cache.clear()
	quit()

func record_loss(a: Aircraft) -> void:
	match w.phase:
		"bullets": bullet_losses += 1
		"object contact": contact_losses += 1  # Integrated object AND terrain pass.
		_: other_losses += 1
	print("AUDIT LOSS t=%.2f id=%d %s phase=%s crashed=%s pos=%s clearance=%.1f" % [
		w.mission_time, a.object_id, a.plane_name, w.phase, a.crashed,
		a.global_position, w.height_above_ground(a.global_position)])
