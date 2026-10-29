class_name Controls
extends RefCounted
## Player controls as the original defines them (redace.ini / mousekeys.ini / keyboard.ini / joystick.ini,
## read by decomp FUN_004485bb / FUN_00448b79): each [Player1<Action>] section has a type (keyboard,
## mouse, joystick) and either axis + sensitivity, upkey/downkey + sensitivity, key, or button.
## Axis actions: Roll, Pitch, Throttle. Button actions: Fire, Secondary, Special, CamAbove, CamLeft,
## CamRight, CamBehind. Joystick buttons -1..-4 are the hat (up, right, down, left).
## Joystick axis actions (decomp FUN_004485bb): "axis" = type 5, read absolutely (throttle = (v * s + 1) / 2,
## FUN_004322de, so a self-centring axis puts the throttle back to half); or "upbutton" / "downbutton" = type 7,
## stepped like keys (throttle += dt * s per held button) - what the Controls page binds when a joystick
## button is pressed on a Throttle/Roll/Pitch row. Gamepad triggers (axes 5/6 here, which DirectInput sticks
## did not have) are accepted as up/down buttons: number TRIGGER_BASE + axis.

const AXES := ["roll", "pitch", "throttle"]
const BUTTONS := ["fire", "secondary", "special", "camabove", "camleft", "camright", "cambehind"]
const SETTINGS_PATH := "user://settings.cfg"
const TRIGGER_BASE := 1000

## key names used in the control files (strings.ini) -> Godot keys
const KEY_NAMES := {
	"leftarrow": KEY_LEFT, "rightarrow": KEY_RIGHT, "uparrow": KEY_UP, "downarrow": KEY_DOWN,
	"leftshift": KEY_SHIFT, "rightshift": KEY_SHIFT, "leftctrl": KEY_CTRL, "rightctrl": KEY_CTRL,
	"leftalt": KEY_ALT, "rightalt": KEY_ALT, "spacebar": KEY_SPACE, "return": KEY_ENTER, "tab": KEY_TAB,
	"backspace": KEY_BACKSPACE, "insert": KEY_INSERT, "delete": KEY_DELETE, "home": KEY_HOME, "end": KEY_END,
	"pageup": KEY_PAGEUP, "pagedown": KEY_PAGEDOWN, "capslock": KEY_CAPSLOCK, "numlock": KEY_NUMLOCK,
	"backslash": KEY_BACKSLASH, "keypadenter": KEY_KP_ENTER, "keypadpoint": KEY_KP_PERIOD,
	"keypadplus": KEY_KP_ADD, "keypadminus": KEY_KP_SUBTRACT, "keypaddivide": KEY_KP_DIVIDE,
	"keypadmultiply": KEY_KP_MULTIPLY, "keypad0": KEY_KP_0, "keypad1": KEY_KP_1, "keypad2": KEY_KP_2,
	"keypad3": KEY_KP_3, "keypad4": KEY_KP_4, "keypad5": KEY_KP_5, "keypad6": KEY_KP_6, "keypad7": KEY_KP_7,
	"keypad8": KEY_KP_8, "keypad9": KEY_KP_9, ".": KEY_PERIOD, ",": KEY_COMMA,
}

var bind := {}  # action -> {type, axis, upkey, downkey, key, button, sensitivity, reversed}


static func from_file(ini_name: String) -> Controls:
	var c := Controls.new()
	var ini := Ini.load_file(Ini.data_path(ini_name))
	for a in AXES + BUTTONS:
		var sec: Dictionary = ini.get("player1" + a, {})
		c.bind[a] = {"type": str(sec.get("type", "keyboard")).strip_edges().to_lower(),
			"axis": int(Ini.num(sec, "axis", 1)), "upkey": str(sec.get("upkey", "")).strip_edges(),
			"downkey": str(sec.get("downkey", "")).strip_edges(), "key": str(sec.get("key", "")).strip_edges(),
			"button": int(Ini.num(sec, "button", 0)), "sensitivity": Ini.num(sec, "sensitivity", 1.0),
			"upbutton": int(Ini.num(sec, "upbutton", 0)), "downbutton": int(Ini.num(sec, "downbutton", 0)),
			"reversed": false}
		if sec.has("upbutton") and not sec.has("axis"):
			c.bind[a].axis = 0
	# joystick.ini puts the throttle on DirectInput axis 3 (Z: a flight stick's lever). On a gamepad that
	# axis is self-centring (right stick, or the triggers combined under DirectInput), so the absolute
	# lever would sit at half throttle; there the triggers step it instead (right = up, left = down).
	var pads := Input.get_connected_joypads()
	if ini_name == "joystick.ini" and not pads.is_empty() and Input.is_joy_known(pads[0]):
		var t: Dictionary = c.bind.throttle
		t.axis = 0
		t.upbutton = TRIGGER_BASE + JOY_AXIS_TRIGGER_RIGHT + 1
		t.downbutton = TRIGGER_BASE + JOY_AXIS_TRIGGER_LEFT + 1
	return c


## Saved bindings, or the defaults from redace.ini (the mouse layout).
static func load_saved() -> Controls:
	var c := from_file("redace.ini")
	var s := ConfigFile.new()
	if s.load(SETTINGS_PATH) == OK and s.has_section("bindings"):
		for a in c.bind:
			var saved = s.get_value("bindings", a, null)
			if saved is Dictionary:
				c.bind[a].merge(saved, true)
	return c


func save() -> void:
	var s := ConfigFile.new()
	s.load(SETTINGS_PATH)
	for a in bind:
		s.set_value("bindings", a, bind[a])
	s.save(SETTINGS_PATH)


static func key_of(name: String) -> Key:
	var n := name.strip_edges().to_lower()
	if KEY_NAMES.has(n):
		return KEY_NAMES[n]
	if n.length() == 1:
		return OS.find_keycode_from_string(n.to_upper())
	return KEY_NONE


static func name_of_key(k: Key) -> String:
	for n in KEY_NAMES:
		if KEY_NAMES[n] == k and not n.begins_with("left"):
			return n
	return OS.get_keycode_string(k)


func _pressed_key(name: String) -> float:
	var k := key_of(name)
	return 1.0 if k != KEY_NONE and Input.is_physical_key_pressed(k) else 0.0


func _joy_axis(axis: int) -> float:
	var v := Input.get_joy_axis(0, axis - 1) if Input.get_connected_joypads().size() > 0 else 0.0
	return v if absf(v) > 0.08 else 0.0


## One joystick button (or hat direction, or gamepad trigger) held.
func _joy_button(n: int) -> bool:
	if n == 0 or Input.get_connected_joypads().is_empty():
		return false
	if n < 0:
		var hat := {-1: JOY_BUTTON_DPAD_UP, -2: JOY_BUTTON_DPAD_RIGHT, -3: JOY_BUTTON_DPAD_DOWN, -4: JOY_BUTTON_DPAD_LEFT}
		return Input.is_joy_button_pressed(0, hat.get(n, JOY_BUTTON_DPAD_UP))
	if n >= TRIGGER_BASE:
		return Input.get_joy_axis(0, n - TRIGGER_BASE - 1) > 0.5
	return Input.is_joy_button_pressed(0, n - 1)


## Joystick up/down buttons of an axis action (type 7) as -1 / 0 / +1 (up = +1).
func _joy_buttons(b: Dictionary) -> float:
	return (1.0 if _joy_button(int(b.get("upbutton", 0))) else 0.0) - (1.0 if _joy_button(int(b.get("downbutton", 0))) else 0.0)


## Button action state.
func pressed(action: String) -> bool:
	var b: Dictionary = bind.get(action, {})
	match b.get("type", ""):
		"keyboard":
			return _pressed_key(b.key) > 0.0
		"mouse":
			return Input.is_mouse_button_pressed(int(b.button)) if int(b.button) > 0 else false
		"joystick":
			return _joy_button(int(b.button))
	return false


## Apply the flight controls to the player for one physics frame (original FUN_004322de).
## mouse = this frame's motion in mickeys.
func drive(p: Aircraft, mouse: Vector2, dt: float) -> void:
	var r: Dictionary = bind.roll
	var q: Dictionary = bind.pitch
	var t: Dictionary = bind.throttle
	var rs := -1.0 if r.reversed else 1.0
	var ps := -1.0 if q.reversed else 1.0
	# roll
	match r.type:
		"mouse":
			p.mouse_control((mouse.x if r.axis == 1 else mouse.y) * rs, 0.0, r.sensitivity, q.sensitivity)
		"joystick" when int(r.axis) == 0:
			# upbutton = roll left, like upkey
			p.key_roll(-_joy_buttons(r) * rs, r.sensitivity, dt)
		"joystick":
			p.joy_roll(_joy_axis(r.axis) * rs, r.sensitivity)
		_:
			# upkey = roll left, downkey = roll right (keyboard.ini: upkey = leftarrow)
			p.key_roll(_pressed_key(r.downkey) - _pressed_key(r.upkey), r.sensitivity, dt)
	# pitch
	match q.type:
		"mouse":
			p.mouse_control(0.0, (mouse.y if q.axis == 2 else mouse.x) * ps, r.sensitivity, q.sensitivity)
		"joystick" when int(q.axis) == 0:
			# upbutton = nose down, like upkey
			p.key_pitch(-_joy_buttons(q) * ps, q.sensitivity, dt)
		"joystick":
			p.joy_pitch(_joy_axis(q.axis) * ps, q.sensitivity, dt)
		_:
			# upkey = nose down (keyboard.ini: upkey = uparrow)
			p.key_pitch(_pressed_key(q.downkey) - _pressed_key(q.upkey), q.sensitivity, dt)
	# throttle
	match t.type:
		"joystick" when int(t.axis) == 0:
			p.throttle = clampf(p.throttle + _joy_buttons(t) * t.sensitivity * dt, 0.0, 1.0)
		"joystick":
			p.throttle = clampf((-_joy_axis(t.axis) * (-1.0 if t.reversed else 1.0) * t.sensitivity + 1.0) * 0.5, 0.0, 1.0)
		_:
			p.throttle = clampf(p.throttle + (_pressed_key(t.upkey) - _pressed_key(t.downkey)) * t.sensitivity * dt, 0.0, 1.0)
	p.fire_input = pressed("fire")
	p.secondary_input = pressed("secondary")


## Text for the Controls page: controller type and value for one action (and direction for axes).
func describe(action: String, up: bool, strings: Dictionary) -> Array:
	var b: Dictionary = bind[action]
	var s := func(k: String) -> String: return strings.get(k, k)
	var typ: String = s.call(b.type)
	var val := ""
	match b.type:
		"keyboard":
			var kn: String = b.key if action in BUTTONS else (b.upkey if up else b.downkey)
			val = s.call(kn.to_lower()) if strings.has(kn.to_lower()) else kn
		"mouse":
			if action in BUTTONS:
				val = s.call({1: "leftmousebutton", 2: "rightmousebutton", 3: "middlemousebutton"}.get(int(b.button), "button"))
			else:
				val = "%s %d" % [s.call("axis"), int(b.axis)]  # "axis 1" on both rows, as the exe shows
		"joystick":
			if action in BUTTONS:
				val = _button_text(int(b.button), s)
			elif int(b.axis) == 0:
				val = _button_text(int(b.get("upbutton" if up else "downbutton", 0)), s)
			else:
				val = "%s %d" % [s.call("axis"), int(b.axis)]
	return [typ, val]


static func _button_text(n: int, s: Callable) -> String:
	if n < 0:
		return "hat " + str(s.call(["up", "right", "down", "left"][clampi(-n - 1, 0, 3)])).to_lower()
	if n >= TRIGGER_BASE:
		return "trigger %d" % (n - TRIGGER_BASE)
	return "%s %d" % [s.call("button"), n]


## Briefing text for one control, as the exe writes ^control<name>^ (decomp RedAce.c:47380):
## keys "'right Shift'", mouse buttons "'left mouse button'", axes "'Mouse Left'" (axis 3: "'Mouse axis 3 Up'"),
## joystick buttons "Joystick button 2", hat "Joystick 'POV Up'".
func briefing_word(action: String, up: bool, strings: Dictionary) -> String:
	var b: Dictionary = bind[action]
	var s := func(k: String) -> String: return strings.get(k, k)
	var typ: String = s.call(b.type)
	match b.type:
		"keyboard":
			var kn: String = b.key if action in BUTTONS else (b.upkey if up else b.downkey)
			return "'%s'" % s.call(kn.to_lower())
		_:
			if action in BUTTONS:
				var n := int(b.button)
				if n < 0:
					return "%s 'POV %s'" % [typ, s.call(["up", "right", "down", "left"][clampi(-n - 1, 0, 3)])]
				if b.type == "mouse" and n >= 1 and n <= 3:
					return "'%s'" % s.call(["leftmousebutton", "rightmousebutton", "middlemousebutton"][n - 1])
				return "%s %s %d" % [typ, s.call("button"), n]
			if b.type == "joystick" and int(b.axis) == 0:
				return "%s %s" % [typ, _button_text(int(b.get("upbutton" if up else "downbutton", 0)), s)]
			var dir: String = s.call(("left" if up else "right") if int(b.axis) == 1 else ("up" if up else "down"))
			if int(b.axis) == 3:
				return "'%s %s %d %s'" % [typ, s.call("axis"), 3, dir]
			return "'%s %s'" % [typ, dir]
