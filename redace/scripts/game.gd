class_name Game
extends Node
## Front end and campaign like the original: HTML menu pages, pilot roster, briefings, flights,
## pause and result pages. Page flow, placeholders and commands follow the exe (decomp RedAce.c
## around 46200-51120; snippets from its strings, e.g. <a href="command:continue">%s</a>).
##   ranks (exe table at 0x51af4c) and promotion scores (0x51b1cc), campaign missions 1..25,
##   training -1, -2 and the demo mission -3 (Menus/demo.html), score per mission from World.mission_score.

const RANKS := ["Corporal", "Sergeant", "Sergeant Major", "Warrant Officer", "2nd Lieutenant", "Lieutentant",
	"Captain", "Major", "Lieutenant Colonel", "Colonel"]
# roster column (exe table at 0x51b08c)
const RANK_SHORT := ["Cpl.", "Sgt.", "Sgt. Mjr.", "WO", "2nd Lt.", "Lt.", "Cpt.", "Mjr.", "Lt Col.", "Colonel"]
const PROMOTION_SCORE := [700, 1800, 2800, 4000, 5400, 7000, 8800, 10800, 12600, 14400]
const LAST_MISSION := 25
const SLOTS := 6
const SAVE_PATH := "user://pilots.cfg"
const SETTINGS_PATH := "user://settings.cfg"
const MENU_MUSIC := 2  # music.ini entry the exe starts at the title screen (FUN_00456c75)

var view: HtmlView
var world: World
var music: AudioStreamPlayer
var strings := {}
var pilots: Array[Dictionary] = []  # {name, rank, score, mission, flights}; empty dict = free slot
var current := -1
var settings := {}
var controls: Controls
var _capture := {}  # control being redefined on the Controls page: {action, up}
var _capture_armed := false

var _page := ""
var _mission := 0  # mission being briefed / flown
var _flown := 0  # mission of the last flight (Re-Fly)
var _campaign := false  # flying the current pilot's campaign mission
var _typing_slot := -1
var _typed := ""
var _delete_slot := -1
var _result := ""
var _layer: CanvasLayer
var _title_timer: SceneTreeTimer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	strings = Ini.load_file(Ini.data_path("language/english/strings.ini")).get("strings", {})
	_setup_audio_buses()
	_load()
	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)
	view = HtmlView.new()
	view.link_clicked.connect(_on_link)
	_layer.add_child(view)
	# the exe plays Sound/MenuClick.wav for every followed link (RedAce.c:49925)
	_click = AudioStreamPlayer.new()
	_click.stream = World.load_sound("menuclick.wav")
	_click.bus = "Effects"
	add_child(_click)
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	add_child(music)
	_apply_settings()
	_apply_cursor()
	get_tree().root.size_changed.connect(_apply_cursor)
	# debug: --mission=N flies straight away (World handles its own flags)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mission="):
			_fly(int(a.get_slice("=", 1)), false, true)
			return
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('mission')")
		if q != null and str(q).is_valid_int():
			_fly(int(q), false, true)
			return
	_play_menu_music()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pages="):
			# debug: show each page for one second (screenshots of the menu renderer)
			if pilots[0].is_empty():
				pilots[0] = {"name": "Test Pilot", "rank": 2, "score": 2000, "mission": 7, "flights": 6}
				current = 0
			for pg in a.substr(8).split(","):
				open_page(pg)
				await get_tree().create_timer(1.0).timeout
			return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clicks="):
			# debug: follow links in order, 1.5 s apart (waits while a flight is running)
			if pilots[0].is_empty():
				pilots[0] = {"name": "Test Pilot", "rank": 0, "score": 600, "mission": 1, "flights": 1}
				current = 0
			for h in a.substr(9).split(","):
				await get_tree().create_timer(1.5).timeout
				if h.begins_with("key:"):
					# debug: press a key (key:esc) while flying
					var ev := InputEventKey.new()
					ev.keycode = KEY_ESCAPE if h == "key:esc" else OS.find_keycode_from_string(h.substr(4))
					ev.physical_keycode = ev.keycode
					ev.pressed = true
					Input.parse_input_event(ev)
					print("key ", h, " paused=", get_tree().paused)
					await get_tree().create_timer(0.5).timeout
					print("after key: paused=", get_tree().paused, " page=", _page)
					continue
				while world != null and not get_tree().paused:
					await get_tree().create_timer(0.5).timeout
				print("click ", h, " on ", _page)
				_on_link(h)
			return
	open_page("Menus\\titlescreen.html")
	_title_timer = get_tree().create_timer(5.0)  # titlescreen shows for 5000 ms (FUN_00456a9d)
	_title_timer.timeout.connect(_title_done)


func _title_done() -> void:
	if _page.ends_with("titlescreen.html"):
		open_page("Menus\\main.html")


# ---------------------------------------------------------------- persistence

func _load() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	pilots.clear()
	for i in SLOTS:
		pilots.append(cfg.get_value("pilots", str(i), {}))
	current = cfg.get_value("roster", "current", -1)
	var s := ConfigFile.new()
	s.load(SETTINGS_PATH)
	var cfg_ini := Ini.load_file(Ini.data_path("redace.ini"))
	controls = Controls.load_saved()
	settings.music_volume = s.get_value("sound", "music_volume", 8)
	settings.effects_volume = s.get_value("sound", "effects_volume", 10)
	settings.clip_plane = s.get_value("graphics", "clip_plane", int(Ini.num(cfg_ini.get("graphics", {}), "drawdistance", 600) / 100))
	settings.effects_detail = s.get_value("graphics", "effects_detail", int(Ini.num(cfg_ini.get("graphics", {}), "effectsdetail", 700) / 100))
	settings.vsync = s.get_value("video", "vsync", true)
	settings.fullscreen = s.get_value("video", "fullscreen", false)
	for k in ["boost", "infinite", "invulnerable"]:
		settings["cheat_" + k] = s.get_value("cheats", k, false)
	settings.game_speed = s.get_value("cheats", "game_speed", 1.0)
	settings.enemy_endurance = s.get_value("cheats", "enemy_endurance", 1.0)


func _save() -> void:
	var cfg := ConfigFile.new()
	for i in SLOTS:
		cfg.set_value("pilots", str(i), pilots[i])
	cfg.set_value("roster", "current", current)
	cfg.save(SAVE_PATH)
	var s := ConfigFile.new()
	s.load(SETTINGS_PATH)
	s.set_value("sound", "music_volume", settings.music_volume)
	s.set_value("sound", "effects_volume", settings.effects_volume)
	s.set_value("graphics", "clip_plane", settings.clip_plane)
	s.set_value("graphics", "effects_detail", settings.effects_detail)
	s.set_value("video", "vsync", settings.vsync)
	s.set_value("video", "fullscreen", settings.fullscreen)
	for k in ["boost", "infinite", "invulnerable"]:
		s.set_value("cheats", k, settings["cheat_" + k])
	s.set_value("cheats", "game_speed", settings.game_speed)
	s.set_value("cheats", "enemy_endurance", settings.enemy_endurance)
	s.save(SETTINGS_PATH)
	controls.save()


func _setup_audio_buses() -> void:
	for b in ["Music", "Effects"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), _vol_db(settings.music_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Effects"), _vol_db(settings.effects_volume))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	if not OS.has_feature("web"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)
	Engine.time_scale = settings.game_speed if settings.game_speed > 0.0 else 1.0


static func _vol_db(v: int) -> float:
	return -80.0 if v <= 0 else linear_to_db(v / 10.0)


func _play_menu_music() -> void:
	var st := World.music_stream(MENU_MUSIC)
	if st and music.stream != st:
		music.stream = st
		music.play()
	elif st and not music.playing:
		music.play()


# ---------------------------------------------------------------- pages

func open_page(path: String) -> void:
	_page = path.replace("/", "\\")
	var rel := _page.to_lower()
	var f := FileAccess.open(Ini.data_path("language/english/" + rel.replace("\\", "/")), FileAccess.READ)
	if f == null:
		push_warning("menu page missing: " + path)
		return
	view.visible = true
	var html := f.get_as_text()
	if rel.ends_with("controloptions.html"):
		html = _controls_defaults_row(html)
	view.show_html(_fill(html))


## Deviation: the exe drops the Controls page's "Set to default for" row, which does not fit its cell.
## Its label and links go into the empty Sensitivity cells of five rows instead, so they show inside
## the panel and no row moves.
func _controls_defaults_row(html: String) -> String:
	var re := RegEx.create_from_string("<font size = 2>\\s*<table>[\\s\\S]*?SET TO DEFAULT[\\s\\S]*?</table>\\s*</font>")
	var m := re.search(html)
	if m == null:
		return html
	html = html.substr(0, m.get_start()) + html.substr(m.get_end())
	var fill := {
		"fire1value": "<font face=morpheus size=1>SET TO DEFAULT</font>",
		"fire2value": "<font face=morpheus size=1>FOR:</font>",
		"camdownvalue": "<a href=\"controldefault:mousekeys.ini\">Mouse</a>",
		"cambehindvalue": "<a href=\"controldefault:joystick.ini\">Joystick</a>",
		"camleftvalue": "<a href=\"controldefault:keyboard.ini\">Keyboard</a>",
	}
	for k in fill:
		var cell := RegEx.create_from_string("(\\^%s\\^</center></a></td><td></td>\\s*)<td></td>" % k)
		# td align=center adds 2 px less than <center>, keeping the label rows at their height
		html = cell.sub(html, "$1<td align=center>%s</td>" % fill[k])
	return html


func _refresh() -> void:
	open_page(_page)


func _pilot() -> Dictionary:
	return pilots[current] if current >= 0 and current < SLOTS and not pilots[current].is_empty() else {}


func _link(href: String, text: String) -> String:
	return "<a href=\"%s\">%s</a>" % [href, text]


func _s(key: String) -> String:
	return strings.get(key, key)


## The exe's ^name^ placeholders.
func _fill(html: String) -> String:
	var p := _pilot()
	var names: PackedStringArray = str(p.get("name", "Pilot")).split(" ", false)
	var vars := {
		"playpage": _link("Menus\\play.html", _s("play")),
		"buyorgoodies": _link("Menus\\goodies.html", _s("goodies")),
		"quiturl": _link("command:quit", _s("quit")),
		"homepage": "http://www.smallrockets.com/",
		# registered copy: the exe's last writes leave "Version 1.02" and an empty second line (RedAce.c:46430)
		"version1": "Version 1.02",
		"version2": "",
		"continue": _continue_link(p),
		"fullname": str(p.get("name", "")),
		"rank": RANKS[int(p.get("rank", 0))] if not p.is_empty() else ("Pilot" if _page.to_lower().begins_with("missions") else ""),
		"sirname": names[names.size() - 1] if names.size() > 0 else "",
		"forenames": " ".join(names.slice(0, maxi(names.size() - 1, 1))) if names.size() > 0 else "",
		"mission": str(mini(int(p.get("mission", 1)), LAST_MISSION)) if not p.is_empty() else "",
		"score": str(int(p.get("score", 0))) if not p.is_empty() else "",
		"rosterinstructions": _s("typeinyourname") if _typing_slot >= 0 else _s("pilotinstructions"),
		"rosterback": _link("Menus\\play.html", _s("back")),
		"levelselector": _level_selector(),
		"cheat": _link("Menus\\cheatoptions.html", _s("cheatoptions")) if _any_completed() else "",
		"victoryurl": "Menus\\victorybrief.html",
		"defeaturl": {"death": "Menus\\faileddeath.html", "defence": "Menus\\faileddefence.html",
			"time": "Menus\\failedtime.html"}.get(_result, "Menus\\faileddeath.html"),
		"loadbar": "<img src=\"Menus\\loadbar.jpg\" width=298 height=20>",
		"rollbar": _sens_bar(1, controls.bind.roll.sensitivity),
		"pitchbar": _sens_bar(0, controls.bind.pitch.sensitivity),
		"rollsign": _check("command:reverse:roll", controls.bind.roll.reversed, true),
		"pitchsign": _check("command:reverse:pitch", controls.bind.pitch.reversed, true),
		"throttlesign": _check("command:reverse:throttle", controls.bind.throttle.reversed, true),
		"channelvol0": _bar("command:volume:0:%d", settings.music_volume, 10, 8),
		"channelvol1": _bar("command:volume:1:%d", settings.effects_volume, 10, 10),
		"musicvolbar": _bar("command:volume:0:%d", settings.music_volume, 10, 8),
		"hardwaresound": _check("command:hardwaresound", true, false),
		"clipplane": _bar("command:clipplane:%d", settings.clip_plane, 10, 6),
		"effectsdetail": _bar("command:effectsdetail:%d", settings.effects_detail, 10, 7),
		"vsync": _check("command:vsync", settings.vsync, false),
		"renderers": "<b>Godot (OpenGL / WebGL 2)</b><br>",
		"videomodes": _video_modes(),
		"boost": _check("command:cheat:boost", settings.cheat_boost, false),
		"infinite": _check("command:cheat:infinite", settings.cheat_infinite, false),
		"invulnerable": _check("command:cheat:invulnerable", settings.cheat_invulnerable, false),
		"gamespeed": _bar("command:gamespeed:%d", int(round((settings.game_speed - 0.5) * 10.0)), 10, 5),
		"enemyendurance": _bar("command:enemyendurance:%d", int(round((settings.enemy_endurance - 0.5) * 10.0)), 10, 5),
	}
	for i in SLOTS:
		var q: Dictionary = pilots[i]
		vars["rank%d" % (i + 1)] = RANK_SHORT[int(q.get("rank", 0))] if not q.is_empty() else ""
		var nm := str(q.get("name", ""))
		if i == _typing_slot:
			nm = _typed + ("_" if Time.get_ticks_msec() % 1000 < 500 else " ")
		vars["name%d" % (i + 1)] = nm
		# every slot offers Delete Pilot or New Pilot, none while a name is typed (RedAce.c:46842)
		var opt := ""
		if _typing_slot < 0:
			opt = _s("deletepilot") if not q.is_empty() else _s("create")
		vars["charopt%d" % (i + 1)] = opt
	vars.merge(_control_vars())
	var re := RegEx.create_from_string("\\^([a-z0-9]+)\\^")
	var out := ""
	var pos := 0
	for m in re.search_all(html):
		out += html.substr(pos, m.get_start() - pos)
		var k := m.get_string(1)
		out += str(vars[k]) if vars.has(k) else m.get_string(0)
		pos = m.get_end()
	return out + html.substr(pos)


func _continue_link(p: Dictionary) -> String:
	if p.is_empty():
		return ""
	if int(p.get("mission", 1)) > LAST_MISSION:
		return ""
	if int(p.get("mission", 1)) <= 1 and int(p.get("flights", 0)) == 0:
		return _link("Menus\\Intro.html", _s("startcampaign"))
	return _link("command:continue", _s("continuecampaign"))


func _level_selector() -> String:
	# replay any mission the current pilot has reached (all of them after completing the game)
	var p := _pilot()
	var top := LAST_MISSION if _any_completed() else maxi(int(p.get("mission", 1)) - 1, 0)
	var out := ""
	for m in range(1, mini(top, LAST_MISSION) + 1):
		out += "<a href=\"missions\\%d\\mission.html\">%s %d</a> <br>" % [m, _s("mission"), m]
	return out


func _any_completed() -> bool:
	for q in pilots:
		if not q.is_empty() and int(q.get("mission", 1)) > LAST_MISSION:
			return true
	return false


## Slider like the exe's: an arrow at the current step, linked bar pieces elsewhere.
func _bar(cmd: String, value: int, steps: int, default: int, small := false) -> String:
	var pre := "sm" if small else ""
	var out := ""
	for i in steps + 1:
		if i == value:
			out += "<img src=\"Menus\\%sslidearrow.jpg\">" % pre
		else:
			var img := "%sslidedefault.jpg" % pre if i == default else "%sslidebar.jpg" % pre
			out += "<a href=\"%s\"><img src=\"Menus\\%s\"></a>" % [cmd % i, img]
	return out


func _sens_bar(axis: int, value: float) -> String:
	return _bar("command:mousesensitivity:%d:%%d" % axis, int(round(value * 10.0)), 10, 5, true)


func _check(cmd: String, on: bool, small: bool) -> String:
	var pre := "sm" if small else ""
	if on:
		return "<a href=\"%s:0\"><img src=\"Menus\\%scheckon.jpg\" rolloversrc=\"Menus\\%scheckonroll.jpg\"></a>" % [cmd, pre, pre]
	return "<a href=\"%s:1\"><img src=\"Menus\\%scheckoff.jpg\" rolloversrc=\"Menus\\%scheckoffroll.jpg\"></a>" % [cmd, pre, pre]


func _video_modes() -> String:
	if OS.has_feature("web"):
		return "<b>Browser window</b><br>"
	var cur := "Fullscreen" if settings.fullscreen else "Windowed"
	var out := "<b>%s</b><br>" % cur
	out += _link("command:videomode:%d" % (0 if settings.fullscreen else 1), "Windowed" if settings.fullscreen
		else "Fullscreen") + "<br>"
	return out


## Control descriptions for controloptions.html and the briefings' ^controlX^ words.
func _control_vars() -> Dictionary:
	var v := {}
	# page placeholder prefix -> [action, up-direction]
	var rows := {"left": ["roll", true], "right": ["roll", false], "down": ["pitch", true], "up": ["pitch", false],
		"throttleup": ["throttle", true], "throttledown": ["throttle", false], "fire1": ["fire", true],
		"fire2": ["secondary", true], "camdown": ["camabove", true], "cambehind": ["cambehind", true],
		"camleft": ["camleft", true], "camright": ["camright", true], "special": ["special", true]}
	for k in rows:
		var d: Array = controls.describe(rows[k][0], rows[k][1], strings)
		var capturing: bool = not _capture.is_empty() and _capture.action == rows[k][0] and _capture.up == rows[k][1]
		v[k + "type"] = "?" if capturing else d[0]
		v[k + "value"] = "?" if capturing else d[1]
	# briefing words, as the exe builds ^control<name>^ (decomp RedAce.c:47380, format strings at 0x51d084..)
	var word := func(action: String, up: bool) -> String:
		return controls.briefing_word(action, up, strings)
	v.controlleft = word.call("roll", true)
	v.controlright = word.call("roll", false)
	v.controlup = word.call("pitch", true)
	v.controldown = word.call("pitch", false)
	v.controlfire1 = word.call("fire", true)
	v.controlfire2 = word.call("secondary", true)
	v.controlthrottleup = word.call("throttle", true)
	v.controlthrottledown = word.call("throttle", false)
	v.controlspecial = word.call("special", true)
	v.controlcamdown = word.call("camabove", true)
	v.controlcamup = word.call("camabove", true)
	v.controlcambehind = word.call("cambehind", true)
	v.controlcamleft = word.call("camleft", true)
	v.controlcamright = word.call("camright", true)
	return v


## The original draws its own cursor: Ui/cursor.ini (Image=menucursor.bmp, Mask=menucursorm.bmp),
## frame 0 (left 32x32, the arrow) on every page and over links too (checked in the original), with the
## arrow tip at the top-left pixel. Shown at the page scale; the build stores it 4x.
var _cursor_frame: Image


func _apply_cursor() -> void:
	if _cursor_frame == null:
		var p := Ini.data_path("ui/menucursor.png")
		if not ResourceLoader.exists(p):
			return
		var img: Image = (load(p) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		_cursor_frame = img.get_region(Rect2i(0, 0, img.get_width() / 2, img.get_height()))
	var win := Vector2(get_tree().root.size)
	var scale := minf(win.x / 640.0, win.y / 480.0)
	# browsers refuse cursors larger than 128 px
	var px := clampi(roundi(32.0 * scale), 16, 128 if OS.has_feature("web") else 256)
	var img := _cursor_frame.duplicate() as Image
	img.resize(px, px, Image.INTERPOLATE_LANCZOS)
	for shape in [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_IBEAM]:
		Input.set_custom_mouse_cursor(img, shape, Vector2.ZERO)


# ---------------------------------------------------------------- links and commands

## The original opened its help pages (file://localhost/language/english/help/...) in the system
## browser. Desktop: unpack game_data/help.zip to user://help once and open the page there.
## Web: the export step puts the same files under help/ next to index.html.
func _open_help(href: String) -> void:
	var rel := href.substr(href.find("localhost/") + 10) if href.find("localhost/") >= 0 else "language/english/help/index.htm"
	rel = rel.replace("\\", "/")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('help/%s', '_blank')" % rel.uri_encode().replace("%2F", "/"))
		return
	var root := "user://help/"
	if not FileAccess.file_exists(root + rel):
		var z := ZIPReader.new()
		if z.open(Ini.data_path("help.zip")) != OK:
			push_warning("help.zip missing")
			return
		for f in z.get_files():
			if f.ends_with("/"):
				continue
			DirAccess.make_dir_recursive_absolute((root + f).get_base_dir())
			var fa := FileAccess.open(root + f, FileAccess.WRITE)
			if fa:
				fa.store_buffer(z.read_file(f))
		z.close()
	OS.shell_open(ProjectSettings.globalize_path(root + rel))


var _click: AudioStreamPlayer


func _on_link(href: String) -> void:
	if _click.stream:
		_click.play()
	var h := href.strip_edges()
	var low := h.to_lower().replace("/", "\\")
	if low.begins_with("http"):
		OS.shell_open(h)
		return
	if low.begins_with("file:"):
		_open_help(h)
		return
	if low.begins_with("missions\\"):
		var parts := low.split("\\")
		_mission = int(parts[1])
		_campaign = false
		open_page(h)
		return
	if low.begins_with("menus\\"):
		if low.ends_with("roster.html"):
			_typing_slot = -1
		open_page(h)
		return
	if low.begins_with("play:"):
		_fly(int(low.get_slice(":", 1)), _campaign)
		return
	if low.begins_with("characterplay:"):
		var i := int(low.get_slice(":", 1)) - 1
		if i >= 0 and i < SLOTS and not pilots[i].is_empty() and _typing_slot < 0:
			current = i
			_save()
			open_page("Menus\\play.html")
		return
	if low.begins_with("characteroption:"):
		var i := int(low.get_slice(":", 1)) - 1
		if i < 0 or i >= SLOTS or _typing_slot >= 0:
			return
		if pilots[i].is_empty():
			_typing_slot = i
			_typed = ""
		else:
			_delete_slot = i
			open_page("Menus\\deleteconfirm.html")
			return
		_refresh()
		return
	if low.begins_with("controldefault:"):
		controls = Controls.from_file(h.get_slice(":", 1).strip_edges().to_lower())
		_save()
		_refresh()
		return
	if low.begins_with("control:"):
		# "control:Player1Roll:1:2" - redefine: the next key, mouse movement/button or joystick input
		# becomes the control (dir 1 = up/positive, kind 2 = axis, 1 = button), as in the original
		var parts := low.split(":")
		_capture = {"action": parts[1].trim_prefix("player1"), "up": parts[2] == "1" or parts[3] == "1"}
		_capture_armed = false
		get_tree().create_timer(0.25).timeout.connect(func() -> void: _capture_armed = true)
		_refresh()
		return
	if low.begins_with("command:"):
		_command(low.substr(8))


var _prev_fullscreen := false
var _screentest_token := 0


func _revert_video_mode() -> void:
	_screentest_token = 0
	settings.fullscreen = _prev_fullscreen
	_apply_settings()
	_save()
	open_page("Menus\\videooptions.html")


func _command(c: String) -> void:
	var a := c.split(":")
	match a[0]:
		"quit":
			if OS.has_feature("web"):
				open_page("Menus\\titlescreen.html")
			else:
				get_tree().quit()
		"timeout":
			# screentest.html "No" (or 5 s without an answer): back to the previous screen mode
			_revert_video_mode()
		"continue":
			_continue()
		"redo", "replay", "restart":
			_fly(_flown, _campaign)
		"abort":
			# the exe fades out with "Mission Aborted" and then shows the defeat page (RedAce.c:50974)
			if world:
				_resume()
				world.abort_mission()
			else:
				open_page("Menus\\main.html")
		"ok":
			if _delete_slot >= 0:
				pilots[_delete_slot] = {}
				if current == _delete_slot:
					current = -1
				_delete_slot = -1
				_save()
			open_page("Menus\\roster.html")
		"cancel":
			_delete_slot = -1
			open_page("Menus\\roster.html")
		"mousesensitivity":
			# axis 0 pitch, 1 roll, 2 throttle (the exe's options slider index)
			controls.bind[["pitch", "roll", "throttle"][clampi(int(a[1]), 0, 2)]].sensitivity = int(a[2]) / 10.0
			_save()
			_refresh()
		"reverse":
			if controls.bind.has(a[1]):
				controls.bind[a[1]].reversed = a.size() > 2 and a[2] == "1"
				_save()
			_refresh()
		"volume":
			settings["music_volume" if a[1] == "0" else "effects_volume"] = int(a[2])
			_apply_settings()
			_save()
			_refresh()
		"clipplane":
			settings.clip_plane = int(a[1])
			_save()
			_refresh()
		"effectsdetail":
			settings.effects_detail = int(a[1])
			_save()
			_refresh()
		"vsync":
			settings.vsync = a[1] == "1"
			_apply_settings()
			_save()
			_refresh()
		"videomode":
			# like the exe: switch, then ask on screentest.html to keep it; reverts after 5 s
			var want := a[1] == "1"
			if want == bool(settings.get("fullscreen", false)):
				_refresh()
				return
			_prev_fullscreen = bool(settings.get("fullscreen", false))
			settings.fullscreen = want
			_apply_settings()
			_save()
			open_page("Menus\\screentest.html")
			var token := Time.get_ticks_msec()
			_screentest_token = token
			get_tree().create_timer(5.0, true).timeout.connect(func() -> void:
				if _screentest_token == token and _page.to_lower().ends_with("screentest.html"):
					_revert_video_mode())
		"cheat":
			settings["cheat_" + a[1]] = a[2] == "1"
			_save()
			_refresh()
		"gamespeed":
			settings.game_speed = 0.5 + int(a[1]) / 10.0
			_save()
			_refresh()
		"enemyendurance":
			settings.enemy_endurance = 0.5 + int(a[1]) / 10.0
			_save()
			_refresh()
		"hardwaresound", "buy", "renderer":
			_refresh()


## "Continue": from the intro or the play page brief the pilot's next mission; from the pause page
## resume; from result pages show the briefing (failures) or the next mission's briefing (wins).
func _continue() -> void:
	if world and get_tree().paused:
		_resume()
		return
	var p := _pilot()
	if _page.to_lower().contains("failed"):
		open_page("missions\\%d\\mission.html" % _mission)
		return
	if not p.is_empty() and (_campaign or _page.to_lower().contains("intro") or _page.to_lower().contains("play")):
		_mission = int(p.mission)
		_campaign = true
		if _mission > LAST_MISSION:
			open_page("Menus\\congrats.html")
		else:
			open_page("missions\\%d\\mission.html" % _mission)
		return
	open_page("Menus\\main.html")


func _input(event: InputEvent) -> void:
	if _capture.is_empty() or not _capture_armed:
		return
	var b: Dictionary = controls.bind[_capture.action]
	var axis_action: bool = _capture.action in Controls.AXES
	var done := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			done = true
		else:
			var name := Controls.name_of_key(event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode)
			if event.location == KEY_LOCATION_LEFT and name in ["rightshift", "rightctrl", "rightalt"]:
				name = name.replace("right", "left")
			if b.type != "keyboard":
				var kb: Dictionary = Controls.from_file("keyboard.ini").bind[_capture.action]
				b.merge(kb, true)
			b.type = "keyboard"
			if axis_action:
				b["upkey" if _capture.up else "downkey"] = name
			else:
				b.key = name
			done = true
	elif event is InputEventMouseButton and event.pressed and not axis_action:
		b.type = "mouse"
		b.button = {MOUSE_BUTTON_LEFT: 1, MOUSE_BUTTON_RIGHT: 2, MOUSE_BUTTON_MIDDLE: 3}.get(event.button_index, 1)
		done = true
	elif event is InputEventMouseMotion and axis_action and _capture.action != "throttle" and event.relative.length() > 12.0:
		b.type = "mouse"
		b.axis = 1 if absf(event.relative.x) > absf(event.relative.y) else 2
		done = true
	elif event is InputEventJoypadButton and event.pressed and not axis_action:
		b.type = "joystick"
		b.button = event.button_index + 1
		done = true
	elif event is InputEventJoypadButton and event.pressed and axis_action:
		# the exe binds upbutton / downbutton for this row and drops the axis (type 7, stepped)
		_bind_joy_step(b, event.button_index + 1)
		done = true
	elif event is InputEventJoypadMotion and axis_action and event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT] \
			and event.axis_value > 0.6:
		# gamepad triggers rest at 0: a stepped up/down button, not an absolute lever
		_bind_joy_step(b, Controls.TRIGGER_BASE + event.axis + 1)
		done = true
	elif event is InputEventJoypadMotion and axis_action and absf(event.axis_value) > 0.6:
		b.type = "joystick"
		b.axis = event.axis + 1
		b.upbutton = 0
		b.downbutton = 0
		done = true
	if done:
		_capture = {}
		_save()
		get_viewport().set_input_as_handled()
		_refresh()


func _bind_joy_step(b: Dictionary, n: int) -> void:
	if b.type != "joystick" or int(b.axis) != 0:
		b.upbutton = 0
		b.downbutton = 0
	b.type = "joystick"
	b.axis = 0
	b["upbutton" if _capture.up else "downbutton"] = n


func _unhandled_input(event: InputEvent) -> void:
	if _typing_slot >= 0 and event is InputEventKey and event.pressed:
		var k: Key = event.keycode
		if k == KEY_ENTER or k == KEY_KP_ENTER:
			if not _typed.strip_edges().is_empty():
				pilots[_typing_slot] = {"name": _typed.strip_edges(), "rank": 0, "score": 0, "mission": 1, "flights": 0}
				current = _typing_slot
				_save()
			_typing_slot = -1
		elif k == KEY_ESCAPE:
			_typing_slot = -1
		elif k == KEY_BACKSPACE:
			_typed = _typed.substr(0, maxi(_typed.length() - 1, 0))
		elif event.unicode >= 32 and _typed.length() < 24:
			_typed += char(event.unicode)
		get_viewport().set_input_as_handled()
		_refresh()
	elif world and get_tree().paused and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_resume()
		get_viewport().set_input_as_handled()
	elif _page.ends_with("titlescreen.html") and (event is InputEventMouseButton or event is InputEventKey) and event.pressed:
		open_page("Menus\\main.html")


func _process(_dt: float) -> void:
	if _typing_slot >= 0 and Engine.get_process_frames() % 15 == 0:
		_refresh()  # blinking cursor


# ---------------------------------------------------------------- flights

func _fly(id: int, campaign: bool, debug := false) -> void:
	_end_flight()
	_mission = id
	_flown = id
	_campaign = campaign
	open_page("Menus\\loading.html")
	await get_tree().process_frame
	await get_tree().process_frame
	music.stop()
	world = World.new()
	world.standalone = debug
	world.mission_id = id
	world.cheat_boost = settings.cheat_boost
	world.cheat_infinite = settings.cheat_infinite
	world.cheat_invulnerable = settings.cheat_invulnerable
	world.enemy_endurance = settings.enemy_endurance
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.controls = controls
	world.finished.connect(_on_finished)
	world.pause_requested.connect(_pause)
	add_child(world)
	world.view_distance = 300.0 + settings.clip_plane * 250.0
	world.effects_detail = settings.effects_detail / 10.0
	if not debug:
		world.load_mission(id)
	view.visible = false
	_page = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if campaign and not _pilot().is_empty():
		pilots[current].flights = int(pilots[current].get("flights", 0)) + 1
		_save()


func _end_flight() -> void:
	get_tree().paused = false
	if world:
		world.queue_free()
		world = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _pause() -> void:
	if get_tree().paused:
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	open_page("Menus\\pause.html")


func _resume() -> void:
	view.visible = false
	_page = ""
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if world:
		world._was_captured = false  # capture is re-armed by the first click on the web


## Mission over (decomp RedAce.c:51072): campaign wins advance the mission, add the score and
## promote when the score reaches the next rank's threshold; finishing mission 25 shows congrats.
func _on_finished(result: String, score: int) -> void:
	_result = result
	_end_flight()
	_play_menu_music()
	if result != "won":
		open_page("Menus\\defeat.html")
		return
	var p := _pilot()
	if not _campaign or p.is_empty() or _mission < 1:
		open_page("Menus\\victory.html")
		return
	var was_last := _mission == LAST_MISSION
	if int(p.mission) == _mission:
		pilots[current].mission = _mission + 1
		pilots[current].score = int(p.score) + score
	var page := "Menus\\victory.html"
	var rank := int(pilots[current].rank)
	if rank < RANKS.size() - 1 and pilots[current].score >= PROMOTION_SCORE[rank]:
		pilots[current].rank = rank + 1
		page = "Menus\\promotion.html"
	if was_last:
		page = "Menus\\congrats.html"
	_save()
	_mission = int(pilots[current].mission)
	open_page(page)
