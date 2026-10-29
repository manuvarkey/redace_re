class_name TouchControls
extends Control
## On-screen flight controls for phones (web and Android); not in the original.
##   steering: tilt (accelerometer, neutral = how the phone is held at the start or on CAL), or a
##     virtual stick (drag on the left half) when there is no sensor or STICK is chosen;
##     both feed Aircraft.joy_roll / joy_pitch like a joystick, with the Controls page sensitivities.
##   throttle: vertical slider at the left edge, absolute while held.
##   FIRE / BOMB / BOOST (turbo cheat only): held buttons, bottom right.
##   VIEW: hold and swipe - up = above, down = behind, left / right = side views; release = chase view.
##   top row: PAUSE, OBJ (objectives), TILT/STICK toggle, CAL (tilt neutral).
## Touches are handled per finger index, so steering, throttle and buttons work together.
## Shown from the first touch; a real mouse hides it again (touch laptops keep the mouse controls).

const SETTINGS_PATH := "user://settings.cfg"
const TILT_RANGE := deg_to_rad(25.0)  # tilt for full deflection
const TILT_DEAD := deg_to_rad(2.0)
const STICK_RANGE := 110.0  # px drag for full deflection
## Sign of the tilt angles, set on the Android emulator: tilting the top edge away = nose down
## (joystick forward), lowering the right side = roll right.
const TILT_ROLL_SIGN := 1.0
const TILT_PITCH_SIGN := -1.0

signal pause_pressed
signal objectives_pressed

var active := false
var roll := 0.0
var pitch := 0.0
var throttle := -1.0  # slider value while held, else -1
var view := 1  # camera mode: 1 chase, 4 behind, 6 left, 7 right, 8 above
var tilt_wanted := true
var show_boost := false
var player_throttle := 0.0  # drawn on the slider when it is not held

var _held := {}  # action -> true: fire, secondary, special
var _touches := {}  # finger index -> {kind, start, pos}
var _g0 := Vector3.ZERO  # neutral gravity
var _font: Font
var _js_window: JavaScriptObject


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fp := Ini.data_path("ui/morpheus.ttf")
	_font = load(fp) if ResourceLoader.exists(fp) else ThemeDB.fallback_font
	active = is_mobile()
	if OS.has_feature("web"):
		_js_window = JavaScriptBridge.get_interface("window")
	var s := ConfigFile.new()
	if s.load(SETTINGS_PATH) == OK:
		tilt_wanted = bool(s.get_value("touch", "tilt", true))


func pressed(action: String) -> bool:
	return active and _held.has(action)


## Gravity in screen coordinates (x right, y up, z out of the screen; pointing down, as Godot reports it),
## zero when there is no sensor.
## Android (project settings input_devices/sensors/*): Godot rotates the sensor to the screen. Web: index.html's head script does the same from
## devicemotion (window.raTx/raTy/raTz).
func gravity() -> Vector3:
	if _js_window:
		var x = _js_window.raTx
		if x == null:
			return Vector3.ZERO
		return Vector3(float(x), float(_js_window.raTy), float(_js_window.raTz))
	var g := Input.get_gravity()
	return g if g != Vector3.ZERO else Input.get_accelerometer()


func has_tilt() -> bool:
	return gravity().length() > 1.0


func tilt_mode() -> bool:
	return tilt_wanted and has_tilt()


func calibrate() -> void:
	_g0 = gravity()


static func _roll_angle(g: Vector3) -> float:
	return atan2(g.x, Vector2(g.y, g.z).length())


static func _pitch_angle(g: Vector3) -> float:
	return atan2(g.z, g.y)


static func _axis(a: float) -> float:
	if absf(a) < TILT_DEAD:
		return 0.0
	return clampf((a - signf(a) * TILT_DEAD) / (TILT_RANGE - TILT_DEAD), -1.0, 1.0)


func _process(_dt: float) -> void:
	visible = active
	if not active:
		return
	if tilt_mode():
		var g := gravity()
		if _g0 == Vector3.ZERO:
			_g0 = g
		roll = _axis(_roll_angle(g) - _roll_angle(_g0)) * TILT_ROLL_SIGN
		pitch = _axis(wrapf(_pitch_angle(g) - _pitch_angle(_g0), -PI, PI)) * TILT_PITCH_SIGN
	elif not _touches.values().any(func(t: Dictionary) -> bool: return t.kind == "stick"):
		roll = 0.0
		pitch = 0.0
	queue_redraw()


# ---------------------------------------------------------------- layout

## Layout unit; controls keep clear of the bottom edge (rounded corners, curved screens).
func _unit() -> float:
	return size.y / 720.0


func _top_buttons() -> Array:
	var u := _unit()
	var w := 112.0 * u
	var h := 52.0 * u
	var names := ["PAUSE", "OBJ", "STICK" if tilt_wanted else "TILT"]
	if tilt_mode():
		names.append("CAL")
	var x0 := size.x * 0.5 - (names.size() * (w + 12.0 * u) - 12.0 * u) * 0.5
	var out := []
	for i in names.size():
		out.append({"name": names[i], "rect": Rect2(x0 + i * (w + 12.0 * u), 64.0 * u, w, h)})
	return out


func _throttle_rect() -> Rect2:
	var u := _unit()
	return Rect2(24.0 * u, size.y * 0.32, 72.0 * u, size.y * 0.54)


func _buttons() -> Array:
	var u := _unit()
	var out := [
		{"action": "fire", "label": "FIRE", "c": Vector2(size.x - 150.0 * u, size.y - 175.0 * u), "r": 95.0 * u},
		{"action": "secondary", "label": "BOMB", "c": Vector2(size.x - 340.0 * u, size.y - 125.0 * u), "r": 68.0 * u},
	]
	if show_boost:
		out.append({"action": "special", "label": "BOOST", "c": Vector2(size.x - 130.0 * u, size.y - 380.0 * u), "r": 58.0 * u})
	return out


func _view_pad() -> Dictionary:
	var u := _unit()
	return {"c": Vector2(size.x - 340.0 * u, size.y - 320.0 * u), "r": 70.0 * u}


func _stick_zone() -> Rect2:
	var t := _throttle_rect()
	var x := t.end.x + 24.0 * _unit()
	return Rect2(x, size.y * 0.3, size.x * 0.5 - x, size.y * 0.62)


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		active = true
		visible = true
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_drag(event.index, event.position)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and not is_mobile():
		active = false  # a real mouse took over
		_touches.clear()
		_held.clear()


func _press(i: int, pos: Vector2) -> void:
	for b in _top_buttons():
		if b.rect.grow(8.0).has_point(pos):
			_tap(b.name)
			_touches[i] = {"kind": "tap", "start": pos, "pos": pos}
			get_viewport().set_input_as_handled()
			return
	for b in _buttons():
		if pos.distance_to(b.c) <= b.r * 1.15:
			_held[b.action] = true
			_touches[i] = {"kind": "button", "action": b.action, "start": pos, "pos": pos}
			get_viewport().set_input_as_handled()
			return
	var vp := _view_pad()
	if pos.distance_to(vp.c) <= vp.r * 1.2:
		_touches[i] = {"kind": "view", "start": pos, "pos": pos}
		get_viewport().set_input_as_handled()
		return
	if _throttle_rect().grow(24.0 * _unit()).has_point(pos):
		_touches[i] = {"kind": "throttle", "start": pos, "pos": pos}
		_drag(i, pos)
		get_viewport().set_input_as_handled()
		return
	if not tilt_mode() and _stick_zone().has_point(pos):
		_touches[i] = {"kind": "stick", "start": pos, "pos": pos}
		get_viewport().set_input_as_handled()


func _drag(i: int, pos: Vector2) -> void:
	var t: Dictionary = _touches[i]
	t.pos = pos
	match t.kind:
		"throttle":
			var r := _throttle_rect()
			throttle = clampf(1.0 - (pos.y - r.position.y) / r.size.y, 0.0, 1.0)
		"stick":
			var d: Vector2 = (pos - t.start) / (STICK_RANGE * _unit())
			roll = clampf(d.x, -1.0, 1.0)
			pitch = clampf(d.y, -1.0, 1.0)  # drag up = stick forward = nose down
		"view":
			var d: Vector2 = pos - t.start
			if d.length() < 30.0 * _unit():
				view = 1
			elif absf(d.x) > absf(d.y):
				view = 7 if d.x > 0.0 else 6
			else:
				view = 4 if d.y > 0.0 else 8


func _release(i: int) -> void:
	if not _touches.has(i):
		return
	var t: Dictionary = _touches[i]
	_touches.erase(i)
	match t.kind:
		"button":
			_held.erase(t.action)
		"throttle":
			throttle = -1.0
		"stick":
			roll = 0.0
			pitch = 0.0
		"view":
			view = 1


func _tap(name: String) -> void:
	match name:
		"PAUSE":
			_touches.clear()
			_held.clear()
			view = 1
			pause_pressed.emit()
		"OBJ":
			objectives_pressed.emit()
		"TILT", "STICK":
			tilt_wanted = name == "TILT"
			roll = 0.0
			pitch = 0.0
			calibrate()
			var s := ConfigFile.new()
			s.load(SETTINGS_PATH)
			s.set_value("touch", "tilt", tilt_wanted)
			s.save(SETTINGS_PATH)
		"CAL":
			calibrate()


func reset() -> void:
	_touches.clear()
	_held.clear()
	throttle = -1.0
	view = 1
	calibrate()


# ---------------------------------------------------------------- drawing

const FILL := Color(1.0, 1.0, 1.0, 0.16)
const LINE := Color(1.0, 0.95, 0.75, 0.55)
const LIT := Color(1.0, 0.85, 0.4, 0.45)
const TEXT := Color(1.0, 0.95, 0.8, 0.85)


func _label(text: String, centre: Vector2, fs: int) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, centre + Vector2(-w * 0.5, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT)


func _draw() -> void:
	var u := _unit()
	var fs := int(26.0 * u)
	for b in _top_buttons():
		draw_rect(b.rect, FILL)
		draw_rect(b.rect, LINE, false, 2.0 * u)
		_label(b.name, b.rect.get_center(), int(22.0 * u))
	for b in _buttons():
		draw_circle(b.c, b.r, LIT if _held.has(b.action) else FILL)
		draw_arc(b.c, b.r, 0.0, TAU, 48, LINE, 3.0 * u)
		_label(b.label, b.c, fs)
	var vp := _view_pad()
	var viewing := view != 1
	draw_circle(vp.c, vp.r, LIT if viewing else FILL)
	draw_arc(vp.c, vp.r, 0.0, TAU, 48, LINE, 3.0 * u)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var tip: Vector2 = vp.c + d * vp.r * 0.85
		var side := Vector2(-d.y, d.x) * 9.0 * u
		draw_colored_polygon(PackedVector2Array([tip, tip - d * 14.0 * u + side, tip - d * 14.0 * u - side]), LINE)
	_label("VIEW", vp.c, int(22.0 * u))
	var tr := _throttle_rect()
	draw_rect(tr, FILL)
	draw_rect(tr, LINE, false, 2.0 * u)
	var th := throttle if throttle >= 0.0 else player_throttle
	var fill_h := tr.size.y * th
	draw_rect(Rect2(tr.position.x, tr.end.y - fill_h, tr.size.x, fill_h), LIT)
	_label("THR", Vector2(tr.get_center().x, tr.position.y - 22.0 * u), int(22.0 * u))
	for t in _touches.values():
		if t.kind == "stick":
			var r := STICK_RANGE * u
			draw_arc(t.start, r, 0.0, TAU, 48, LINE, 2.0 * u)
			draw_circle(t.start + (t.pos - t.start).limit_length(r), 34.0 * u, LIT)
	if not tilt_mode() and _touches.is_empty():
		_label("drag to steer" if not (tilt_wanted and not has_tilt()) else "no tilt sensor: drag to steer",
			_stick_zone().get_center(), int(22.0 * u))
