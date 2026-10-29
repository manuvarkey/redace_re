# Usage: godot --headless --path . -s tools/audit_missions.gd  (MS=1,2,3 limits the missions; ~25 s each)
extends SceneTree
# Headless audit: every mission, every placed object / aircraft / goal
var w: World
var mi := 0
var n := 0
var missions: Array = (OS.get_environment("MS").split(",") as Array).map(func(x): return int(x)) if OS.get_environment("MS") != "" else World.MISSIONS
var issues := {}  # text -> missions

func note(m: int, s: String) -> void:
	if not issues.has(s): issues[s] = []
	if not m in issues[s]: issues[s].append(m)

func _init():
	_next()

func _next():
	if w: w.queue_free()
	if mi >= missions.size():
		var keys := issues.keys(); keys.sort()
		for k in keys: print("ISSUE ", k, "  missions=", issues[k])
		var sk := stats.keys(); sk.sort()
		for k in sk: print("STAT ", k, ": ", stats[k][0], " placed, worst ", snappedf(stats[k][1], 0.1), "  missions=", stats[k][2])
		print("AUDIT DONE ", issues.size(), " distinct issues")
		quit(); return
	w = World.new(); w.standalone = true; w.mission_id = missions[mi]; root.add_child(w); n = 0

var stats := {}  # text -> [count, max, missions]
func stat(m: int, s: String, v: float) -> void:
	if not stats.has(s): stats[s] = [0, 0.0, []]
	stats[s][0] += 1
	stats[s][1] = maxf(stats[s][1], v)
	if not m in stats[s][2]: stats[s][2].append(m)

func _ray(a: Vector3, b: Vector3) -> float:
	var hit := w.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))
	return a.distance_to(hit.position) if hit else 1e9

func _sound_ok(f: String) -> bool:
	return f.is_empty() or World.load_sound(f) != null

func _physics_process(_dt):
	n += 1
	if n != 3: return false
	var m: int = missions[mi]
	var mf := Ini.load_file(Ini.data_path("missions/%d/mission.ini" % m))
	if mf.is_empty(): note(m, "mission.ini missing")
	var placed := 0
	var spawned_ids := {}
	for t in w.targets: spawned_ids[t.id] = t
	for p in w.planes: spawned_ids[p.object_id] = p
	var b := w.map_bounds
	for sn in mf.keys():
		var sec: Dictionary = mf[sn]
		if sn.begins_with("ground") or sn.begins_with("vehicle"):
			placed += 1
			var name := str(sec.get("name", "")).to_lower()
			var id := int(Ini.num(sec, "id", 0))
			var ini := Ini.load_file(Ini.data_path("objects/ground/%s/ground.ini" % name))
			if ini.is_empty(): note(m, "object type '%s' has no ground.ini (not placed)" % name); continue
			if not spawned_ids.has(id): note(m, "object '%s' not spawned" % name); continue
			if not spawned_ids[id] is Dictionary: continue
			var t: Dictionary = spawned_ids[id]
			for mp in t.models:
				if not ResourceLoader.exists(Ini.data_path(mp)): note(m, "object '%s' model missing: %s" % [name, mp])
			var snd: Dictionary = ini.get("sound", {})
			for k in snd:
				if str(k) in ["hitsound", "althitsound", "explosion", "breakage", "gunfire", "altgunfire"] and not _sound_ok(str(snd[k])):
					note(m, "object '%s' sound missing: %s=%s" % [name, k, snd[k]])
			var pos := Ini.vec3(sec, "pos")
			if not b.grow(50).has_point(Vector2(pos.x, pos.z)): note(m, "object '%s' outside map" % name)
			else:
				var below := _ray(pos + Vector3.UP * 1.5, pos + Vector3.DOWN * 400.0)
				var above := _ray(pos + Vector3.UP * 1.5, pos + Vector3.UP * 400.0)
				var gap: float = below
				if below > 6.0 and above < below:
					stat(m, "object '%s' base under terrain surface" % name, above)
				elif below > 6.0 and not (name.contains("bridge") or name.contains("viaduct")):
					stat(m, "object '%s' floating above ground" % name, below)
		elif sn.begins_with("air") and not sn.contains("goal"):
			var pn := str(sec.get("name", "")).to_lower()
			if not FileAccess.file_exists(Ini.data_path("objects/planes/%s/plane.ini" % pn)): note(m, "plane type '%s' missing" % pn)
			var id := int(Ini.num(sec, "id", 0))
			if not spawned_ids.has(id): note(m, "plane '%s' not spawned" % pn)
		elif sn.contains("goal"):
			var tid := int(Ini.num(sec, "targetid", 0))
			var gt := int(Ini.num(sec, "type", 0))
			if tid > 0 and not spawned_ids.has(tid): note(m, "goal 0x%x in %s targets missing id %d" % [gt, sn, tid])
			if not gt in Aircraft.GOAL_TYPES: note(m, "goal type 0x%x ignored (as the exe)" % gt)
	for p in w.planes:
		if p._model == null: note(m, "plane '%s' has no model" % p.plane_name)
		for s in [p._hit_sound, p._blast_sound]:
			if s == null: note(m, "plane '%s' sound missing" % p.plane_name)
		var gh := w.ground_height(p.global_position)
		if gh < -900: note(m, "plane '%s' over a terrain hole" % p.plane_name)
		elif p.global_position.y - gh < -2.0: stat(m, "plane '%s' starts below the terrain" % p.plane_name, gh - p.global_position.y)
	if w.player == null: note(m, "no player plane")
	for r in w.rules:
		if r.total == 0: note(m, "rule group %d has no members" % r.group)
	print("mission %d: %d ground/vehicle sections, %d spawned, %d planes" % [m, placed, w.targets.size(), w.planes.size()])
	mi += 1
	_next()
	return false
