extends SceneTree
## Red Baron mod tests: godot --headless --path redace -s res://mods/redbaron/tests/test_redbaron.gd
## Phase 1: the mission script API and the generic World / Game hooks, on the fixture mission 199.

const FIXTURE := 199
const RedBaronInit := preload("res://mods/redbaron/init.gd")
const RedBaronAircraft := preload("res://mods/redbaron/aircraft.gd")
const MS := preload("res://mods/redbaron/mission_script.gd")

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
		15: _check_campaign_menus()
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
		check(absf(sustained.call(s().plane(id)) - 8.0) < 0.1, "mission 2 enemy %d fires 8 rounds/s" % id)
	check(world.player.high_speed == 110.0 and world.player.endurance == 125.0 and b.endurance == 125.0, "design stats")
	check(b.current_goal().type == Aircraft.G_FORMATION and b.current_goal().targetid == 3001, "Brenner starts on the Baron's wing")
	check(b.high_speed > world.player.high_speed, "Brenner is faster, so he can run away")
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
	check(s().broke_off and b.current_goal().type == Aircraft.G_ATTACK and b.current_goal().targetid == 3003,
		"Brenner breaks off after the decoy at 6 s")
	check(world.message_label.text.begins_with("Brenner breaks off"), "HUD says when Brenner breaks off")
	check(not s().armed and not s().rejoined, "still close: catching him does not count yet")
	b.global_position = p.global_position + Vector3(500, 0, 0)
	_settle()
	check(s().armed and not s().rejoined, "rejoin armed once Brenner has got 300 away")
	b.global_position = p.global_position + Vector3(180, 0, 0)
	_settle()
	check(s().rejoined and b.current_goal().type == Aircraft.G_FORMATION and b.current_goal().targetid == 3001,
		"Brenner rejoins in formation within 200")
	check(world.message_label.text == "Brenner joins. Return to base.", "HUD says Brenner joins, return to base")
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
	check(absf(fe.fire_rate * fe.fire_on / (fe.fire_on + fe.fire_off) - 8.0) < 0.1, "F.E.2d front gun 8 rounds/s")
	check(not fe.retaliate, "F.E.2ds hold course (retaliate off)")
	check(s().plane(3020).hidden, "pursuer hidden")
	check(s().plane(3002).current_goal().type == Aircraft.G_FORMATION, "Brenner in formation (retaliate before 0x30)")
	fe.global_position = p.global_position + Vector3(100, 0, 0)
	p.take_damage(1.0, fe)
	check(not s().wounded, "no wound in the first 30 s")
	world.mission_time = 31.0
	p.take_damage(1.0, s().plane(3002))
	check(not s().wounded, "only an F.E.2d observer wounds")
	fe.global_position = p.global_position + Vector3(400, 0, 0)
	p.take_damage(1.0, fe)
	check(not s().wounded, "observer must be within 150")
	fe.global_position = p.global_position + Vector3(100, 0, 0)
	p.take_damage(1.0, fe)
	check(s().wounded and s().overlay().wound == 1.0, "observer hit after 30 s within 150 wounds")
	check(s().plane(3020).present() and s().plane(3020).current_goal().type == Aircraft.G_APPEAR, "pursuer revealed")
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
	p.global_position = Vector3(6250, 380, 7400)
	_settle()
	check(world.mission_over and world._end_result == "won", "landing at the aerodrome wins")


func _m08_crash() -> void:
	s().wound()
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
	check(game.opened.back() == "campaigns\\redbaron\\complete.html", "last mission opens the completion page")
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
