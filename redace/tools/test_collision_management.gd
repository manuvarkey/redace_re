extends SceneTree
## Source oracle: FUN_00431607 / FUN_00430199 and 0x4343c9 matrix rotation.
## godot --headless --path redace -s tools/test_collision_management.gd
class TestWorld extends World:
	var events: Array[String] = []
	var contacts := {}
	var query := 0
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		particles = Particles.new()
	func _exit_tree() -> void:
		particles.free()
	func ground_contact(_from: Vector3, _to: Vector3) -> Dictionary:
		events.append("terrain%d" % query)
		var result: Dictionary = contacts.get(query, {})
		query += 1
		return result
	func _collide_segment(_p: Aircraft, _a: Vector3, _b: Vector3, _dt: float, _candidates: Variant = null) -> void:
		events.append("object%d" % (query - 1))
	func play_at(_pos: Vector3, _stream: AudioStream, _volume_db := 0.0) -> void:
		pass
	func flash(_node: Node3D, _seconds := 0.25) -> void:
		pass
	func real_segment(p: Aircraft, a: Vector3, b: Vector3, dt: float) -> void:
		super._collide_segment(p, a, b, dt)

class PhysicsWorld extends World:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		particles = Particles.new()
	func _exit_tree() -> void:
		particles.free()
	func play_at(_pos: Vector3, _stream: AudioStream, _volume_db := 0.0) -> void:
		pass

class TestPlane extends Aircraft:
	var deaths := 0
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		destroyed.connect(func(_p): deaths += 1)
	func on_hit(_attacker) -> void:
		pass

var failures := 0
var checks := 0
var world: TestWorld
var p: TestPlane
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func fresh() -> void:
	if world:
		world.free()
	world = TestWorld.new()
	root.add_child(world)
	p = TestPlane.new()
	p.world = world
	world.add_child(p)
	world.planes.append(p)
	p.state = Aircraft.State.FLYING
	p.position = Vector3(1, 2, 0)
	p.down_length = 2
	p.speed = 50
	p.high_speed = 100
	p.endurance = 100
	p.health = 100
func model(parent: Node3D, count: int) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		node.add_child(mi)
	return node
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	fresh()
	world.contacts[0] = {"position": Vector3.ZERO, "normal": Vector3.UP}
	world.collide(p, Vector3(0, 2, 0), 0.01)
	check(world.events == ["terrain0"] and p.crashed, "nose terrain hit gates all object and later probe queries")
	check(p.deaths == 1, "nose crash counts one loss")
	fresh()
	world.contacts[1] = {"position": Vector3.ZERO, "normal": Vector3.UP}
	world.collide(p, Vector3(0, 2, 0), 0.01)
	check(world.events == ["terrain0", "object0", "terrain1"] and p.crashed, "upper terrain hit gates upper objects and later queries")
	fresh()
	world.contacts[2] = {"position": Vector3(1, 0, 0), "normal": Vector3.UP}
	world.collide(p, Vector3(0, 2.05, 0), 0.01)
	check(p.state == Aircraft.State.GROUND and is_equal_approx(p.position.y, 2.05), "gentle lower contact lands at contact plus normal offset")
	check(world.events.size() == 12 and world.events[5] == "object2", "lower objects run before response, remaining probes still run after landing")
	fresh()
	p.position.y = 1.94  # lower endpoint -0.06; dt .01 => -6 units/s, irrespective of velocity
	p.velocity = Vector3.ZERO
	world.contacts[2] = {"position": Vector3(1, 0, 0), "normal": Vector3.UP}
	world.collide(p, Vector3(0, 2.05, 0), 0.01)
	check(p.state == Aircraft.State.FLYING and is_equal_approx(p.position.y, 2.11), "moderate contact reflects displacement, not centre velocity")
	check(p.flight_basis.z.is_equal_approx(Vector3.UP), "bounce steers toward reflected direction")
	fresh()
	p.position.y = 1.89
	world.contacts[2] = {"position": Vector3(1, 0, 0), "normal": Vector3.UP}
	world.collide(p, Vector3(0, 2.05, 0), 0.01)
	check(p.crashed and world.events.size() == 6, "hard lower contact crashes after its objects and stops remaining probes")
	fresh()
	p.state = Aircraft.State.GROUND
	world.collide(p, Vector3(0, 2, 0), 0.01)
	check(world.query == 5 and world.events.size() == 10, "taxiing still tests nose, upper, tail and both wings")
	fresh()
	world.contacts[4] = {"position": Vector3.ZERO, "normal": Vector3.UP}
	world.contacts[5] = {"position": Vector3.ZERO, "normal": Vector3.UP}
	world.collide(p, Vector3(0, 2, 0), 0.01)
	check(p.falling and p.deaths == 1 and p.health == 98, "each wing adds one damage; duplicate loss signal is suppressed")
	check(world.events.back() == "object5", "wing contact still queries object geometry after falling begins")
	fresh()
	var normal := Vector3(0, 1, 1).normalized()
	var contact := Vector3(0, 4, 0)
	check(p.resolve_ground_contact({"position": contact, "normal": normal}, contact - normal * 0.02, 0.01), "gentle sloped contact resolves")
	check(p.position.is_equal_approx(contact + normal * 2.05), "slope offset follows hit triangle normal")

	# Every mesh corresponds to an atomic; two face crossings in one box count once.
	fresh()
	p.position = Vector3.ZERO
	p._model = model(p, 1)
	check(p.collision_hit_count(Vector3(-2, 0, 0), Vector3(2, 0, 0)) == 1, "front/back triangles of one atomic yield one callback")
	p._model = model(p, 2)
	check(p.collision_hit_count(Vector3(-2, 0, 0), Vector3(2, 0, 0)) == 2, "two intersected atomics yield two callbacks")
	p._model.position.y = 10
	check(p.collision_hit_count(Vector3(-2, 0, 0), Vector3(2, 0, 0)) == 0, "cached parts follow live model transforms")
	p._model = model(p, 1)
	check(p.collision_hit_count(Vector3(-2, 0, 0), Vector3(2, 0, 0)) == 1, "damage-model replacement refreshes atomic geometry")

	p._model = model(p, 1)
	var moving_part: MeshInstance3D = p._model.get_child(0)
	var long_box := BoxMesh.new()
	long_box.size = Vector3(2, 10, 2)
	moving_part.mesh = long_box
	moving_part.position = Vector3(5, 0, 0)
	check(p.collision_hit_count(Vector3(9, 0, -2), Vector3(9, 0, 2)) == 0, "unrotated child misses outside its narrow side")
	moving_part.rotation.z = PI / 2
	check(p.collision_hit_count(Vector3(9, 0, -2), Vector3(9, 0, 2)) == 1, "broad phase encloses rotating child across cached pivot bounds")

	# A dead soft object still wears down a plane, and a solid wreck still kills it.
	fresh()
	p.position = Vector3.ZERO
	var tree := model(world, 2)
	var t := {"node": tree, "model_index": 0, "dead": true, "soft": true, "endurance": 7.0, "name": "tree"}
	world.targets.append(t)
	world.real_segment(p, Vector3(-300, 0, 0), Vector3(300, 0, 0), 0.01)
	check(is_equal_approx(p.health, 95.8), "destroyed soft object applies 2.1 per atomic along full long segment")
	t.soft = false
	world.real_segment(p, Vector3(-300, 0, 0), Vector3(300, 0, 0), 0.01)
	check(p.deaths == 1 and p.falling, "solid wreck collision kills once across multiple atomics")
	fresh()
	p.position = Vector3.ZERO
	var wing_obstacle := model(world, 1)
	wing_obstacle.position = Vector3(0, 8, 0)
	world.targets.append({"node": wing_obstacle, "model_index": 0, "dead": true, "soft": true, "endurance": 7.0, "name": "tree"})
	var nearby := world._collision_candidates(p, Vector3.ZERO, Vector3.ZERO, 9.0)
	check(nearby.size() == 1, "candidate envelope includes objects reached only by an offset wing probe")
	world.real_segment(p, Vector3.ZERO, Vector3(0, 9, 0), 0.01)
	check(is_equal_approx(p.health, 97.9), "wing-only obstacle reaches narrow phase")

	# Unequal aircraft endurances: each receives damage scaled by the OTHER plane.
	fresh()
	p.position = Vector3.ZERO
	var q := TestPlane.new()
	q.world = world
	world.add_child(q)
	q.endurance = 200
	q.health = 200
	q.state = Aircraft.State.FLYING
	q._model = model(q, 1)
	world.planes.append(q)
	world.real_segment(p, Vector3(-2, 0, 0), Vector3(2, 0, 0), 0.01)
	check(is_equal_approx(p.health, 99.2) and is_equal_approx(q.health, 199.6), "aircraft constructors' soft flag gives fractional damage both ways")
	await real_terrain()
	world.free()
	print("Collision management: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func body(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var solid := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	solid.add_child(collision)
	parent.add_child(solid)
	solid.position = pos


func real_terrain() -> void:
	var terrain := PhysicsWorld.new()
	root.add_child(terrain)
	body(terrain, Vector3(100, 2, 100), Vector3(0, -1, 0))
	var aircraft := TestPlane.new()
	aircraft.world = terrain
	terrain.add_child(aircraft)
	aircraft.state = Aircraft.State.FLYING
	aircraft.down_length = 2
	aircraft.front_length = 0
	aircraft.position = Vector3(0, 1.98, 0)
	aircraft.speed = 50
	aircraft.high_speed = 100
	await physics_frame
	await physics_frame
	var contact := terrain.ground_contact(Vector3(0, 0.05, 0), Vector3(0, -0.02, 0))
	check(not contact.is_empty() and contact.normal.is_equal_approx(Vector3.UP), "real physics query returns lower contact and triangle normal")
	terrain.collide(aircraft, Vector3(0, 2.05, 0), 0.01)
	check(aircraft.state == Aircraft.State.GROUND and is_equal_approx(aircraft.position.y, 2.05), "real swept underside lands on terrain")
	body(terrain, Vector3(10, 10, 20), Vector3(6, 0, 0))
	await physics_frame
	await physics_frame
	aircraft.state = Aircraft.State.FLYING
	aircraft.position = Vector3(0, 2.05, 0)
	aircraft.flight_basis = Basis(Vector3.UP, PI / 2)
	aircraft.basis = aircraft.flight_basis
	aircraft.speed = 10
	aircraft.high_speed = 10
	aircraft.cruise_speed = 10
	aircraft.stall_speed = 0
	aircraft.mass = 0
	aircraft.throttle = 1
	aircraft.front_length = 2
	var prev := aircraft.position
	aircraft._fly(0.2)
	check(is_equal_approx(aircraft.position.y, 2.05), "flight step does not teleport up a cliff using endpoint ground height")
	terrain.collide(aircraft, prev, 0.2)
	check(aircraft.crashed and aircraft.deaths == 1, "real vertical cliff contact crashes before later probes")
	terrain.free()
