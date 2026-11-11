extends "res://mods/redbaron/mission_script.gd"
## Script for the missions that run on the original rules (design: 1, 3, 4, 5, 6, 9, 10). It only adds what
## the playtests asked for, from optional [mod] keys of the mission:
##   intro = text                   HUD line at the start (with the objective cue)
##   objective = text               the objective line kept on the HUD (default: the intro)
##   mark = x z                     minimap marker (the home aerodrome, the defended yard)
##   counter = group|label          HUD counter "label n / N" for a destroy group (n lost of N; "need k" when the
##                                  rule asks for fewer than all)
##   protect = group|label          every member of a protect group is marked (green ring and bracket; a ruin icon
##                                  once lost) and a counter line "label standing s / N, lost at L" is shown
##   prioritylabel = text           label on the brackets of the destroy-group targets
##   escape = id id ...             these planes leaving the map fail the mission at once ...
##   escapeline = text              ... with this end-of-flight line (result "escaped"; the mission's
##                                  failed_escaped.html follows the defeat page)
##   escapewarn = text              warning when an escaping plane comes within ESCAPE_WARN of the map edge
## Every plane and ground object in a destroy group (other than 9) is a priority target: blinking red-orange
## target icon on the minimap and a red-orange bracket in the view. The win and the losses stay with the
## original rules.

const ESCAPE_WARN := 900.0

var _counter_group := -1
var _counter_label := ""
var _protect_group := -1
var _protect_label := ""
var _escapers: Array[Aircraft] = []
var _escape_warned := {}
var _escape_warn_text := ""
var _counter_text := ""


func start() -> void:
	var m: Dictionary = mod.mission.get("mod", {})
	if m.has("mark"):
		var xz := str(m.mark).split(" ", false)
		mark_destination(Vector3(float(xz[0]), 0.0, float(xz[1])))
	if m.has("counter"):
		var parts := str(m.counter).split("|")
		_counter_group = int(parts[0])
		_counter_label = parts[1] if parts.size() > 1 else "Targets"
	if m.has("protect"):
		var parts := str(m.protect).split("|")
		_protect_group = int(parts[0])
		_protect_label = parts[1] if parts.size() > 1 else "Standing"
	for id in str(m.get("escape", "")).split(" ", false):
		var p := plane(int(id))
		if p:
			_escapers.append(p)
	if m.has("escapeline"):
		end_messages["escaped"] = str(m.escapeline)
	_escape_warn_text = str(m.get("escapewarn", ""))
	if m.has("intro"):
		objective(str(m.intro), str(m.get("objective", "")))
	var label := str(m.get("prioritylabel", ""))
	var destroy_planes: Array[Aircraft] = []
	for p in world.planes:
		for r in world.rules:
			if r.percent < 0.0 and p.groups & (1 << int(r.group)) and r.group != 9 and not destroy_planes.has(p):
				destroy_planes.append(p)
	for p in destroy_planes:
		mark_priority(p, label, destroy_planes.size() <= 3)
	for t in world.targets:
		for r in world.rules:
			if r.percent < 0.0 and t.groups & (1 << int(r.group)) and r.group != 9:
				mark_priority(t, label)
				break
	if _protect_group >= 0:
		for t in world.targets:
			if t.groups & (1 << _protect_group):
				mark_protect(t)
		for p in world.planes:
			if p.groups & (1 << _protect_group) and not p.is_player:
				mark_protect(p, label)


func step(_dt: float) -> void:
	for p in _escapers:
		if p.left_map and alive(p):
			lose("escaped")
			return
		if _escape_warn_text != "" and alive(p) and p.present() and not _escape_warned.has(p) \
				and _edge_distance(p) < ESCAPE_WARN:
			_escape_warned[p] = true
			warn(_escape_warn_text, 5.0)
	var lines: Array[String] = []
	for r in world.rules:
		if r.total > 0 and r.group == _counter_group:
			var need: int = int(ceil(r.total * -float(r.percent) / 100.0 - 0.01)) if r.percent < 0.0 else r.total
			lines.append("%s %d / %d" % [_counter_label, r.lost, r.total] + ("  (need %d)" % need if need < r.total else ""))
	for r in world.rules:
		if r.total > 0 and r.group == _protect_group and r.percent > 0.0:
			var lost_at: int = int(floor(r.total * (100.0 - float(r.percent)) / 100.0 + 0.01)) + 1
			lines.append("%s standing %d / %d  (fails at %d lost)" % [_protect_label, r.total - r.lost, r.total, lost_at])
	lines.append_array(extra_lines())
	var text := "\n".join(lines)
	if text != _counter_text:
		_counter_text = text
		overlay().set_counter(text)


## More HUD counter lines from a mission script (below the counter and protect lines).
func extra_lines() -> Array[String]:
	return []


## Flat distance from a plane to the map edge it is heading for (INF when it flies away from every near edge).
func _edge_distance(p: Aircraft) -> float:
	var b := world.map_bounds
	var pos := p.global_position
	var f := p.flight_basis.z
	var d := INF
	if f.x < -0.3:
		d = minf(d, pos.x - b.position.x)
	if f.x > 0.3:
		d = minf(d, b.end.x - pos.x)
	if f.z < -0.3:
		d = minf(d, pos.z - b.position.y)
	if f.z > 0.3:
		d = minf(d, b.end.y - pos.z)
	return d
