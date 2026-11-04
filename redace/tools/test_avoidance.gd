extends SceneTree
## godot --headless --path redace -s tools/test_avoidance.gd
class TestWorld extends World:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var w := TestWorld.new()
	root.add_child(w)
	var me := Aircraft.new()
	var other := Aircraft.new()
	for p in [me, other]:
		w.add_child(p)
		p.world = w
		p.set_process(false)
		p.set_physics_process(false)
		p.state = Aircraft.State.FLYING
		w.planes.append(p)
	other.groups = 1 << 8
	other.starboard_length = 5
	other.back_length = 8
	other.radius = 100  # A broad-phase sphere must not control the avoidance distance.
	other.position = Vector3(11, 0, 0)
	me._avoid_collision()
	check(me.current_goal().is_empty(), "outside original extent-based threshold does not evade")
	other.position.x = 10
	me._avoid_collision()
	check(me.current_goal().is_empty(), "strict squared-distance threshold excludes equality")
	other.position.x = 9
	# Separate flight frames from visual frames to catch the banked-vector regression.
	me.basis = Basis(Vector3.BACK, PI / 2)
	other.basis = Basis(Vector3.RIGHT, PI / 6)
	me._avoid_collision()
	var goal := me.current_goal()
	check(int(goal.get("type", 0)) == Aircraft.G_EVADE, "nearby group 8 aircraft triggers evade")
	var expected := Vector3(-50, 0, 0)  # Both unbanked frames are identity.
	check(goal.get("pos", Vector3.INF).is_equal_approx(expected), "sidestep ignores visual bank and uses unbanked frames")
	check(is_equal_approx(float(goal.get("radius", 0)), 1.5), "original 1.5 second evade duration")
	me._avoid_collision()
	check(me.goals.size() == 1, "active evade does not enqueue another evade")
	me.goals.clear()
	other.groups = 1 << 9
	me._avoid_collision()
	check(me.current_goal().is_empty(), "other groups do not trigger this original avoidance routine")
	me.basis = Basis.IDENTITY
	me.ahead_alt = 120
	me._ai_pitch = 7
	me._avoid_terrain()
	check(me._ai_pitch == 7, "terrain threshold is strict")
	me.ahead_alt = 119
	me._avoid_terrain()
	check(me._ai_pitch == 20, "upright low-altitude pull-up matches original")
	me.basis = Basis(Vector3.BACK, PI)
	me._avoid_terrain()
	check(me._ai_pitch == 20, "visual bank alone does not invert terrain avoidance")
	me.flight_basis = Basis(Vector3.BACK, PI)
	me._avoid_terrain()
	check(me._ai_pitch == -20, "inverted control frame reverses pull-up")
	w.free()
	print("Avoidance regression: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)
