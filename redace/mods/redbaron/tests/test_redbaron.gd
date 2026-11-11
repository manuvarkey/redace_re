extends SceneTree
## Red Baron mod tests: godot --headless --path redace -s res://mods/redbaron/tests/test_redbaron.gd
## Phase 1: the mission script API and the generic World / Game hooks, on the fixture mission 199.

const FIXTURE := 199
const RedBaronInit := preload("res://mods/redbaron/init.gd")
const RedBaronAircraft := preload("res://mods/redbaron/aircraft.gd")
const MS := preload("res://mods/redbaron/mission_script.gd")
const ObjectiveScript := preload("res://mods/redbaron/missions/objective.gd")
## Sustained gun rates (docs/plane_figures.md): German twin Spandau 23.3, the Dr.I 32.7 (the player's 1918 upgrade);
## British twin guns 1.5x weaker than the Albatros (15.6); single guns half their side's twin rate (British 7.8, German 11.7).
const RATES := {"albatros_red": 23.33, "albatros_brenner": 23.33, "albatros_wingman": 23.33, "albatros_player": 23.33,
	"fokker_red": 32.67, "fokker_brenner": 32.67, "fokker_rookie": 32.67, "sopwithcamel_rb": 15.56, "se5a_rb": 15.56,
	"nieuport17_rb": 7.78, "bristolscout_rb": 7.8, "aircodh2_rb": 7.78, "re8": 7.78, "handleypage": 7.78, "halberstadt_rb": 11.66}

var world: World
var ticks := 0
var checks := 0
var failures := 0
var stage := 0
var _stage_tick := 0
var _timer_fired := 0.0
var _secured := 0
var _damaged := []


## Game without saving, menus, music or video changes: only the flight-result bookkeeping is real.
class TestGame extends Game:
	var opened: Array[String] = []
	func _ready() -> void:
		_load()  # defaults: the scratch save files do not exist
		_click = AudioStreamPlayer.new()
		add_child(_click)
	func _save() -> void:
		pass
	func _play_menu_music() -> void:
		pass
	func _apply_graphics_settings() -> void:
		pass
	func open_page(path: String) -> void:
		opened.append(path)


func _initialize() -> void:
	# scratch save files: never the player's own pilots, options or bindings
	Game.save_path = "user://test_pilots.cfg"
	Game.settings_path = "user://test_settings.cfg"
	world = World.new()
	world.standalone = false
	root.add_child.call_deferred(world)
	_start.call_deferred()


func _start() -> void:
	world.progress_secured.connect(func() -> void: _secured += 1)
	world.load_mission(FIXTURE)


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


func s() -> MS:
	return world._mod.mission_script


func _physics_process(_dt: float) -> bool:
	ticks += 1
	if ticks - _stage_tick < 12:
		return false
	_stage_tick = ticks
	match stage:
		0: _check_load()
		1: _check_reveal_and_controls()
		2: _check_rules_and_win()
		3: _reload()
		4: _check_scripted_loss()
		5: _check_stock_isolation()
		6: _check_game_hooks()
		7: world.load_mission(102)
		8: _m02_rejoin()
		9: _m02_win_and_loss()
		10: world.load_mission(108)
		11: _m08_wound()
		12: _m08_land()
		13: world.load_mission(108)
		14: _m08_crash()
		15: world.load_mission(108)
		16: _m08_escape()
		17: _check_campaign_menus()
		18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38:
			_stock_rule_mission(stage - 18)
		39: world.load_mission(107)
		40: _m07()
		41: world.load_mission(111)
		42: _m11()
		43: world.load_mission(112)
		44: _m12()
		45: world.load_mission(112)
		46: _m12_rookie_lost()
		_:
			print("RED BARON: %d checks, %d failures" % [checks, failures])
			quit(1 if failures else 0)
			return true
	stage += 1
	return false


func _check_load() -> void:
	check(world._mod is RedBaronInit, "mission 199 loads the Red Baron init")
	check(s() != null and s().get_script().resource_path.ends_with("tests/fixture_script.gd"), "[mod] script is loaded")
	check(s().started and s().get("start_calls") == 1, "start() runs once on the first step")
	check(int(s().get("steps")) >= 2, "step() runs every physics step (mission_step hook)")
	check(world.player.get_script() == RedBaronAircraft, "aircraft come from the mod (create_aircraft)")
	check(world.planes.size() == 5, "all fixture planes spawned")
	# environment keys
	var env: Environment = world._mod.environment
	check(env.fog_light_color.is_equal_approx(Color8(200, 120, 80)), "[environment] fogcolour sets the fog")
	check(env.ambient_light_color.is_equal_approx(Color8(100, 100, 120)), "[environment] ambient sets the ambient light")
	var sky_fog: Color = (env.sky.sky_material as ShaderMaterial).get_shader_parameter("fog_color")
	check(sky_fog.is_equal_approx(Color8(200, 120, 80)), "fog colour reaches the sky horizon")
	var tint: Color = world._mod.light_tint
	check(tint.is_equal_approx(Color8(204, 153, 102)), "[environment] light tints the lit scene (%s)" % tint)
	var sky_front: Texture2D = (env.sky.sky_material as ShaderMaterial).get_shader_parameter("sky_front")
	check(sky_front != null and sky_front.resource_path.ends_with("skies/dawn/sky_front.jpg"), "[environment] sky loads .jpg faces")
	s().set_fog(Color(0.1, 0.2, 0.3))
	check(env.fog_light_color.is_equal_approx(Color(0.1, 0.2, 0.3)), "set_fog changes the fog at run time")
	# gunners
	var enemy: Aircraft = s().plane(9003)
	var hidden_enemy: Aircraft = s().plane(9004)
	var two_seater: Aircraft = s().plane(9005)
	check(two_seater.get("gunners_enabled") == true, "halberstadt has gunners by default")
	check(enemy.get("gunners_enabled") == true, "[airN] gunners = 1 turns gunners on")
	check(world.player.get("gunners_enabled") == false, "fighters have no gunners")
	# hidden planes are not lost; rules count them alive
	check(hidden_enemy.hidden, "0x170 hides the plane")
	var r9: Dictionary = world.rules.filter(func(r): return r.group == 9)[0]
	check(r9.total == 2 and r9.lost == 0, "hidden enemy is not lost (counts_as_lost)")
	# timers, flags, distances
	s().after(0.1, func() -> void: _timer_fired = world.mission_time)
	check(s().once("a") and not s().once("a") and s().flag("a"), "once / flag")
	var d := MS.distance(world.player, Vector3(6500, 700, 7100))
	check(d > 0.0 and MS.near(world.player, world.player.global_position + Vector3(10, 0, 0), 11.0), "distance / near")
	check(MS.distance(Vector3(0, 0, 0), Vector3(3, 100, 4), true) == 5.0, "flat distance")
	check(s().planes_in_group(9).size() == 2, "planes_in_group")
	# goals
	MS.fly_to(enemy, Vector3(7000, 800, 7000))
	check(enemy.goals.size() == 1 and enemy.current_goal().type == Aircraft.G_WAYPOINT, "set_goals replaces the goal list")
	MS.attack(enemy, world.player)
	check(enemy.current_goal().type == Aircraft.G_ATTACK and enemy.current_goal().targetid == 9001, "attack retargets")
	var friend: Aircraft = s().plane(9002)
	MS.formation(friend, world.player, Vector3(20, 0, -20))
	check(friend.current_goal().type == Aircraft.G_FORMATION and friend.current_goal().offset == Vector3(20, 0, -20),
		"formation goal with offset")
	# damage
	enemy.damaged.connect(func(_p, amount, attacker) -> void: _damaged.append([amount, attacker]))
	var before := enemy.health
	MS.damage(enemy, 5.0, world.player)
	check(is_equal_approx(enemy.health, before - 5.0), "damage takes health")
	check(_damaged.size() == 1 and _damaged[0][1] == world.player, "damaged signal carries the attacker")
	# message
	s().message("Brenner rejoins", 2.0)
	check(world.message_label.text == "Brenner rejoins", "message shows on the HUD")
	# reveal (takes effect in the plane's next step)
	MS.reveal(hidden_enemy, Vector3(7000, 900, 7300), [MS.goal(Aircraft.G_ATTACK, 9001)])
	# controls override
	s().set("throttle_cap", 0.3)
	s().set("guns_off", true)
	world.player.throttle = 1.0
	world.player.fire_input = true


func _check_reveal_and_controls() -> void:
	var hidden_enemy: Aircraft = s().plane(9004)
	check(hidden_enemy.present() and hidden_enemy.state in [Aircraft.State.FLYING, Aircraft.State.STALL], "reveal brings the plane in airborne (state %d hidden %s goal %s)" % [hidden_enemy.state, hidden_enemy.hidden, hidden_enemy.current_goal()])
	check(MS.near(hidden_enemy, Vector3(7000, 900, 7300), 60.0), "reveal places it at the given position")
	check(hidden_enemy.current_goal().type == Aircraft.G_ATTACK, "reveal continues with the given goals")
	check(_timer_fired > 0.0, "after() fires")
	check(world.player.throttle <= 0.3 + 1e-6, "mission_step can cap the player's throttle")
	check(not world.player.fire_input, "mission_step can hold the player's guns")
	MS.hide(hidden_enemy)
	check(hidden_enemy.hidden and not hidden_enemy.present(), "hide")
	# counts_as_lost
	var mod: RedBaronInit = world._mod
	var enemy: Aircraft = s().plane(9003)
	var friend: Aircraft = s().plane(9002)
	check(not mod.counts_as_lost(hidden_enemy), "hidden enemy not lost")
	enemy.left_map = true
	friend.left_map = true
	check(mod.counts_as_lost(enemy), "group 9 that left the map is lost")
	check(not mod.counts_as_lost(friend), "group 8 that left the map escaped (not lost)")
	enemy.left_map = false
	friend.left_map = false
	s().set("throttle_cap", -1.0)
	s().set("guns_off", false)


func _check_rules_and_win() -> void:
	# all enemies down: the stock rules would win, but the script owns the win
	for p in world.planes:
		if not p.allied:
			p.state = Aircraft.State.DEAD
	world._count_rule_members()
	check(world._rules_result() == "won", "stock rules decide won")
	world._check_rules()
	check(not world.mission_over, "owns_win keeps flying when the stock rules win")
	s().end_messages["won"] = "Both home"
	s().result_pages["won"] = "Menus\\victory.html"
	s().secure_progress()
	s().secure_progress()
	check(_secured == 1 and world.progress_was_secured, "secure_progress emits once")
	s().win()
	world._check_rules()
	check(world.mission_over and world._end_result == "won", "win() ends the flight as a win")
	check(world._end_label.text == "Both home", "end_message replaces the end line")
	check(world.result_page("won", true) == "Menus\\victory.html", "result_page names the page")
	check(world.result_page("death", true) == "", "no page for other results")


func _reload() -> void:
	world.load_mission(FIXTURE)


func _check_scripted_loss() -> void:
	check(not world.progress_was_secured, "reload clears secured progress")
	check(s().get("start_calls") == 1, "new script per flight")
	# player death would end it as "death"; a script may rename it and hide the line
	world.player.state = Aircraft.State.DEAD
	s().end_messages["epilogue"] = ""
	s().lose("epilogue")
	world._check_rules()
	check(world.mission_over and world._end_result == "epilogue", "lose() with a script's own result")
	check(world._end_label.text == "", "empty end line")


func _check_stock_isolation() -> void:
	world.load_mission(21)
	check(world._mod == null, "stock mission has no mod")
	check(world.map_markers.is_empty(), "map markers cleared on mission load")
	check(world.player.get_script() == load("res://scripts/aircraft.gd"), "stock aircraft class")
	world.player.state = Aircraft.State.DEAD
	world._check_rules()
	check(world._end_result == "death" and world._end_label.text == "Plane Destroyed", "stock death line unchanged")
	check(world.result_page("death", true) == "", "stock result page unchanged")


func _check_game_hooks() -> void:
	var game := TestGame.new()
	root.add_child(game)
	game.pilots.assign([{"name": "Manfred", "mission": 5, "score": 600, "rank": 0}, {}, {}, {}, {}, {}])
	game.current = 0
	# a mission script secures campaign progress mid-flight, then the flight ends in a scripted loss
	var w := World.new()
	w.standalone = false
	game.world = w
	game.add_child(w)
	w.load_mission(FIXTURE)
	w.progress_secured.connect(game._on_progress_secured)
	game._mission = 5
	game._flown = 5
	game._campaign = true
	w._mod.mission_script.result_pages["epilogue"] = "Menus\\credits.html"
	w.secure_progress()
	check(int(game.pilots[0].mission) == 6, "secure_progress advances the campaign at once")
	var score := int(game.pilots[0].score)
	check(score > 600, "secure_progress adds the mission score")
	game._on_finished("epilogue", 0)
	check(game.opened.back() == "Menus\\credits.html", "result_page replaces the defeat page")
	check(int(game.pilots[0].mission) == 6 and int(game.pilots[0].score) == score, "no double credit after the flight")
	# a plain win with a custom page still advances once
	w = World.new()
	w.standalone = false
	game.world = w
	game.add_child(w)
	w.load_mission(FIXTURE)
	game._mission = 6
	w._mod.mission_script.result_pages["won"] = "Menus\\credits.html"
	game._on_finished("won", 600)
	check(int(game.pilots[0].mission) == 7, "win advances the campaign")
	check(game.opened.back() == "Menus\\credits.html", "result_page replaces the victory page")
	# stock: no world page
	w = World.new()
	w.standalone = false
	game.world = w
	game.add_child(w)
	w.load_mission(21)
	game._mission = 7
	game._on_finished("death", 0)
	check(game.opened.back() == "Menus\\defeat.html", "stock defeat page")
	game.queue_free()


# ---------------------------------------------------------------- mission 2: First Sortie

func _settle() -> void:
	## Script and rules evaluated now, as in a physics step.
	s().run_step(0.0)
	world._count_rule_members()
	world._check_rules()


func _m02_rejoin() -> void:
	check(world._mod is RedBaronInit and s().get_script().resource_path.ends_with("missions/m02.gd"), "102 loads m02.gd")
	var b: Aircraft = s().plane(3002)
	var nieuport: Aircraft = s().plane(3004)
	var sustained := func(a: Aircraft) -> float: return a.fire_rate * a.fire_on / (a.fire_on + a.fire_off)
	check(world.player.plane_name == "albatros_red" and b.plane_name == "albatros_brenner", "tuned Albatros folders")
	check(absf(sustained.call(world.player) - 25.0 * 1.4 / 1.5) < 0.01 and is_equal_approx(sustained.call(b), sustained.call(world.player)) and is_equal_approx(world.player.fire_rate, 25.0),
		"player and Brenner guns match the original mission 1 player (%.1f rounds/s)" % sustained.call(world.player))
	for id in [3003, 3004, 3005]:
		check(absf(sustained.call(s().plane(id)) - 7.8) < 0.1, "mission 2 enemy %d: single gun, 7.8 rounds/s" % id)
	check(world.player.high_speed == 110.0 and world.player.endurance == 125.0 and b.endurance == 125.0, "design stats")
	check(b.current_goal().type == Aircraft.G_FORMATION and b.current_goal().targetid == 3001, "Brenner starts on the Baron's wing")
	check(b.high_speed > world.player.high_speed, "Brenner is faster, so he can run away")
	check(world.player.ordnance_type == 2 and world.player.ordnance_left == 10, "102: 10 rockets")
	check(s().plane(3004).hidden and s().plane(3005).hidden, "ambush hidden at start")
	world._count_rule_members()
	check(world.rules[0].group == 2 and world.rules[0].lost == 0, "Brenner protected (Group2)")
	# all enemies down (the hidden ambush too): the stock rules would win, the script does not
	var enemies := world.planes.filter(func(p): return not p.allied)
	for e in enemies:
		e.state = Aircraft.State.DEAD
	_settle()
	check(not world.mission_over, "killing the enemies does not win mission 2")
	for e in enemies:
		e.state = Aircraft.State.FLYING
	# Brenner breaks off at 6 s, the Baron closes on him (over the lines, far from the aerodrome)
	var p := world.player
	p.global_position = Vector3(8000, 650, 7600)
	b.global_position = p.global_position + Vector3(100, 0, 0)
	world.mission_time = 5.0
	_settle()
	check(not s().broke_off, "no break before 6 s")
	world.mission_time = 6.5
	_settle()
	check(s().broke_off and b.current_goal().type == Aircraft.G_WAYPOINT and b.current_goal().pos.is_equal_approx(s().decoy.global_position),
		"Brenner breaks off after the decoy at 6 s, flat out (waypoint on the Scout)")
	check(world.message_label.text.begins_with("Brenner breaks off"), "HUD says when Brenner breaks off")
	check(not s().armed and not s().rejoined, "catching him does not count yet")
	b.global_position = p.global_position + Vector3(150, 0, 0)
	world.mission_time = 30.0
	_settle()
	check(not s().armed and not s().rejoined, "no time fallback: catching him counts only after he reaches the Scout")
	var decoy: Aircraft = s().plane(3003)
	b.global_position = decoy.global_position + Vector3(200, 0, 0)
	p.global_position = b.global_position + Vector3(150, 0, 0)
	_settle()
	check(s().armed and not s().rejoined, "Brenner near the Scout: intermediate event")
	check(b.current_goal().type == Aircraft.G_ATTACK and b.current_goal().targetid == 3003, "on the Scout he attacks it")
	check(world.message_label.text.begins_with("Brenner is over the British guns"), "HUD says Brenner is in danger")
	_settle()
	check(not s().rejoined, "no rejoin in the same moment as the previous event")
	world.mission_time = 35.0
	b.global_position = p.global_position + Vector3(180, 0, 0)
	_settle()
	check(s().rejoined and b.current_goal().type == Aircraft.G_FORMATION and b.current_goal().targetid == 3001,
		"Brenner rejoins in formation within 200")
	check(world.message_label.text == "Brenner joins. Return to base.", "HUD says Brenner joins, return to base")
	# halfway home the interceptors come in
	var inter: Array = [s().plane(3006), s().plane(3007)]
	check(inter[0].hidden and inter[1].hidden, "interceptors hidden until halfway home")
	var home := Vector3(6200, 650, 7450)
	var start: Vector3 = p.global_position
	world.mission_time = 40.0
	p.global_position = start.lerp(home, 0.3)
	b.global_position = p.global_position + Vector3(30, 0, 30)
	_settle()
	check(not s().intercepted, "not yet halfway")
	p.global_position = start.lerp(home, 0.6)
	b.global_position = p.global_position + Vector3(30, 0, 30)
	_settle()
	check(s().intercepted and inter[0].current_goal().type == Aircraft.G_APPEAR and not inter[0].hidden,
		"two Nieuports revealed halfway home")
	check(inter[0].goals[1].targetid == 3001 and inter[1].goals[1].targetid == 3002, "one on the Baron, one on Brenner")
	check(world.map_markers.size() == 1 and MS.near(world.map_markers[0].pos, Vector3(6200, 0, 7450), 1.0),
		"aerodrome marked on the minimap")


func _m02_win_and_loss() -> void:
	var p := world.player
	var b: Aircraft = s().plane(3002)
	var home := Vector3(6200, 650, 7450)
	p.global_position = home
	b.global_position = home + Vector3(800, 0, 0)
	_settle()
	check(not world.mission_over, "no win until Brenner is home too")
	b.global_position = home + Vector3(150, 0, 100)
	_settle()
	check(world.mission_over and world._end_result == "won", "both near the aerodrome wins")
	world.load_mission(102)
	await physics_frame
	await physics_frame
	s().plane(3002).state = Aircraft.State.DEAD
	_settle()
	check(world.mission_over and world._end_result == "defence", "Brenner lost fails mission 2")


# ---------------------------------------------------------------- mission 8: Wounded

func _m08_wound() -> void:
	var p := world.player
	var fe: Aircraft = s().plane(3010)
	check(fe.get("gunners_enabled") == true, "F.E.2d stand-ins have gunners")
	check(absf(fe.fire_rate * fe.fire_on / (fe.fire_on + fe.fire_off) - 7.8) < 0.1, "F.E.2d front gun 7.8 rounds/s")
	check(not fe.retaliate, "F.E.2ds hold course (retaliate off)")
	check(MS.distance(fe, Vector3(6200, 0, 7450), true) > 2500.0, "F.E.2ds start far from the aerodrome")
	var route := 0.0
	var from := fe.global_position
	var near_base := INF
	for g in fe.goals:
		if g.type == Aircraft.G_WAYPOINT:
			var to: Vector3 = g.pos
			to.x = minf(to.x, world.map_bounds.end.x + 150.0)
			route += Vector2(to.x - from.x, to.z - from.z).length()
			near_base = minf(near_base, MS.distance(g.pos, Vector3(6200, 0, 7450), true))
			from = to
	check(route / fe.high_speed > 75.0, "F.E.2d route about %.0f s to the map edge (60+ after interception)" % (route / fe.high_speed))
	check(near_base > 1550.0, "F.E.2d route stays 1550+ from the aerodrome (%.0f)" % near_base)
	check(p.ordnance_type == 2 and p.ordnance_left == 10, "the Baron carries 10 rockets")
	check(fe.goals.back().pos.x > 9358.0, "F.E.2ds head off the map east")
	check(s().plane(3020).hidden and s().plane(3021).hidden, "ambush hidden")
	check(s().plane(3002).current_goal().type == Aircraft.G_FORMATION, "Brenner in formation (retaliate before 0x30)")
	check(world.message_label.text.begins_with("F.E.2ds over our lines"), "first objective on the HUD")
	check(s().overlay()._counter != null and s().overlay()._counter.text.begins_with("F.E.2d down 0 / 4"), "kill counter")
	# hits do not wound any more: the ambush does
	world.mission_time = 31.0
	fe.global_position = p.global_position + Vector3(100, 0, 0)
	p.take_damage(1.0, fe)
	check(not s().wounded, "an observer hit does not wound")
	# all four down
	p.global_position = Vector3(8600, 650, 8400)
	for f in s().fe2ds:
		f.state = Aircraft.State.DEAD
	world.mission_time = 40.0
	_settle()
	check(s().returning and world.message_label.text == "The F.E.2d flight is destroyed. Well done! Return to base.",
		"success line and return to base when all are down")
	check(not s().overlay()._counter.visible, "counter hidden on the way home")
	check(s().plane(3002).current_goal().type == Aircraft.G_FORMATION, "Brenner on the Baron's wing on the way home")
	# halfway home: the ambush is seen coming, then the first hit wounds
	var home := Vector3(6200, 650, 7450)
	var start := p.global_position
	world.mission_time = 50.0
	p.global_position = start.lerp(home, 0.3)
	_settle()
	check(not s().ambushed, "no ambush before halfway")
	p.global_position = start.lerp(home, 0.6)
	_settle()
	check(s().ambushed and not s().wounded, "ambush halfway home, not yet wounded")
	check(not s().plane(3020).hidden and not s().plane(3021).hidden, "two Nieuports revealed")
	var appear: Vector3 = s().plane(3020).current_goal().pos
	check(s().plane(3020).current_goal().type == Aircraft.G_APPEAR and MS.distance(appear, p) > 400.0 and appear.y > p.global_position.y + 150.0,
		"they appear far behind and above (%.0f), to be seen coming" % MS.distance(appear, p))
	check(world.message_label.text == "Scouts diving behind us!", "HUD warns of the scouts")
	check(world.map_markers.filter(func(m): return m.get("follow") in [s().plane(3020), s().plane(3021)]).size() == 2, "ambushers highlighted on the minimap")
	check(s().plane(3002).current_goal().type == Aircraft.G_ATTACK and s().plane(3002).current_goal().targetid == 3020
		and s().plane(3002).goals[1].targetid == 3021, "Brenner turns to engage the first, then the second")
	var second: Aircraft = s().plane(3021)
	check(second.goals[1].type == Aircraft.G_RETALIATE_ON and second.goals[1].radius == 20.0 and second.goals.back().pos.x > 9358.0,
		"the second attacks 20 s, then turns for home")
	check(s().plane(3002).goals.back().type == Aircraft.G_FORMATION and s().plane(3002).goals.back().has("offset"),
		"Brenner forms up again afterwards")
	check(world.map_markers.any(func(m): return m.icon == MS.AERODROME_ICON), "aerodrome still marked")
	# their first hit is the wound
	p.take_damage(1.0, s().plane(3020))
	check(s().wounded, "the first ambusher hit wounds the Baron")
	check(p.health >= p.endurance * 0.5 and p.get("damage_scale") == 0.25, "wounded: at least half endurance, quarter damage")
	var before := p.health
	p.take_damage(8.0, s().plane(3021))
	check(is_equal_approx(p.health, before - 2.0), "a hit after the wound does a quarter")
	check(s().overlay()._jolt > 0.0, "the hit jolts the view")
	world.mission_time += 0.5
	s().run_step(0.0)
	check(s().overlay().wound == 1.0 and world.message_label.text == "You are hit. Land at the aerodrome.",
		"then the impaired view and the order to land")
	p.throttle = 1.0
	p.fire_input = true
	s().run_step(0.0)
	check(p.throttle <= 0.5 and not p.fire_input, "wound: half throttle, no guns")


func _m08_land() -> void:
	var p := world.player
	check(not world.mission_over, "still flying after the wound")
	p.global_position = Vector3(6900, 380, 7450)
	p.state = Aircraft.State.GROUND
	_settle()
	check(not world.mission_over, "landing away from the aerodrome does not win")
	p.global_position = Vector3(5995, 380, 7755)
	_settle()
	check(world.mission_over and world._end_result == "won", "landing at the far end of the strip wins (390 from the marker)")


func _m08_crash() -> void:
	s().ambush()
	world.player.crash()
	_settle()
	check(world.mission_over and world._end_result == "death", "a crash loses mission 8")


# ---------------------------------------------------------------- campaign wiring

func _page_text(path: String) -> String:
	return FileAccess.get_file_as_string(Ini.data_path("language/english/" + path.to_lower().replace("\\", "/")))


func _check_campaign_menus() -> void:
	var list := World.ModLauncher.campaigns()
	check(list.size() == 1 and list[0].id == "redbaron", "launcher finds the campaign manifest")
	var c: Dictionary = list[0]
	check(c.missions.has(102) and c.missions.has(108) and c.ranks[0] == "Leutnant" and c.ranks[2] == "Rittmeister",
		"manifest missions and ranks")
	var game := TestGame.new()
	root.add_child(game)
	game.strings = {}
	var stock := {"name": "Hans Pilot", "mission": 7, "score": 2000, "rank": 2}
	game.pilots.assign([stock.duplicate(), {}, {}, {}, {}, {}])
	game.current = 0
	game._campaign_list()[0].missions.assign([102, 108])  # the flow below: a two-mission campaign
	var bonus := game._fill(_page_text("Menus\\bonus.html"))
	check(bonus.contains("campaign:redbaron") and bonus.contains("Der Rote Kampfflieger"), "Bonus Missions lists the campaign")
	check(bonus.contains("missions\\26\\mission.html"), "Battle of Britain still listed")
	game._on_link("campaign:redbaron")
	check(game._campaign_id == "redbaron" and game.opened.back() == "campaigns\\redbaron\\intro.html", "campaign link opens the intro")
	game._page = "campaigns\\redbaron\\intro.html"
	var intro := game._fill(_page_text(game._page))
	check(intro.contains("Start Campaign") and intro.contains("Leutnant Hans Pilot"), "intro: Start Campaign, campaign rank")
	# Replay Missions (replayall = 1 while the campaign is built: every mission)
	check(intro.contains("Replay Missions") and intro.contains("campaigns\\redbaron\\replay.html"), "intro links Replay Missions")
	game._on_link("campaigns\\redbaron\\replay.html")
	check(game.opened.back() == "campaigns\\redbaron\\replay.html", "Replay Missions page opens")
	var replay := game._fill(_page_text("campaigns\\redbaron\\replay.html"))
	check(replay.contains("First Sortie") and replay.contains("Wounded") and replay.contains("missions\\108\\mission.html"),
		"replay lists missions by title")
	game._active_campaign().replayall = false
	check(game._campaign_replayable(game.pilots[0]) == [102], "without replayall: only reached missions")
	game._active_campaign().replayall = true
	game._on_link("missions\\108\\mission.html")
	check(not game._campaign and game._campaign_id == "redbaron" and game.opened.back() == "missions\\108\\mission.html",
		"replayed mission flies outside the campaign")
	game._on_link("campaign:redbaron")
	game._on_link("command:continue")
	check(game.opened.back() == "missions\\102\\mission.html" and game._campaign and game._mission == 102, "Start briefs the first mission")
	game._page = "missions\\102\\mission.html"
	var brief := game._fill(_page_text(game._page))
	check(brief.contains("campaign:redbaron") and brief.contains("play:102"), "briefing links")
	# win mission 2 (score 600): no promotion yet
	game._flown = 102
	game._on_finished("won", 600)
	var prog: Dictionary = game.pilots[0].campaigns.redbaron
	check(prog.won == [102] and prog.score == 600 and prog.rank == 0, "win recorded in the campaign's own progress")
	check(game.opened.back() == "Menus\\victory.html", "victory page")
	game._page = "Menus\\victory.html"
	check(game._fill(_page_text("Menus\\victory.html")).contains("missions\\102\\debrief.html"), "victory leads to the mission's debriefing")
	var debrief := game._fill(_page_text("missions\\102\\debrief.html"))
	check(debrief.contains("You brought Brenner home") and not debrief.contains("promoted"), "debriefing text, no promotion yet")
	check(int(game.pilots[0].mission) == 7 and int(game.pilots[0].score) == 2000 and int(game.pilots[0].rank) == 2,
		"original campaign progress untouched")
	game._page = "Menus\\victorybrief.html"
	game._on_link("command:continue")
	check(game.opened.back() == "missions\\108\\mission.html", "continue briefs the next mission")
	# a loss, then a retry from the failed page
	game._on_finished("death", 0)
	check(game.opened.back() == "Menus\\defeat.html" and prog.won == [102], "loss records nothing")
	game._page = "Menus\\faileddeath.html"
	game._on_link("command:continue")
	check(game.opened.back() == "missions\\108\\mission.html", "failed page returns to the briefing")
	# win mission 8 (600 more = 1200): promoted to Oberleutnant, campaign (so far) complete
	game._on_finished("won", 600)
	check(prog.rank == 1 and prog.won == [102, 108], "promotion at 1000")
	check(game.opened.back() == "Menus\\victory.html", "last mission: victory, then its debriefing")
	game._page = "missions\\108\\debrief.html"
	game._on_link("command:continue")
	check(game.opened.back() == "campaigns\\redbaron\\complete.html", "Next Mission after the last debriefing: completion page")
	check(game._debrief_page(5) == "" and game._debrief_page(26) == "", "original missions keep the generic victory message")
	game._flown = 108
	check(game._fill(_page_text("missions\\108\\debrief.html")).contains("promoted to the rank of Oberleutnant"),
		"the debriefing names the promotion")
	game._page = "Menus\\promotionbrief.html"
	check(game._fill(_page_text(game._page)).contains("Oberleutnant"), "promotion page names the campaign rank")
	# back in the original menus everything is stock again
	game._on_link("Menus\\play.html")
	check(game._campaign_id == "", "original menus leave the mod campaign")
	game._page = "Menus\\play.html"
	var play := game._fill(_page_text("Menus\\play.html"))
	check(play.contains("Sergeant Major") and play.contains("Mission: 7"), "play page shows the original campaign")
	# a mission added to the manifest later does not move progress
	c.missions.push_front(101)
	game._campaign_list()[0].missions.push_front(101)
	game._campaign_id = "redbaron"
	check(game._next_campaign_mission(game.pilots[0], game._active_campaign()) == 101, "new earlier mission comes next")
	game.queue_free()


func _m08_escape() -> void:
	s().fe2ds[0].state = Aircraft.State.DEAD
	s().fe2ds[3].left_map = true
	_settle()
	check(world.mission_over and world._end_result == "escaped" and world._end_label.text == "An F.E.2d Got Away",
		"one F.E.2d leaving the map fails mission 8")
	var game := TestGame.new()
	root.add_child(game)
	game.pilots.assign([{"name": "Hans Pilot", "mission": 1}, {}, {}, {}, {}, {}])
	game.current = 0
	game._flown = 108
	game._result = "escaped"
	check(game._fill("^defeaturl^") == "missions\\108\\failed_escaped.html", "defeat page leads to the mission's own failure message")
	game._result = "death"
	check(game._fill("^defeaturl^") == "Menus\\faileddeath.html", "other results keep the original failure messages")
	game._flown = 5
	game._result = "escaped"
	check(game._fill("^defeaturl^") == "Menus\\faileddeath.html", "original missions have no own failure pages")
	game.queue_free()


# ---------------------------------------------------------------- missions on the original rules (Phase 4)

## [id, player plane, {group: percent}, timelimit, escaping plane id or 0, counter group or -1]
const STOCK_RULE := [
	[101, "albatros_player", {7: -100.0}, 300.0, 3002, -1],
	[103, "albatros_red", {7: -100.0}, 240.0, 0, 7],
	[104, "albatros_red", {3: 60.0, 7: -100.0}, 0.0, 0, 7],
	[105, "albatros_red", {7: -100.0}, 0.0, 3010, -1],
	[106, "albatros_red", {7: -100.0}, 0.0, 0, 7],
	[110, "fokker_red", {7: -75.0}, 300.0, 0, 7],
	[109, "albatros_red", {3: 60.0, 7: -100.0}, 0.0, 0, 7],
]


## Three stages per mission: load; check and win; reload; lose (death, time, defence or escape).
func _stock_rule_mission(i: int) -> void:
	var spec: Array = STOCK_RULE[i / 3]
	var id: int = spec[0]
	match i % 3:
		0:
			world.load_mission(id)
		1:
			check(world._mod is RedBaronInit and s().get_script() in [ObjectiveScript, preload("res://mods/redbaron/missions/m01.gd"), preload("res://mods/redbaron/missions/m05.gd"), preload("res://mods/redbaron/missions/m06.gd"), preload("res://mods/redbaron/missions/m09.gd"), preload("res://mods/redbaron/missions/m10.gd")], "%d: objective script" % id)
			if id == 105:
				var e: Aircraft = s().plane(3020)
				check(e.current_goal().type == Aircraft.G_FORMATION, "105: escorts in formation on the recon plane")
				world.player.global_position = s().recon.global_position + Vector3(0, 0, -500)
				s()._check = 0.0
				s().run_step(0.0)
				check(e.current_goal().type == Aircraft.G_ATTACK and e.current_goal().targetid == 3001
					and s().plane(3021).current_goal().targetid == 3001, "105: escorts turn on the Baron when he engages")
				world.player.global_position = s().recon.global_position + Vector3(0, 0, -2000)
				s()._check = 0.0
				s().run_step(0.0)
				check(e.current_goal().type == Aircraft.G_FORMATION and e.current_goal().has("offset"), "105: back in formation when he falls back")
			if id == 103:
				var sp: Aircraft = s().plane(3010)
				check(sp.get("_damage_paths").size() == 3, "103: RE8 has damage stages")
				sp.take_damage(sp.endurance * 0.4, world.player)
				check(sp.get("_damage_stage") == 1, "103: RE8 shows its first damage stage at 40 %")
				sp.health = sp.endurance
			if id == 109:
				check(world.message_label.text == "Bombers approaching from the northeast. Fighters ahead of them!", "109: warning at the start")
				var hp: Array = world.planes.filter(func(q): return q.plane_name == "handleypage")
				check(hp.size() == 3 and hp.all(func(q): return q.get("_stations").size() == 3), "109: O/100s with nose, dorsal and ventral gunners")
				check(world.planes.filter(func(q): return q.plane_name == "sopwithcamel_rb" and q.current_goal().type == Aircraft.G_FORMATION).size() == 5, "109: five escorts in formation")
				check(s().plane(3002).allied and s().plane(3003).allied, "109: two wingmen")
				var leads := world.planes.filter(func(q): return q.plane_name == "sopwithcamel_rb").map(func(q): return int(q.goals.back().targetid))
				leads.sort()
				check(leads == [3010, 3010, 3010, 3011, 3012], "109: one close escort per bomber, two sweeping ahead of the lead (%s)" % [leads])
				check(world.planes.filter(func(q): return q.plane_name == "sopwithcamel_rb").all(func(q): return q.get("keep_station")), "109: escorts keep station")
				var spread := INF
				for i2 in hp.size():
					for j2 in range(i2 + 1, hp.size()):
						spread = minf(spread, hp[i2].global_position.distance_to(hp[j2].global_position))
				check(spread > 400.0, "109: bombers well apart (%.0f)" % spread)
				var b: Aircraft = hp[0]
				b.global_position = Vector3(8000, 800, 6500)
				world.player.global_position = b.global_position + Vector3(0, 0, -400)
				s()._check = 0.0
				s().run_step(0.0)
				var esc: Array = world.planes.filter(func(q): return q.plane_name == "sopwithcamel_rb" and q.get("_formation") == null)
				check(world.planes.filter(func(q): return q.plane_name == "sopwithcamel_rb" and q.current_goal().type == Aircraft.G_ATTACK).size() >= 2, "109: escorts of a threatened bomber turn on the German")
			if id == 106:
				var bal: Array = world.targets.filter(func(x): return x.name == "balloon")
				check(bal.size() == 3 and bal.all(func(x): return x.models.size() == 3), "106: balloons with two damage stages")

				var cl := world.planes.filter(func(q): return q.plane_name == "halberstadt_rb")
				var armed := cl.size() == 3
				var assigned := 0
				var rings := {}
				for q in cl:
					var guns: Array = s().BOMBERS[q.object_id].guns
					assigned += guns.size()
					rings[s().BOMBERS[q.object_id].ring] = true
					armed = armed and q.ordnance_type == 1 and q.ordnance_left == 20 and q.goals.any(func(g): return g.type == Aircraft.G_BOMB_RUN and g.targetid == guns[0])
				check(armed, "106: three Halberstadts bombing their own AA guns")
				var guns_total := world.targets.filter(func(x): return x.name == "aagun_rapid").size()
				check(rings.size() == 3 and assigned * 2 >= guns_total - 1 and assigned * 2 <= guns_total + 1,
					"106: about half the guns (%d of %d) assigned, across all three rings" % [assigned, guns_total])
				check(s().extra_lines()[0].begins_with("Guns silenced   West 0/5"), "106: silenced guns per ring on the HUD")
				# the West bomber's guns silenced: it turns for home (off the north edge), the others carry on
				for gid in s().BOMBERS[3030].guns:
					s().object(gid).dead = true
				s().run_step(0.0)
				var west: Aircraft = s().plane(3030)
				check(west.current_goal().type == Aircraft.G_WAYPOINT and west.current_goal().pos.z < world.map_bounds.position.y,
					"106: a Halberstadt done with its guns withdraws north")
				check(world.map_markers.filter(func(m): return m.icon == MS.SILENCED_ICON).size() == 3, "106: silenced guns marked on the minimap")
				check(not s()._announced, "106: no 'complete' line while bombers are still at work")
				# the others time out on their guns (they move on, then withdraw)
				for k in 8:
					world.mission_time += 40.0
					s().run_step(0.0)
				check(s()._announced and world.message_label.text == s().COMPLETE_TEXT, "106: bombing run complete line")
				check(world.targets.filter(func(x): return x.name == "aagun_rapid" and not x.dead).size() >= 5, "106: guns outside the assignments stay active")
				world.mission_time = 0.0
			if id == 101:
				var hk: Aircraft = s().plane(3002)
				check(hk.high_speed < world.player.high_speed and hk.high_roll > world.player.high_roll, "101: Hawker out-turns the Albatros but is slower")
				var flat := hk.global_position - world.player.global_position
				flat.y = 0.0
				var fwd := Vector3(world.player.flight_basis.z.x, 0, world.player.flight_basis.z.z).normalized()
				check(absf(fwd.dot(flat.normalized())) < 0.95 and hk.global_position.y >= world.player.global_position.y,
					"101: Hawker offset from the Baron's path, as high or higher (not head-on)")
				check(hk.goals.any(func(g): return g.type == Aircraft.G_WAYPOINT), "101: Hawker opens by crossing the Baron's track, then attacks")
				# the Baron settles on his tail: he breaks, then cannot break again for the recovery time
				MS.attack(hk, world.player)
				world.player.flight_basis = hk.flight_basis
				world.player.global_position = hk.global_position - hk.flight_basis.z * 150.0
				for k in 16:
					s().run_step(0.1)
				check(hk.current_goal().type == Aircraft.G_EVADE, "101: Hawker breaks when the Baron settles behind him")
				hk._remove_goal(hk.current_goal())
				for k in 16:
					s().run_step(0.1)
				check(hk.current_goal().type != Aircraft.G_EVADE, "101: recovery time between breaks")
				world.mission_time = 201.0
				s().run_step(0.0)
				check(s().retreating and hk.goals.back().type == Aircraft.G_WAYPOINT and hk.goals.back().pos.z > world.map_bounds.end.y
					and world.message_label.text.begins_with("Hawker breaks away"), "101: retreat phase with its own line")
				world.mission_time = 0.0
			if id == 104:
				check(s().overlay()._counter.text.contains("Hangars standing 6 / 6  (fails at 3 lost)"), "104: protected buildings counted on the HUD")
				check(world.map_markers.filter(func(m): return m.icon == MS.PROTECT_ICON).size() == 6, "104: protected buildings marked")
				check(world.planes.filter(func(q): return q.plane_name == "re8").all(func(q): return q.groups & (1 << 7)), "104: the bombers are the objective")
			if id == 109:
				var rails := world.targets.filter(func(x): return x.name == "rail")
				check(rails.size() > 60, "109: railway laid (%d segments)" % rails.size())
				var off := 0
				var worst := 0.0
				for x in rails:
					var c: Vector3 = x.node.global_position
					var half: Vector3 = x.node.global_transform.basis.z * s().RAIL_HALF
					for q in [c - half, c + half]:
						worst = maxf(worst, absf(q.y - world.ground_height(q)))
						if absf(q.y - world.ground_height(q)) > 1.5:
							off += 1
					if c.y < world.ground_height(c) - 2.5:  # a sharp hump over 1.2 may show through (lift capped)
						off += 1
				check(off == 0, "109: rails lie on the terrain, ends on the ground (%d off, worst %.1f)" % [off, worst])
				check(world.targets.filter(func(x): return x.groups & (1 << 3)).all(func(x): return x.node.global_position.y > 100.0), "109: yard buildings on the terrain")
				var clash := 0
				for o in world.targets:
					if o.name in ["rail", "van", "station", "factory", "warehouse"] or o.dead:
						continue
					var op: Vector3 = o.node.global_position
					for x in rails:
						var c2: Vector3 = x.node.global_position
						var h2: Vector3 = x.node.global_transform.basis.z * s().RAIL_HALF
						var cp := Geometry2D.get_closest_point_to_segment(Vector2(op.x, op.z), Vector2(c2.x - h2.x, c2.z - h2.z), Vector2(c2.x + h2.x, c2.z + h2.z))
						if cp.distance_to(Vector2(op.x, op.z)) < 20.0:
							clash += 1
							break
				check(clash == 0, "109: no trees, houses or guns on the railway (%d)" % clash)
				check(s().overlay()._counter.text.contains("Rail yard standing 6 / 6"), "109: yard losses on the HUD")
			if id == 110:
				check(world.message_label.text.begins_with("Destroy six of the eight tanks"), "110: objective stated directly")
				check(s().overlay()._counter.text.contains("(need 6)"), "110: counter shows six needed")
				world.mission_time = 101.0
				s().run_step(0.0)
				check(s().plane(3024).present() and s().plane(3025).present(), "110: second Camel pair for the wingmen")
				world.mission_time = 0.0
			if id == 104:
				for id2 in [3002, 3003]:
					var b: Aircraft = s().plane(id2)
					check(b.state != Aircraft.State.GROUND and b.goals.any(func(g): return g.type == Aircraft.G_ATTACK and g.targetid == -9),
						"104: wingman %d in the air, after the raiders" % id2)
				check(world.player.state == Aircraft.State.GROUND, "104: the Baron starts on the field")
				var wave1 := world.planes.filter(func(q): return q.object_id >= 3010 and q.object_id <= 3016)
				var wave2 := world.planes.filter(func(q): return q.object_id >= 3020 and q.object_id <= 3026)
				check(wave1.size() == 7 and wave1.filter(func(q): return q.plane_name == "re8").size() == 4, "104: wave of 4 bombers + 3 fighters")
				check(wave1.filter(func(q): return q.plane_name == "re8").all(func(q): return q.ordnance_left == 1 and q.goals.any(func(g): return g.type == Aircraft.G_BOMB_RUN)),
					"104: bombers carry a bomb and fly a bombing run")
				var home := Vector3(6200, 0, 7450)
				var bombers := wave1.filter(func(q): return q.plane_name == "re8")
				var route: float = MS.distance(bombers[0], Vector3(9100, 0, 7250), true) + MS.distance(Vector3(9100, 0, 7250), home, true)
				check(route > 5000.0, "104: bombers about 60 s out (route %.0f)" % route)
				var ahead := true
				for q in wave1:
					if q.plane_name == "se5a_rb":
						var d := MS.distance(q, home, true)
						ahead = ahead and d < route - 2000.0 and d > 2500.0
				check(ahead, "104: fighters well ahead, about 30 s out")
				check(wave2.is_empty() and world.planes.filter(func(q): return q.groups & (1 << 9)).size() == 7, "104: one wave of seven raiders")
			check(world.player.plane_name == spec[1], "%d: player flies %s" % [id, spec[1]])
			if id != 101 and id != 103:
				var rockets := 30 if id == 110 else 10
				check(world.player.ordnance_type == 2 and world.player.ordnance_left == rockets, "%d: %d rockets" % [id, rockets])
			if id == 110:
				for id2 in [3002, 3003]:
					var wing: Aircraft = s().plane(id2)
					var own := wing.goals.filter(func(g): return g.type == Aircraft.G_ATTACK and int(g.targetid) in [3020, 3021, 3022, 3023])
					check(wing and wing.allied and not own.is_empty(), "110: wingman %d on his own Camel" % id2)
			check(world.planes.filter(func(q): return q.call("is_persistent")).all(func(q): return id == 104 and q.plane_name == "re8"),
				"%d: original AI behaviour (only Scramble's bombers persistent)" % id)
			var groups := {}
			for r in world.rules:
				groups[int(r.group)] = float(r.percent)
				check(r.total > 0, "%d: rule group %d has members" % [id, r.group])
			check(groups == spec[2], "%d: rules %s" % [id, groups])
			check(is_equal_approx(world.time_limit, spec[3]), "%d: time limit %.0f" % [id, spec[3]])
			check(world.message_label.text != "", "%d: intro line on the HUD" % id)
			if world.map_bounds.size.x < 5000.0:  # country: behind German lines, nothing bombed
				check(world.targets.all(func(x): return not ("burn" in x.name or "wreck" in x.name or "ruin" in x.name)),
					"%d: no bombed buildings or burnt trees on the country map" % id)
			var targets := world.planes.filter(func(p): return p.groups & (1 << 7))
			for p in targets:
				check(world.map_markers.any(func(m): return m.icon == "smalltarget" and MS.near(m.pos, p, 20.0)),
					"%d: target plane %d marked on the minimap" % [id, p.object_id])
			if spec[5] >= 0:
				check(s().overlay()._counter != null and s().overlay()._counter.visible, "%d: HUD counter" % id)
			for r in world.rules:
				check(r.lost == 0, "%d: nothing lost at the start (hidden planes are not lost)" % id)
			for p in world.planes:
				var key := "fokker_rookie" if p.plane_name.begins_with("fokker_rookie") else p.plane_name
				if RATES.has(key):
					check(absf(p.fire_rate * p.fire_on / (p.fire_on + p.fire_off) - RATES[key]) < 0.05,
						"%d: %s guns %.2f rounds/s" % [id, p.plane_name, p.fire_rate * p.fire_on / (p.fire_on + p.fire_off)])
				check(not p.plane_name in ["sopwithcamel", "se5a", "nieuport17", "bristolscout", "aircodh2", "halberstadt"],
					"%d: %s is the mod's copy (stock figures untouched)" % [id, p.plane_name])
			# win: every member of every destroy group lost
			for p in world.planes:
				for r in world.rules:
					if r.percent < 0.0 and p.groups & (1 << int(r.group)):
						p.state = Aircraft.State.DEAD
			for t in world.targets:
				for r in world.rules:
					if r.percent < 0.0 and int(t.groups) & (1 << int(r.group)):
						t.dead = true
			world._count_rule_members()
			world._check_rules()
			check(world.mission_over and world._end_result == "won", "%d: destroying the targets wins" % id)
		2:
			world.load_mission(id)
			await physics_frame
			await physics_frame
			if spec[4] > 0:
				s().plane(spec[4]).left_map = true
				_settle()
				check(world.mission_over and world._end_result == "escaped", "%d: escape fails" % id)
				check(FileAccess.file_exists(Ini.data_path("language/english/missions/%d/failed_escaped.html" % id)), "%d: own failure page" % id)
			elif spec[3] > 0.0:
				world.mission_time = spec[3] + 1.0
				_settle()
				check(world.mission_over and world._end_result == "time", "%d: out of time fails" % id)
			elif spec[2].has(3):
				for t in world.targets:
					if int(t.groups) & (1 << 3):
						t.dead = true
				_settle()
				check(world.mission_over and world._end_result == "defence", "%d: losing the hangars fails" % id)
			else:
				world.player.state = Aircraft.State.DEAD
				_settle()
				check(world.mission_over and world._end_result == "death", "%d: plane destroyed fails" % id)
			check(FileAccess.file_exists(Ini.data_path("language/english/missions/%d/debrief.html" % id)), "%d: debriefing" % id)


# ---------------------------------------------------------------- missions 7, 11, 12 (Phase 6)

func _m07() -> void:
	var photo: Aircraft = s().plane(3002)
	check(photo.plane_name == "halberstadt_rb" and photo.get("gunners_enabled") and not photo.retaliate, "107: photo plane, gunners, holds course")
	check(world.planes.filter(func(q): return q.plane_name == "sopwithcamel_rb").all(func(q): return q.hidden), "107: Camels hidden until it is over their side")
	photo.global_position = Vector3(8400, 400, 7750)
	_settle()
	check(not world.mission_over, "107: no win before the photo run")
	photo.global_position = Vector3(10300, 450, 12000)
	_settle()
	check(s().photographed and world.message_label.text.begins_with("Photographs taken"), "107: photo run done")
	photo.global_position = Vector3(8400, 400, 7750)
	_settle()
	check(world.mission_over and world._end_result == "won", "107: home with the photographs wins")
	check(FileAccess.file_exists(Ini.data_path("language/english/missions/107/failed_defence.html")), "107: own failure page")


func _m11() -> void:
	var p := world.player
	var brenner: Aircraft = s().plane(3002)
	var hw: Aircraft = s().plane(3003)
	var ts: Aircraft = s().plane(3004)
	var at := func(dt: float) -> void:
		world.mission_time += dt
		_settle()
	check(brenner.current_goal().type == Aircraft.G_FORMATION and brenner.current_goal().targetid == 3004
		and hw.current_goal().targetid == 3004, "111: Brenner and Hartwig escort the two-seater")
	check(brenner.call("keeps_station") and hw.call("keeps_station") and not s().plane(3010).call("keeps_station"),
		"111: the Dr.I wingmen keep station in formation (no zig-zag); the Camels fly the original formation")
	check(is_equal_approx(ts.health, ts.endurance * 0.7) and ts.get("damage_scale") == s().TWO_SEATER_SCALE, "111: the two-seater starts damaged (70 %)")
	check(s().overlay()._counter.text.begins_with("Two-seater 70 %") and world.message_label.text.begins_with("Join the damaged two-seater"),
		"111: opening line, two-seater condition on the HUD")
	check(world.map_markers.any(func(m): return m.icon == MS.PROTECT_ICON) and world.map_markers.any(func(m): return m.icon == MS.AERODROME_ICON),
		"111: two-seater and aerodrome marked")
	check(world.planes.filter(func(q): return q.groups & (1 << 9)).size() == 10, "111: ten enemy aircraft")
	for q in [p, brenner, hw, ts]:
		var over: float = q.global_position.y - world.ground_height(q.global_position)
		check(over < 400.0, "111: %d starts below the ceiling (%.0f over the ground)" % [q.object_id, over])
	check(not s().overlay().SHOW_BRACKETS, "brackets and labels are off in the view (minimap only)")
	at.call(26.0)
	check(s().stage == "e1" and not s().plane(3010).hidden and brenner.current_goal().targetid == 3010
		and hw.current_goal().type == Aircraft.G_FORMATION, "111: encounter 1, Brenner takes one, Hartwig stays on the two-seater")
	var appear: Vector3 = s().plane(3010).current_goal().pos
	check(MS.distance(appear, ts) > 700.0, "111: the pursuers appear well out (%.0f)" % MS.distance(appear, ts))
	for id in s().W1:
		s().plane(id).state = Aircraft.State.DEAD
	at.call(7.0)
	check(s().stage == "after_e1" and world.message_label.text == "First attack broken. Stay with the two-seater.", "111: first attack broken")
	at.call(s().SAFEGUARD + 1.0)
	check(s().stage == "e2" and world.message_label.text.begins_with("Scouts ahead!"), "111: encounter 2 (safeguard timer)")
	check(brenner.current_goal().targetid == s().W2[0] and hw.current_goal().targetid == s().W2[0], "111: Brenner and Hartwig take the high scout")
	check(s().plane(s().W2[1]).goals.any(func(g): return g.type == Aircraft.G_ATTACK and g.targetid == 3004), "111: the low pair go for the two-seater")
	check(not s()._tracked.has(s().plane(s().W2[1])) and not s()._tracked.has(s().plane(s().W2[2])), "111: the low pair are not marked apart")
	for id in [s().W2[1], s().W2[2]]:
		s().plane(id).state = Aircraft.State.DEAD
	at.call(7.0)
	check(s().stage == "after_e2" and world.message_label.text == "The way is clear. Bring them through.", "111: the way is clear")
	at.call(s().SAFEGUARD + 1.0)
	check(s().stage == "e3" and world.message_label.text.begins_with("Another flight coming in!"), "111: encounter 3")
	at.call(s().COVER_AFTER + 0.5)
	check(s().stage == "cover" and world.message_label.text.begins_with("Brenner is covering the rear"), "111: Brenner covers the rear")
	p.global_position = brenner.global_position + Vector3(0, 0, -150)
	_settle()
	check(alive_plane(brenner), "111: Brenner's death is not set off by the Baron coming close")
	at.call(s().STORY_AFTER + 0.5)
	check(s().stage == "story" and s()._cine_cam != null and s()._cine_cam.current and p.autopilot and s().overlay()._bars[0].visible,
		"111: the story moment: camera cut-in, letterbox, the Baron on autopilot")
	check(s().overlay()._caption.text == "" and s()._cine_target == brenner, "111: over Brenner's shoulder, no caption yet")
	at.call(s().STORY_KILL_CAMEL + 0.5)
	check(alive_plane(brenner) and not alive_plane(s().plane(s().W3[2])), "111: Brenner shoots down the Camel on Hartwig")
	at.call(s().STORY_SECOND_SHOT - s().STORY_KILL_CAMEL)
	check(s()._cine_target == s().plane(s().W3[1]) and s()._cine_quarry == brenner, "111: the shot moves to the Camel behind Brenner")
	check(s()._cine_target.global_position.distance_to(brenner.global_position) < 400.0, "111: that Camel is close behind him")
	at.call(s().STORY_KILL_BRENNER - s().STORY_SECOND_SHOT)
	check(brenner.state == Aircraft.State.DEAD and s().overlay()._caption.text == "", "111: Brenner falls (scripted), still no caption")
	at.call(s().STORY_CAPTION - s().STORY_KILL_BRENNER)
	check(s().overlay()._caption.text == s().STORY_LINE and s()._cine_cam != null, "111: one caption, while the cut-in runs on")
	var msg_before: String = world.message_label.text
	at.call(s().STORY_END - s().STORY_CAPTION)
	check(s().stage == "after_story" and s()._cine_cam == null and world.camera.current and not p.autopilot,
		"111: back to the Baron after %.0f s" % s().STORY_END)
	check(world.message_label.text == msg_before, "111: no second message after the cut-in")
	check(s().overlay()._objective.text.contains("Hartwig"), "111: objective updated")
	check(s().hartwig_protected and is_equal_approx(hw.health, hw.endurance * 0.5) and hw.get("damage_scale") == s().HARTWIG_SCALE
		and s().overlay()._counter.text.contains("Hartwig 50 %"), "111: Hartwig smoking, protected, condition on the HUD")
	at.call(26.0)
	check(s().stage == "e4", "111: encounter 4 over the approach")
	ts.global_position = Vector3(8400, 300, 7700)
	_settle()
	check(s().two_seater_home and ts.hidden and world.message_label.text == "The two-seater is down safely.", "111: two-seater lands")
	check(not world.mission_over, "111: no win before Hartwig is home")
	hw.global_position = Vector3(8350, 300, 7800)
	_settle()
	check(s().hartwig_home and hw.hidden and world.message_label.text == "Brenner's second is home.", "111: Hartwig home, announced")
	world.mission_time += 3.5
	_settle()
	check(s().stage == "home" and s().overlay()._objective.text.begins_with("Return to the aerodrome"), "111: then return to the aerodrome")
	p.global_position = Vector3(8400, 400, 8200)
	_settle()
	check(world.mission_over and world._end_result == "won", "111: the Baron at the aerodrome wins")
	var letter := FileAccess.get_file_as_string(Ini.data_path("language/english/missions/111/debrief.html"))
	check(letter.contains("<i>Madam,"), "111: the letter, in italics")
	var hv := HtmlView.new()
	var parsed: Dictionary = hv._parse("<body>plain <i>slanted</i></body>")
	check(parsed.objs.any(func(o): return o.get("text", "") == "slanted" and o.get("italic", false))
		and parsed.objs.any(func(o): return o.get("text", "") == "plain" and not o.get("italic", false)), "pages: <i> sets italics")
	hv.free()
	check(FileAccess.file_exists(Ini.data_path("language/english/missions/111/failed_second.html")), "111: failure page for losing Hartwig")


static func alive_plane(q: Aircraft) -> bool:
	return q.state != Aircraft.State.DEAD


func _m12() -> void:
	var p := world.player
	check(world.rules.size() == 1 and world.rules[0].group == 3 and world.rules[0].total == 4, "112: four rookies protected")
	for i in 4:
		s().rookies[i].left_map = true
		s().rookies[i]._set_hidden(true)
		_settle()
		if i < 3:
			check(s().phase == 1 and world.message_label.text == "%d of 4 are home." % (i + 1), "112: rookie %d home" % (i + 1))
	check(not world.mission_over and world.rules[0].lost == 0, "112: rookies off the map are saved, not lost")
	check(s().phase == 2 and world.progress_was_secured, "112: campaign completion saved on the fourth crossing")
	check(s().pursuers.all(func(c): return c.current_goal().type == Aircraft.G_ATTACK and c.current_goal().targetid == 3001), "112: pursuers turn on the Baron")
	for c in s().pursuers:
		c.state = Aircraft.State.DEAD
	_settle()
	check(s().phase == 3, "112: pursuit destroyed: the ridge")
	s().run_step(0.0)
	check(s().waves.filter(func(c): return c.present()).size() == 3, "112: a wave of three")
	world.mission_time += 41.0
	s().run_step(0.0)
	check(s().waves.filter(func(c): return c.present()).size() == 6, "112: another every 40 s")
	world.mission_time = s().phase3_at + 241.0
	_settle()
	check(p.state == Aircraft.State.DEAD, "112: ground fire after four minutes")
	_settle()
	check(world.mission_over and world._end_result == "epilogue" and world._end_label.text == "", "112: no Plane Destroyed: fade to the epilogue")
	check(world.result_page("epilogue", true) == "campaigns\\redbaron\\epilogue.html", "112: epilogue page")
	var epi := FileAccess.get_file_as_string(Ini.data_path("language/english/campaigns/redbaron/epilogue.html"))
	check(epi.contains("bgcolor=#000000") and epi.contains("To our gallant and worthy foe") and epi.contains("His young pilots reached home"), "112: epilogue text on a black page")


func _m12_rookie_lost() -> void:
	s().rookies[1].state = Aircraft.State.DEAD
	_settle()
	check(world.mission_over and world._end_result == "defence", "112: a rookie lost fails")
	check(FileAccess.file_exists(Ini.data_path("language/english/missions/112/failed_defence.html")), "112: own failure page")
