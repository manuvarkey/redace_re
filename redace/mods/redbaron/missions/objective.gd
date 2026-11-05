extends "res://mods/redbaron/mission_script.gd"
## Script for the missions that run on the original rules (design: 1, 3, 4, 5, 6, 10). It only adds what
## the playtests asked for, from optional [mod] keys of the mission:
##   intro = text                   HUD line at the start
##   mark = x z                     minimap marker (the home aerodrome)
##   counter = group|label          HUD counter "label n / N" for a rule group (n lost of N)
##   escape = id id ...             these planes leaving the map fail the mission at once ...
##   escapeline = text              ... with this end-of-flight line (result "escaped"; the mission's
##                                  failed_escaped.html follows the defeat page)
## Every plane in a destroy group gets the target icon on the minimap, following it.
## The win and the other losses stay with the original rules.

var _counter_group := -1
var _counter_label := ""
var _escapers: Array[Aircraft] = []


func start() -> void:
	var m: Dictionary = mod.mission.get("mod", {})
	if m.has("mark"):
		var xz := str(m.mark).split(" ", false)
		mark_on_map(Vector3(float(xz[0]), 0.0, float(xz[1])))
	if m.has("counter"):
		var parts := str(m.counter).split("|")
		_counter_group = int(parts[0])
		_counter_label = parts[1] if parts.size() > 1 else "Targets"
	for id in str(m.get("escape", "")).split(" ", false):
		var p := plane(int(id))
		if p:
			_escapers.append(p)
	if m.has("escapeline"):
		end_messages["escaped"] = str(m.escapeline)
	if m.has("intro"):
		message(str(m.intro), 6.0)
	for p in world.planes:
		for r in world.rules:
			if r.percent < 0.0 and p.groups & (1 << int(r.group)) and r.group != 9:
				track_on_map(p)


func step(_dt: float) -> void:
	track_markers()
	for p in _escapers:
		if p.left_map and alive(p):
			lose("escaped")
			return
	if _counter_group >= 0:
		for r in world.rules:
			if r.group == _counter_group and r.total > 0:
				overlay().set_counter("%s %d / %d" % [_counter_label, r.lost, r.total])
