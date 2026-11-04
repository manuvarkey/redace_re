extends SceneTree
## Run with an isolated XDG_DATA_HOME: this exercises the actual settings save path.

class TestGame extends Game:
	func _ready() -> void:
		_load()
		strings = {"mission": "Mission", "cheatoptions": "Cheat Options"}
		view = HtmlView.new()
		add_child(view)
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
		check(not link.rects.is_empty(), "link is visible: " + link.href)
		for rect: Rect2 in link.rects:
			check(Rect2(0, 0, 640, 480).encloses(rect), "link stays in the page: " + link.href)
			for previous in rects:
				check(not previous.intersects(rect), "links do not overlap: " + link.href)
			rects.append(rect)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game := TestGame.new()
	root.add_child(game)
	check(game.settings.collision_damage == 0, "missing setting defaults to original damage")
	for completed in [false, true]:
		game.pilots[0] = {"name": "Test", "mission": 26 if completed else 1}
		game.current = 0
		game.open_page("Menus\\goodies.html")
		links_fit(game.view)
		var found := false
		for link in game.view._links:
			found = found or link.href.to_lower() == "menus\\extraoptions.html"
		check(found, "Extra Options available regardless of campaign progress")
	game._on_link("Menus\\extraoptions.html")
	check(game._page.to_lower().ends_with("extraoptions.html"), "Goodies link opens Extra Options")
	for mode in [1, 2, 0]:
		game._on_link("command:collisiondamage:%d" % mode)
		check(game.settings.collision_damage == mode, "menu command selects mode %d" % mode)
		check(game._collision_damage_options().contains("[%s]" % ["Default", "Mild", "Full"][mode]),
			"selected mode is marked")
		links_fit(game.view)
		var saved := ConfigFile.new()
		check(saved.load(Game.SETTINGS_PATH) == OK and saved.get_value("extra", "collision_damage", -1) == mode,
			"mode persisted to settings file")
		var loaded := Game.new()
		loaded._load()
		check(loaded.settings.collision_damage == mode, "mode survives reload")
		loaded.free()
	if "--snapshot" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/redace-extra-options.png")
	game._on_link("Menus\\goodies.html")
	check(game._page.to_lower().ends_with("goodies.html"), "Back returns to Goodies")
	if "--snapshot" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/redace-goodies-extra.png")
	game.free()
	print("Extra Options: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
