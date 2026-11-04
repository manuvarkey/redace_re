extends SceneTree
## godot --headless --path redace -s tools/test_probe_detection.gd
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func segment(sg: Array, a: Vector3, b: Vector3, message: String) -> void:
	check(sg[0].is_equal_approx(a) and sg[1].is_equal_approx(b), message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var p := Aircraft.new()
	root.add_child(p)
	p.set_process(false)
	p.set_physics_process(false)
	p.state = Aircraft.State.FLYING
	p.front_length = 7
	p.down_length = 2
	p.back_length = 8
	p.port_length = 9
	p._probe_previous_basis = Basis(Vector3.UP, PI / 2)
	p.flight_basis = Basis(Vector3.RIGHT, PI / 2)
	p.global_transform = Transform3D(Basis(Vector3.BACK, PI / 2), Vector3(10, 20, 30))
	var prev := Vector3(1, 2, 3)
	var probes := p.probe_segments(prev)
	check(probes.size() == 6, "six airborne probes")
	segment(probes[0], prev, Vector3(8, 2, 3), "nose uses previous position and forward")
	segment(probes[1], prev, Vector3(8, 20, 30), "top uses banked render up and downlength")
	segment(probes[2], Vector3(1, 0, 3), Vector3(10, 20, 28), "bottom uses previous/current unbanked up")
	segment(probes[3], Vector3(1, -6, 3), Vector3(10, 20, 22), "fourth probe uses unbanked up and backlength")
	segment(probes[4], prev, Vector3(10, 11, 30), "negative wing uses banked render frame")
	segment(probes[5], prev, Vector3(10, 29, 30), "positive wing uses banked render frame")
	p.state = Aircraft.State.GROUND
	check(p.probe_segments(prev).size() == 5, "ground state omits underside sweep")

	# A transformed model must replace all INI lengths, including asymmetric extents.
	var model := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8, 6, 10)
	mesh.mesh = box
	mesh.position = Vector3(1, 1, 2)
	model.add_child(mesh)
	p.add_child(model)
	p.plane_name = "probe_regression"
	p._lengths_from_model(model)
	check(is_equal_approx(p.front_length, 7) and is_equal_approx(p.back_length, 3), "front/back from model")
	check(is_equal_approx(p.port_length, 3) and is_equal_approx(p.starboard_length, 5), "asymmetric lateral model bounds")
	check(is_equal_approx(p.up_length, 4) and is_equal_approx(p.down_length, 2), "vertical model bounds")

	# A lower sweep hits a triangle that a centre-to-end diagonal misses.
	var target := Aircraft.new()
	root.add_child(target)
	target.set_process(false)
	target.set_physics_process(false)
	target._faces = PackedVector3Array([Vector3(1, -3.2, -0.2), Vector3(1, -2.8, -0.2), Vector3(1, -3, 0.2)])
	check(target.box_hit(Vector3(0, -3, 0), Vector3(2, -3, 0)), "offset sweep detects real triangle contact")
	check(not target.box_hit(Vector3.ZERO, Vector3(2, -3, 0)), "old centre diagonal misses that contact")
	# Configured/default collision lengths must not clip a real triangle outside the old box.
	target._faces = PackedVector3Array([Vector3(20, -1, -1), Vector3(20, 1, -1), Vector3(20, 0, 1)])
	check(target.box_hit(Vector3(19, 0, 0), Vector3(21, 0, 0)), "target broad phase encloses actual mesh")
	target.free()
	p.free()
	print("Probe detection regression: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)
