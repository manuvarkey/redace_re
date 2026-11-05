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
## win now, however the flight ends).

static func for_mission(mission: Dictionary) -> Node:
	var path: String = str(mission.get("mod", {}).get("init", ""))
	if path.begins_with("res://mods/") and ResourceLoader.exists(path):
		return load(path).new()
	return null


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
