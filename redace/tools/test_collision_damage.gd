extends SceneTree
## godot --headless --path redace -s tools/test_collision_damage.gd

class TestWorld extends World:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		particles = Particles.new()

	func _exit_tree() -> void:
		particles.free()

	func play_at(_pos: Vector3, _stream: AudioStream, _volume_db := 0.0) -> void:
		pass

	func ground_contact(_a: Vector3, _b: Vector3) -> Dictionary:
		return {}

	func flash(_node: Node3D, _seconds := 0.25) -> void:
		pass

class TestPlane extends Aircraft:
	var deaths := 0
	var hits := 0
	var moves := 0
	var contacts := 1

	func _ready() -> void:
		set_physics_process(false)
		set_process(false)
		destroyed.connect(func(_plane): deaths += 1)

	func collision_hit_count(_a: Vector3, _b: Vector3) -> int:
		hits += 1
		return contacts

	func on_hit(_attacker) -> void:
		pass

	func _fly(_dt: float) -> void:
		moves += 1

	func _ai(_dt: float) -> void:
		pass

	func _apply_ai_commands() -> void:
		pass

	func _terrain_probes(_prev: Vector3) -> void:
		pass

	func _damage_smoke(_dt: float) -> void:
		pass

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func plane(world: TestWorld) -> TestPlane:
	var p := TestPlane.new()
	p.world = world
	p.endurance = 100.0
	p.health = 100.0
	p.state = Aircraft.State.FLYING
	p._first_frame = false
	world.add_child(p)
	world.planes.append(p)
	return p

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	var a := plane(world)
	var b := plane(world)
	var c := plane(world)
	var hidden_plane := plane(world)
	hidden_plane.hidden = true
	# Original flags 0x401/0x601: two callback contacts cause 0.4 each way, not death.
	for i in 2:
		world._collide_segment(a, Vector3.ZERO, Vector3.RIGHT, 0.01)
	check(a.deaths == 0 and is_equal_approx(a.health, 98.4), "prober takes fractional damage from both targets")
	check(is_equal_approx(b.health, 99.2), "both probes damage the target by 0.4 each")
	check(is_equal_approx(c.health, 99.2), "contacts continue beyond first aircraft")
	check(hidden_plane.hits == 0, "hidden aircraft are excluded")
	# B's probes still contact a falling A, but receive fractional damage.
	a.take_damage(101.0)
	world.planes.erase(c)
	b._physics_process(0.01)
	check(b.deaths == 0 and b.health < 99.2, "contact with falling aircraft damages second prober gradually")
	check(a.deaths == 1, "hits on falling target do not emit destruction again")
	var hits_before := b.hits
	a._physics_process(0.01)
	check(a.moves == 1 and b.hits > hits_before, "falling aircraft still moves and probes objects")
	check(a.deaths == 1 and b.deaths == 0, "falling collisions do not repeat death effects")
	a.falling = false
	hits_before = b.hits
	a._physics_process(0.01)
	check(a.moves == 1 and b.hits == hits_before, "crashed aircraft no longer probes")
	world.free()
	await extra_modes()
	print("Collision damage regression: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)

func extra_modes() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	world.collision_damage = World.CollisionDamage.MILD
	var a := plane(world)
	var b := plane(world)
	b.endurance = 200.0
	b.health = 200.0
	b.contacts = 3
	world.collide(a, Vector3.ZERO, 0.01)
	world.collide(b, Vector3.ZERO, 0.01)
	check(is_equal_approx(a.health, 50.0) and is_equal_approx(b.health, 100.0),
		"Mild removes half of each plane's own endurance once across all probes and both directions")
	await physics_frame
	world.collide(a, Vector3.ZERO, 0.01)
	check(a.deaths == 0 and b.deaths == 0, "continuous contact does not repeat Mild damage")
	await physics_frame
	await physics_frame
	world.collide(b, Vector3.ZERO, 0.01)
	check(a.deaths == 1 and b.deaths == 1, "another impact after separation applies Mild damage again")
	world.free()
	world = TestWorld.new()
	root.add_child(world)
	world.collision_damage = World.CollisionDamage.FULL
	a = plane(world)
	b = plane(world)
	b.endurance = 200.0
	b.health = 200.0
	world.collide(a, Vector3.ZERO, 0.01)
	world.collide(b, Vector3.ZERO, 0.01)
	check(a.deaths == 1 and b.deaths == 1, "Full kills both planes, once, regardless of endurance")
	world.free()
