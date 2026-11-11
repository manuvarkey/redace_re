extends SceneTree
## Use isolated XDG_DATA_HOME. Omit --headless to also prove GLES3 buffer scaling by pixels.

class TestGame extends Game:
	var fake_screen := false

	func _window_size(height: int) -> Vector2i:
		return Vector2i(height * 16 / 9, height) if fake_screen else super._window_size(height)

	func _ready() -> void:
		_load()
		_setup_audio_buses()
		_layer = CanvasLayer.new()
		_layer.layer = 10
		add_child(_layer)
		view = HtmlView.new()
		_layer.add_child(view)
		_click = AudioStreamPlayer.new()
		add_child(_click)
		root_window().size_changed.connect(_update_render_resolution)
		set_process(false)

	func root_window() -> Window:
		return get_tree().root

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func links_fit(view: HtmlView) -> void:
	var rects: Array[Rect2] = []
	for link in view._links:
		check(not link.rects.is_empty(), "visible link: " + link.href)
		for rect: Rect2 in link.rects:
			check(Rect2(0, 0, 640, 480).encloses(rect), "link within page: " + link.href)
			for previous in rects:
				check(not previous.intersects(rect), "links do not overlap: " + link.href)
			rects.append(rect)

func _initialize() -> void:
	# scratch save files: never the player's own pilots, options or bindings
	Game.save_path = "user://test_pilots.cfg"
	Game.settings_path = "user://test_settings.cfg"
	_remove_scratch_files()
	run.call_deferred()

func _finalize() -> void:
	_remove_scratch_files()

func _remove_scratch_files() -> void:
	for path in [Game.save_path, Game.settings_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func run() -> void:
	var game := TestGame.new()
	root.add_child(game)
	check(game.settings.render_height == 0, "existing users default to Native")
	check(game.settings.window_height == 0, "existing window size preserved")
	game.fake_screen = true
	game.open_page("Menus\\videooptions.html")
	links_fit(game.view)
	check(game.view._links.size() == 14, "all rendering, window size, mode, vsync and Back links fit")
	game.fake_screen = false
	var distance: int = game.settings.clip_plane
	var detail: int = game.settings.effects_detail
	for size in [Vector2i(1024, 768), Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2560, 1080)]:
		for height in Game.RENDER_HEIGHTS:
			var scale := Game.render_scale(size.y, height)
			var internal := Vector2(size) * scale
			check(is_equal_approx(internal.x / internal.y, float(size.x) / size.y), "uniform scale preserves aspect")
			check(is_equal_approx(internal.y, mini(size.y, height) if height else size.y), "target height capped at Native")
	for height in Game.RENDER_HEIGHTS:
		game.open_page("Menus\\videooptions.html")
		links_fit(game.view)
		if game.settings.render_height == height:
			continue
		var before: int = game.settings.render_height
		game._command("renderresolution:%d" % height)
		check(game._page.ends_with("screentest.html"), "resolution opens confirmation")
		check(is_equal_approx(root.scaling_3d_scale, Game.render_scale(root.size.y, height)), "preset applied to actual root viewport")
		game._save()  # e.g. an unrelated pilot/settings save while a preview is pending
		var loaded := Game.new()
		loaded._load()
		check(loaded.settings.render_height == before, "unconfirmed setting not persisted")
		loaded.free()
		game._command("keepvideo")
		loaded = Game.new()
		loaded._load()
		check(loaded.settings.render_height == height, "confirmed resolution survives reload")
		loaded.free()
	Engine.time_scale = 0.73
	game._command("renderresolution:360")
	check(is_equal_approx(Engine.time_scale, 0.73), "resolution preview preserves mission timing")
	game._command("timeout")
	check(is_equal_approx(Engine.time_scale, 0.73), "resolution rollback preserves mission timing")
	Engine.time_scale = 1.0
	check(game.settings.render_height == 0, "No restores previous rendering resolution")
	# An earlier preview's timer must not roll back a later preview prematurely.
	await create_timer(1.0).timeout
	game._command("renderresolution:480")
	Engine.time_scale = 2.0
	paused = true
	await create_timer(4.2, true, false, true).timeout
	check(game.settings.render_height == 480, "stale timers cannot revert a newer preview")
	await create_timer(1.0, true, false, true).timeout
	check(game.settings.render_height == 0, "timeout rolls back while paused, independent of game speed")
	paused = false
	Engine.time_scale = 1.0
	check(game.settings.clip_plane == distance and game.settings.effects_detail == detail, "graphics settings preserved")
	game._command("renderresolution:123")
	check(game.settings.render_height == 0, "invalid resolution ignored")
	var cfg := ConfigFile.new()
	cfg.load(Game.settings_path)
	cfg.set_value("video", "render_height", 123)
	cfg.set_value("video", "window_height", -20)
	cfg.save(Game.settings_path)
	var invalid := Game.new()
	invalid._load()
	check(invalid.settings.render_height == 0 and invalid.settings.window_height == 0, "unsupported saved settings fall back")
	invalid.free()
	game._save()
	if DisplayServer.get_name() != "headless":
		await graphical_checks(game)
	game.free()
	print("Video Options: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func settle() -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw

func graphical_checks(game: Game) -> void:
	check(RenderingServer.get_current_rendering_method() == "gl_compatibility", "exercise Compatibility renderer")
	game.open_page("Menus\\videooptions.html")
	await settle()
	root.get_texture().get_image().save_png("/tmp/redace-video-options.png")
	# Physical/window mode changes and complete rollback.
	var old_size := DisplayServer.window_get_size()
	game._command("windowresolution:480")
	await settle()
	check(DisplayServer.window_get_size() == game._window_size(480), "window resolution applied")
	game._command("timeout")
	await settle()
	check(DisplayServer.window_get_size() == old_size, "window size rolled back")
	game._command("videomode:1")
	await settle()
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "fullscreen applied")
	game._command("timeout")
	await settle()
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "windowed mode restored")
	game.view.visible = false
	var camera := Camera3D.new()
	root.add_child(camera)
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	mesh.scale = Vector3(100, 100, 1)
	mesh.position.z = -2
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO = vec3(mod(floor(FRAGCOORD.x), 2.0)); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	mesh.material_override = material
	root.add_child(mesh)
	for size in [Vector2i(800, 600), Vector2i(960, 540), Vector2i(960, 600)]:
		DisplayServer.window_set_size(size)
		await settle()
		game.settings.render_height = 0
		game._update_render_resolution()
		await settle()
		var native := root.get_texture().get_image()
		game.settings.render_height = 360
		game._update_render_resolution()
		await settle()
		var low := root.get_texture().get_image()
		check(native.get_size() == low.get_size(), "UI/output buffer dimensions unchanged")
		check(is_equal_approx(root.scaling_3d_scale, 360.0 / root.size.y), "resize reapplies 360p scale")
		# Full contrast alternating pixels at Native must be filtered when the 3D buffer is smaller.
		var native_edges := 0.0
		var low_edges := 0.0
		for x in range(10, low.get_width() - 10):
			native_edges += absf(native.get_pixel(x, 30).r - native.get_pixel(x - 1, 30).r)
			low_edges += absf(low.get_pixel(x, 30).r - low.get_pixel(x - 1, 30).r)
		check(low_edges < native_edges * 0.8, "rendered pixels prove smaller GLES3 3D buffer: %s (%f / %f)" % [size, low_edges, native_edges])
	mesh.free()
	camera.free()
