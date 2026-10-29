class_name Ini
## Reader for the original game's INI files.
## Section and key names are lower-cased; values stay strings. Sections keep file order.

const DATA_ROOT := "res://game_data/"


static func load_file(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("INI not found: " + path)
		return out
	var section := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with(";"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges().to_lower()
			if not out.has(section):
				out[section] = {}
			continue
		var eq := line.find("=")
		if eq < 0 or section.is_empty():
			continue
		out[section][line.substr(0, eq).strip_edges().to_lower()] = line.substr(eq + 1).strip_edges()
	return out


static func num(sec: Dictionary, key: String, default: float = 0.0) -> float:
	return float(sec[key]) if sec.has(key) else default


static func vec3(sec: Dictionary, key: String, default := Vector3.ZERO) -> Vector3:
	if not sec.has(key):
		return default
	var p: PackedStringArray = sec[key].split(" ", false)
	if p.size() < 3:
		return default
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


static func data_path(rel: String) -> String:
	return DATA_ROOT + rel.to_lower().replace("\\", "/")
