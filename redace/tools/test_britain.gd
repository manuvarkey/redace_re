extends SceneTree

var world: World
var ticks := 0

func _initialize() -> void:
	world = World.new()
	world.standalone = false
	root.add_child.call_deferred(world)
	_start.call_deferred()

func _start() -> void:
	world.load_mission(26)

func _physics_process(_dt: float) -> bool:
	ticks += 1
	if ticks != 5:
		return false
	assert(world.player.plane_name == "spitfire")
	assert(world.planes.size() == 22)
	assert(world.player.get_script() == load("res://mods/britain/aircraft.gd"))
	for p in world.planes:
		if p.plane_name == "bf109":
			assert(p.get("escort_leader_id") == p.object_id - 3)
		if p.plane_name == "he111":
			assert(str(p.get("radar_icon")).ends_with("smallbomber.png"))
	for t in world.targets:
		if t.name.begins_with("britain"):
			assert(t.models.size() == 4, "Every new damageable asset needs two damaged stages and a wreck")
	assert(not world.is_sea(Vector3(2720, 8, 1700)), "Quays must not cause sea crashes")
	assert(world.is_sea(Vector3(5000, 0, 2300)))
	assert(world._aabb_of(world.player._model).size.x >= 21.0, "Spitfire must match the original aircraft screen scale")
	assert(world.player.dive_speed > world.player.high_speed)
	assert(world.player.high_speed > world.player.cruise_speed)
	assert(is_equal_approx(world.planes[4].endurance, world.planes[7].endurance * 1.5),
		"Mission bombers must have 50 percent more endurance than escort fighters")
	assert(world.objects_by_id[100].groups & (1 << Hud.GROUP_TARGET), "Factory must use the original target icon")
	assert(not world.objects_by_id[100].groups & (1 << Hud.GROUP_AA))
	assert(absf(world.ground_height(Vector3(5200, 100, 2300))) < 1.0, "Raid approach must be over water")
	assert(world.ground_height(Vector3(1800, 200, 3300)) > 40, "Factory must occupy the inland valley")
	assert(world.map_bounds.size.x >= 6000)
	assert(world.rules.filter(func(r): return r.group == 9)[0].total == 18)
	assert(world.rules.filter(func(r): return r.group == 9)[0].lost == 0, "Hidden future raids must remain alive")
	assert(not world.mission_over)
	assert(world.planes[4].hidden)
	# Exercise the actual wait/appear script for each scheduled raid.
	for wave in range(3):
		var p: Aircraft = world.planes[4 + wave * 6]
		p._script_goal(p.current_goal(), 12.0 + wave * 85.0 + 0.1)
		assert(p.present(), "Raid must appear after its wait")
		assert(p.state == Aircraft.State.FLYING)
	for i in range(4, 10):
		world.planes[i].state = Aircraft.State.DEAD
	world._count_rule_members()
	world._check_rules()
	assert(not world.mission_over, "Destroying the first raid must not skip future raids")
	for p in world.planes:
		if not p.allied:
			p.state = Aircraft.State.DEAD
	world._count_rule_members()
	world._check_rules()
	assert(world.mission_over, "All three raids destroyed must win")
	assert(world._end_result == "won")
	world.mission_over = false
	world.objects_by_id[100].dead = true
	world._count_rule_members()
	world._check_rules()
	assert(world.mission_over, "Factory loss must override victory")
	assert(world._end_result == "defence")
	print("BRITAIN PASS: assets, squadron, hidden raids, timed arrivals, victory and factory defeat")
	world.load_mission(-3)
	assert(world.player.get_script() == load("res://scripts/aircraft.gd"), "Stock missions must use the original aircraft class")
	assert(not world.is_sea(Vector3(5000, 0, 2300)))
	assert(world._mod == null)
	print("STOCK ISOLATION PASS: default aircraft, no Britain sea/environment")
	quit()
	return false
