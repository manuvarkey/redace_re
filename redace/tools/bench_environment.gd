extends SceneTree
## Fixed-camera GPU timings in Compatibility. Run graphically; no AI or physics work.
var w: World
func _initialize() -> void:
	run.call_deferred()
func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("GPU benchmark requires a graphical display")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1280, 720)
	root.scaling_3d_scale = 1.0
	root.msaa_3d = Viewport.MSAA_DISABLED
	w = World.new()
	w.standalone = false
	w.view_distance = 1800.0
	root.add_child(w)
	w.load_mission(26)
	w.set_process(false)
	w.set_physics_process(false)
	for p in w.planes:
		p.set_process(false)
		p.set_physics_process(false)
	w.particles.set_process(false)
	for child in w.get_children():
		if child is CanvasLayer:
			child.visible = false
	var viewport := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	var environment = w._mod.environment
	for view in ["water", "cloud", "scenery"]:
		w.camera.position = Vector3(5000, 30, 2300) if view != "scenery" else Vector3(2500, 120, 1700)
		w.camera.look_at(Vector3(5000, 0, 3400) if view == "water" else (Vector3(5000, 400, 2700) if view == "cloud" else Vector3(2450, 30, 1900)))
		for quality in [1, 0, 1]:
			w.apply_graphics_quality(quality if view == "water" else 1, quality if view == "cloud" else 1, quality if view == "scenery" else 1)
			# Freeze shader animation for matching images; this diagnostic does not change the game.
			for material in [environment._water_material_ref, environment._sky_material_ref]:
				var shader := material.shader.duplicate() as Shader
				shader.code = shader.code.replace("TIME", "12.0")
				material.shader = shader
			for i in 30:
				await frame()
			var gpu: Array[float] = []
			var cpu: Array[float] = []
			for i in 80:
				await frame()
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
			gpu.sort()
			cpu.sort()
			print("ENV_BENCH view=%s quality=%s gpu_median=%.3fms gpu_p95=%.3fms cpu_median=%.3fms primitives=%d" % [view, "Standard" if quality else "Low", gpu[40], gpu[76], cpu[40], root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)])
			root.get_texture().get_image().save_png("/tmp/redace-%s-%s.png" % [view, "standard" if quality else "low"])
	w.free()
	World._scene_cache.clear()
	quit()
