extends SceneTree
## Use isolated XDG_DATA_HOME. --write-startup=N then --expect-startup=N proves engine startup loading.
## --render-probe=/tmp/path.png captures actual GLES3 texture sampling for a paired Off/16x run.

class TestWorld extends World:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		camera = Camera3D.new()
		add_child(camera)

class TestGame extends Game:
	func _ready() -> void:
		_load()
		_layer = CanvasLayer.new()
		add_child(_layer)
		view = HtmlView.new()
		_layer.add_child(view)
		_click = AudioStreamPlayer.new()
		add_child(_click)
		set_process(false)

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
			check(Rect2(130, 160, 380, 260).encloses(rect) or link.href.to_lower() == "menus\\options.html", "link in panel: " + link.href)
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
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--write-startup="):
			var cfg := ConfigFile.new()
			cfg.load(Game.settings_path)
			cfg.set_value("rendering", Game.ANISOTROPY_SETTING, int(arg.get_slice("=", 1)))
			cfg.save(Game.settings_path)
			quit()
			return
		if arg.begins_with("--expect-startup="):
			check(int(ProjectSettings.get_setting("rendering/" + Game.ANISOTROPY_SETTING)) == int(arg.get_slice("=", 1)), "engine reads anisotropy before renderer startup")
		if arg.begins_with("--render-probe="):
			await render_probe(arg.get_slice("=", 1))
			quit(1 if failures else 0)
			return
	var game := TestGame.new()
	root.add_child(game)
	var saved := ConfigFile.new()
	saved.load(Game.settings_path)
	if not saved.has_section_key("graphics", "msaa"):
		check(game.settings.msaa == 0, "old saves default MSAA Off")
	if not saved.has_section_key("rendering", Game.ANISOTROPY_SETTING):
		check(game.settings.anisotropy == 0, "old saves default anisotropy Off")
	for key in ["water_detail", "cloud_detail", "scenery_detail"]:
		if not saved.has_section_key("graphics", key):
			check(game.settings[key] == 1, "old saves default quality to Standard")
	game.open_page("Menus\\graphicoptions.html")
	var distance: int = game.settings.clip_plane
	var detail: int = game.settings.effects_detail
	var fullscreen: bool = game.settings.fullscreen
	var window_size := root.size
	var scale := root.scaling_3d_scale
	Engine.time_scale = 0.73
	for key in ["msaa", "anisotropy", "water_detail", "cloud_detail", "scenery_detail"]:
		var labels: Array = Game.MSAA_LABELS if key == "msaa" else (Game.ANISOTROPY_LABELS if key == "anisotropy" else Game.DETAIL_LABELS)
		var count := labels.size()
		for mode in count:
			game._on_link("command:%s:%d" % [key, mode])
			check(game.settings[key] == mode, "select %s %d" % [key, mode])
			check(game._graphics_choices(key, labels).contains("[%s]" % labels[mode]), "selected choice marked")
			check(game.view._links.size() == 31, "all sliders, quality choices and Back fit")
			links_fit(game.view)
			if key == "msaa":
				check(root.msaa_3d == Viewport.MSAA_DISABLED, "menu-only viewport keeps MSAA disabled")
			var loaded := Game.new()
			loaded._load()
			check(loaded.settings[key] == mode, "setting survives reload")
			loaded.free()
	if "--snapshot" in OS.get_cmdline_user_args():
		await create_timer(0.3).timeout
		await settle()
		root.get_texture().get_image().save_png("/tmp/redace-graphics-options.png")
	game.world = TestWorld.new()
	game.add_child(game.world)
	for mode in Game.MSAA_LABELS.size():
		game._command("msaa:%d" % mode)
		check(root.msaa_3d == mode, "MSAA applies immediately in flight")
		if "--snapshot" in OS.get_cmdline_user_args():
			await settle()
			check(root.get_texture().get_image().get_pixel(200, 600).r > 0.1, "menu artwork remains visible over MSAA flight")
	game.world.particles = Particles.new()
	for value in [2, 5, detail]:
		game._command("effectsdetail:%d" % value)
		check(is_equal_approx(game.world.effects_detail, value / 10.0) and is_equal_approx(game.world.particles.detail, value / 10.0), "Effects Detail updates current flight particles")
	game.world.particles.free()
	game.world.particles = null
	check(is_equal_approx(Engine.time_scale, 0.73), "graphics changes preserve mission timing")
	game._end_flight()
	game.open_page("Menus\\graphicoptions.html")
	check(root.msaa_3d == Viewport.MSAA_DISABLED, "returning to menus disables MSAA")
	check(game.settings.clip_plane == distance and game.settings.effects_detail == detail, "existing graphics settings preserved")
	check(root.size == window_size and root.scaling_3d_scale == scale and game.settings.fullscreen == fullscreen, "display/render resolution preserved")
	Engine.time_scale = 1.0
	for key in ["msaa", "anisotropy", "water_detail", "cloud_detail", "scenery_detail"]:
		var before: int = game.settings[key]
		game._command(key + ":99")
		check(game.settings[key] == before, "invalid menu choice ignored")
	game._on_link("Menus\\Options.html")
	check(game._page.to_lower().ends_with("options.html"), "Back returns to Options")
	saved.load(Game.settings_path)
	for key in ["water_detail", "cloud_detail", "scenery_detail"]:
		saved.set_value("graphics", key, 99)
	saved.set_value("graphics", "msaa", 99)
	saved.set_value("rendering", Game.ANISOTROPY_SETTING, -1)
	saved.save(Game.settings_path)
	var invalid := Game.new()
	invalid._load()
	check(invalid.settings.msaa == 0 and invalid.settings.anisotropy == 0, "invalid saved choices fall back to Off")
	for key in ["water_detail", "cloud_detail", "scenery_detail"]:
		check(invalid.settings[key] == 1, "invalid saved detail falls back to Standard")
	invalid.free()
	game._command("msaa:0")
	game._command("anisotropy:0")
	game.free()
	print("Graphics Options: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func settle() -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw

func render_probe(path: String) -> void:
	check(DisplayServer.get_name() != "headless", "pixel test needs a graphical renderer")
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 2, 5)
	camera.look_at(Vector3(0, 0, -40))
	var mesh := MeshInstance3D.new()
	mesh.mesh = PlaneMesh.new()
	mesh.mesh.size = Vector2(20, 200)
	scene.add_child(mesh)
	mesh.position.z = -80
	var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	for y in 512:
		for x in 512:
			img.set_pixel(x, y, Color.WHITE if (x / 8 + y / 8) % 2 == 0 else Color.BLACK)
	img.generate_mipmaps()
	var material := ShaderMaterial.new()
	var shader := World._lit_shader(false, 0).duplicate() as Shader
	shader.code = shader.code.replace("texture(tex, UV)", "texture(tex, UV * vec2(10.0, 100.0))")
	material.shader = shader
	material.set_shader_parameter("tex", ImageTexture.create_from_image(img))
	material.set_shader_parameter("prelit", true)
	mesh.material_override = material
	await settle()
	root.get_texture().get_image().save_png(path)
	print("Anisotropy pixel probe: startup level=", ProjectSettings.get_setting("rendering/" + Game.ANISOTROPY_SETTING), " path=", path)
	scene.free()
