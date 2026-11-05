extends "res://mods/redbaron/mission_script.gd"
## Mission 12, The Last Patrol (design "12. The Last Patrol"):
##   1. Escort: four rookies run north for the German edge with six Camels after them. A rookie leaving
##      the map is home (left_map; not lost). On the fourth: campaign completion is saved at once
##      (secure_progress), and the six pursuers turn on the Baron.
##   2. Stop the pursuit: destroy all six (HUD counter).
##   3. The ridge: three more Camels every 40 s; ridge guns along the river. After 4 minutes of this a
##      burst of ground fire ends it.
## A rookie lost fails (Group3 = 100). The Baron's death after the rookies are home is not a defeat: no
## end line, then the epilogue page.

const WAVE_EVERY := 40.0
const RIDGE_TIME := 240.0

var rookies: Array[Aircraft] = []
var pursuers: Array[Aircraft] = []
var waves: Array[Aircraft] = []
var phase := 1
var home := 0
var phase3_at := 0.0
var _next_wave := 0.0
var _wave_index := 0


func start() -> void:
	owns_win = true
	end_messages["epilogue"] = ""
	result_pages["epilogue"] = "campaigns\\redbaron\\epilogue.html"
	for id in [3002, 3003, 3004, 3005]:
		rookies.append(plane(id))
	for id in range(3010, 3016):
		pursuers.append(plane(id))
	for id in range(3020, 3038):
		waves.append(plane(id))
	message("Get the new pilots home. Keep the Camels off them.", 6.0)


func outcome(stock: String) -> String:
	if stock == "death" and world.progress_was_secured:
		return "epilogue"
	return super.outcome(stock)


func step(_dt: float) -> void:
	var p := world.player
	if not alive(p):
		return
	match phase:
		1:
			var n := rookies.filter(func(r): return r.left_map and alive(r)).size()
			if n > home:
				home = n
				if home < rookies.size():
					message("%d of 4 are home." % home, 4.0)
				else:
					phase = 2
					secure_progress()
					for c in pursuers:
						if c.present():
							attack(c, p)
					message("All four are home. Turn back and stop the pursuit.", 6.0)
		2:
			var down := pursuers.filter(func(c): return not alive(c) or c.left_map).size()
			overlay().set_counter("Pursuers down %d / %d" % [down, pursuers.size()])
			if down == pursuers.size():
				phase = 3
				phase3_at = now()
				_next_wave = now()
				overlay().set_counter("")
		3:
			if now() >= _next_wave and _wave_index < waves.size():
				_next_wave = now() + WAVE_EVERY
				for k in 3:
					if _wave_index >= waves.size():
						break
					var c := waves[_wave_index]
					_wave_index += 1
					var at := p.global_position + Vector3((k - 1) * 200.0, 120.0, 700.0)
					at.x = clampf(at.x, world.map_bounds.position.x + 300.0, world.map_bounds.end.x - 300.0)
					at.z = clampf(at.z, world.map_bounds.position.y + 300.0, world.map_bounds.end.y - 300.0)
					reveal(c, at, [goal(Aircraft.G_ATTACK, p.object_id)], p.global_position - at)
			if now() >= phase3_at + RIDGE_TIME:
				phase = 4
				# the burst of ground fire from the ridge: shot down whatever the cheats (the story's end)
				p.health = 0.0
				p._shot_down()
