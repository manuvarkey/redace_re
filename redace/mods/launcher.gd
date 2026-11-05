extends RefCounted
## Generic mission extension loader. A mission declares [mod] init=res://mods/.../init.gd; World adds that
## node under the level before the map, objects and aircraft are made. Other [mod] keys belong to the mod.
##
## Hooks World calls on the mod node (each mod should define these):
##   setup_map(world, environment, level)   after the map, sky and fog are set up
##   create_aircraft() -> Aircraft          aircraft instance for each [airN] (Aircraft.new() for stock)
##   configure_aircraft(plane, section)     after Aircraft.setup, with the mission's [airN] section
##   counts_as_lost(plane) -> bool          whether a plane counts as lost for the mission rules
##   is_sea(pos) -> bool, sea_crash(pos)    water surfaces
##   camera_distance_scale (property)       chase camera distance factor (1.0 = original)
## Optional hooks, called only when defined (stock behaviour otherwise):
##   apply_graphics_quality(water, cloud)   graphics options changed
##   mission_step(world, dt)                every physics step, after the player's input and before the
##                                          rules; may override the player's controls for that step
##   mission_outcome(world, stock) -> String  the rules' decision each step ("" flying, "won", "death",
##                                          "time", "defence"); return the final one ("won" = win, any
##                                          other non-empty name = loss, "" = keep flying)
##   end_message(world, result) -> Variant  String replaces the end-of-flight line ("" = none); null = stock
##   result_page(world, result, campaign) -> String  menu page after the flight; "" = stock page
## World helpers for mission scripts: show_message(text, seconds), secure_progress() (credit the campaign
## win now, however the flight ends), map_markers (extra minimap icons: {pos: Vector3, icon: HUD icon name
## or res:// image}; cleared on each mission load).

static func for_mission(mission: Dictionary) -> Node:
	var path: String = str(mission.get("mod", {}).get("init", ""))
	if path.begins_with("res://mods/") and ResourceLoader.exists(path):
		return load(path).new()
	return null


## Mod campaigns: every res://mods/<name>/campaign.ini, in folder order. Keys of its [campaign] section:
##   id (default: folder name), title, missions = comma-separated mission ids in order,
##   ranks / ranksshort = comma-separated names (first = starting rank),
##   promotion = comma-separated scores at which rank 1, 2, ... is reached,
##   intro = menu page with the campaign's Start / Continue link, complete = page after the last mission.
## Game keeps each pilot's progress per campaign id, apart from the original campaign's.
static func campaigns() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root := DirAccess.open("res://mods/")
	if root == null:
		return out
	var folders := root.get_directories()
	folders.sort()
	for folder in folders:
		var path := "res://mods/%s/campaign.ini" % folder
		if not FileAccess.file_exists(path):
			continue
		var c: Dictionary = Ini.load_file(path).get("campaign", {})
		var missions: Array[int] = []
		for m in str(c.get("missions", "")).split(",", false):
			if m.strip_edges().is_valid_int():
				missions.append(int(m))
		var ranks := Array(str(c.get("ranks", "")).split(",", false)).map(func(r): return str(r).strip_edges())
		var short := Array(str(c.get("ranksshort", "")).split(",", false)).map(func(r): return str(r).strip_edges())
		var promotion := Array(str(c.get("promotion", "")).split(",", false)).map(func(r): return int(r))
		if missions.is_empty() or ranks.is_empty():
			continue
		out.append({"id": str(c.get("id", folder)), "title": str(c.get("title", folder)), "missions": missions,
			"ranks": ranks, "short": short if short.size() == ranks.size() else ranks, "promotion": promotion,
			"intro": str(c.get("intro", "")), "complete": str(c.get("complete", "Menus\\congrats.html"))})
	return out


static func mission_sequence(original: Array[int]) -> Array[int]:
	var sequence: Array[int] = original.duplicate()
	var root := DirAccess.open(Ini.data_path("missions/"))
	if root:
		for folder in root.get_directories():
			if not folder.is_valid_int():
				continue
			var id := int(folder)
			if id > 0 and not sequence.has(id):
				var data := Ini.load_file(Ini.data_path("missions/%d/mission.ini" % id))
				if data.has("mod"):
					sequence.append(id)
	sequence.sort()
	return sequence
