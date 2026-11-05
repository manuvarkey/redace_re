extends SceneTree
## Verify that quality settings alter rendering only, including live switches and damaged models.
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var w := World.new()
	w.standalone = false
	root.add_child(w)
	w.load_mission(26)
	w.set_process(false)
	w.set_physics_process(false)
	var environment = w._mod.environment
	var water_mesh = environment.get_node("SeaSurface")
	var sea_shape = environment.get_node("SeaCollision").get_child(0)
	var mesh_id: RID = water_mesh.mesh.get_rid()
	var shape_id: RID = sea_shape.shape.get_rid()
	var water_standard: String = environment._water_material_ref.shader.code
	var cloud_standard: String = environment._sky_material_ref.shader.code
	var aircraft_state := []
	for p in w.planes:
		p.set_process(false)
		p.set_physics_process(false)
		aircraft_state.append([p.global_transform, p.health, p.state, p.velocity])
	var first: Dictionary = w.targets[0]
	var faces: AABB = first.aabb
	w.apply_graphics_quality(0, 0, 0)
	check(environment._water_material_ref.shader.code.count("noise2(fine") == 0, "Low water removes four fine-noise evaluations")
	check(water_standard.count("noise2(fine") == 4, "Standard water retains fine ripple normals")
	check(environment._sky_material_ref.shader.code.contains("float wisps = 0.5;"), "Low clouds omit fine wisps")
	check(environment._sky_material_ref.shader.code.contains("+ 0.085;"), "Low clouds preserve mean cover while dropping highest octave")
	check(water_mesh.mesh.get_rid() == mesh_id and sea_shape.shape.get_rid() == shape_id, "quality does not rebuild or alter sea geometry/collision")
	for t in w.targets:
		for mesh in t.node.find_children("*", "MeshInstance3D", true, false):
			check(is_equal_approx(mesh.lod_bias, 0.5), "Low scenery applies GPU LOD bias")
	for i in w.planes.size():
		var p: Aircraft = w.planes[i]
		check([p.global_transform, p.health, p.state, p.velocity] == aircraft_state[i], "quality preserves aircraft state")
		for mesh in p._model.find_children("*", "MeshInstance3D", true, false):
			check(is_equal_approx(mesh.lod_bias, 1.0), "aircraft visual detail remains unchanged")
	check(first.aabb == faces, "scenery collision bounds unchanged")
	w._damage_target(first, first.endurance * 0.8)
	for mesh in first.node.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_queued_for_deletion() and not mesh.get_parent().is_queued_for_deletion():
			check(is_equal_approx(mesh.lod_bias, 0.5), "replacement damage model inherits scenery detail")
	w.apply_graphics_quality(1, 1, 1)
	check(environment._water_material_ref.shader.code == water_standard, "Standard restores original water shader exactly")
	check(environment._sky_material_ref.shader.code == cloud_standard, "Standard restores original cloud shader exactly")
	w.load_mission(-3)
	w.apply_graphics_quality(0, 0, 0)
	check(w._mod == null, "stock missions support scenery detail without Britain shaders")
	w.free()
	World._scene_cache.clear()
	print("Environment quality: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
