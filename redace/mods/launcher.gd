extends RefCounted
## Generic mission extension loader. A mission declares [mod] init=res://mods/.../init.gd.

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
