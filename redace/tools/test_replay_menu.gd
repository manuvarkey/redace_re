extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var game := Game.new()
	game.strings = {"mission": "Mission"}
	game.pilots.assign([{}, {}, {}, {}, {}, {}])
	game.current = 0
	var view := HtmlView.new()
	root.add_child(view)
	var raw := FileAccess.get_file_as_string(Ini.data_path("language/english/menus/levelselect.html"))
	for reached in [1, 2, 3, 14, 25, 26]:
		game.pilots[0] = {"name": "Test", "mission": reached}
		view.show_html(raw.replace("^levelselector^", game._level_selector()))
		var expected := mini(reached - 1, Game.LAST_MISSION)
		var missions := []
		var back_rect := Rect2()
		for link in view._links:
			if link.href.to_lower() == "menus\\main.html":
				check(not link.rects.is_empty(), "Main Menu remains visible")
				if not link.rects.is_empty(): back_rect = link.rects[0]
			elif link.href.begins_with("missions\\"):
				missions.append(link)
		check(missions.size() == expected, "only unlocked missions appear for progress %d" % reached)
		var columns := {}
		for link in missions:
			check(not link.rects.is_empty(), "unlocked mission has a clickable rectangle: " + link.href)
			for rect: Rect2 in link.rects:
				check(rect.end.y <= 434.0 and not rect.intersects(back_rect), "mission stays above Main Menu: " + link.href)
				check(rect.position.x >= 220.0 and rect.end.x <= 422.0, "mission stays inside the painted panel: " + link.href)
				columns[int(rect.get_center().x < 320.0)] = true
		if expected > 1:
			check(columns.size() == 2, "replay list uses two columns")
	if "--snapshot" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/redace-replay-two-columns.png")
	game.free()
	view.free()
	print("Replay menu: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
