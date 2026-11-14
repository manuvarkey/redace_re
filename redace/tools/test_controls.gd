extends SceneTree
## Flight controls on phones with a game controller: which input flies each axis (Controls.drive).
## godot --headless --path redace -s tools/test_controls.gd

var checks := 0
var failures := 0


## A controller (device 0) with set axes and buttons, and optionally a phone.
class FakeControls extends Controls:
	var pad := -1
	var axes := {}  # axis number (1-based, as bound) -> value
	var buttons := {}  # button number -> held
	var mobile := false
	func _pad() -> int:
		return pad
	func _mobile() -> bool:
		return mobile
	func _pad_has_sensors() -> bool:
		return false  # as on Android: Godot reads controller sensors through SDL only
	func _joy_axis(axis: int) -> float:
		return float(axes.get(axis, 0.0)) if pad >= 0 else 0.0
	func _joy_button(n: int) -> bool:
		return pad >= 0 and bool(buttons.get(n, false))


## A phone's touch layer with a set gravity reading.
class FakeTouch extends TouchControls:
	var g := Vector3.ZERO
	func gravity() -> Vector3:
		return g


## Records what the controls asked of the plane.
class Probe extends Aircraft:
	var roll_in := NAN
	var pitch_in := NAN
	var calls: Array[String] = []
	func joy_roll(v: float, s: float, _response_seconds := 0.0) -> void:
		roll_in = v * s
		calls.append("joy_roll")
	func joy_pitch(v: float, s: float, _dt: float) -> void:
		pitch_in = v * s
		calls.append("joy_pitch")
	func key_roll(axis: float, _s: float, _dt: float) -> void:
		roll_in = axis
		calls.append("key_roll")
	func key_pitch(axis: float, _s: float, _dt: float) -> void:
		pitch_in = axis
		calls.append("key_pitch")
	func mouse_control(_dx: float, _dy: float, _s_roll: float, _s_pitch: float) -> void:
		calls.append("mouse")


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)


func near(a: float, b: float) -> bool:
	return absf(a - b) < 1e-4


## Joystick bindings (roll axis 1, pitch axis 2, throttle on two buttons) with sensitivity 1, as joystick.ini sets them
## on a known gamepad.
func joystick_controls() -> FakeControls:
	var c := FakeControls.new()
	var src := Controls.from_file("joystick.ini")
	c.bind = src.bind.duplicate(true)
	for a in Controls.AXES:
		c.bind[a].sensitivity = 1.0
		c.bind[a].reversed = false
	c.bind.throttle.axis = 0
	c.bind.throttle.upbutton = 6
	c.bind.throttle.downbutton = 5
	return c


func phone(c: FakeControls) -> FakeTouch:
	var t := FakeTouch.new()
	t.active = true
	t.roll = 0.3  # tilt or on-screen stick
	t.pitch = 0.2
	c.touch = t
	c.mobile = true
	return t


func run() -> void:
	var dt := 1.0 / 60.0
	var p := Probe.new()

	# the reported bug: on a phone, a connected controller's stick did nothing (the touch layer flew every axis)
	var c := joystick_controls()
	var t := phone(c)
	c.pad = 0
	c.axes = {1: 0.8, 2: -0.6}
	c.drive(p, Vector2.ZERO, dt)
	check(near(p.roll_in, 0.8) and near(p.pitch_in, -0.6), "phone + controller: the stick flies roll and pitch (got %f, %f)" % [p.roll_in, p.pitch_in])

	# no controller connected: the touch layer flies, as before
	c.pad = -1
	c.drive(p, Vector2.ZERO, dt)
	check(near(p.roll_in, 0.3) and near(p.pitch_in, 0.2), "phone without a controller: touch steering")

	# controller connected but the mouse layout bound: touch steering
	var m := FakeControls.new()
	m.bind = Controls.from_file("redace.ini").bind.duplicate(true)
	for a in Controls.AXES:
		m.bind[a].sensitivity = 1.0
	phone(m)
	m.pad = 0
	m.axes = {1: 0.8, 2: -0.6}
	m.drive(p, Vector2.ZERO, dt)
	check(near(p.roll_in, 0.3) and near(p.pitch_in, 0.2), "phone, controller, mouse layout: touch steering")

	# a finger on the on-screen stick takes over from the controller
	c.pad = 0
	t._touches[0] = {"kind": "stick", "start": Vector2.ZERO, "pos": Vector2.ZERO}
	c.drive(p, Vector2.ZERO, dt)
	check(near(p.roll_in, 0.3) and near(p.pitch_in, 0.2), "on-screen stick held: touch steering")
	t._touches.clear()

	# controller tilt option without controller sensors: the phone's own tilt, while the stick is at rest
	c.gyro_enabled = true
	c.axes = {1: 0.0, 2: 0.0}
	t.g = Vector3(0, -9.8, 0)
	t.calibrate()
	var a := deg_to_rad(15.0)
	t.g = Vector3(sin(a), -cos(a), 0) * 9.8  # 15 degrees about the screen's z: roll
	var expect := t.tilt_axes()
	c.drive(p, Vector2.ZERO, dt)
	check(absf(expect.x) > 0.3 and near(p.roll_in, expect.x), "controller tilt on a phone uses the phone's tilt (%f, %f)" % [p.roll_in, expect.x])
	c.axes = {1: -0.7, 2: 0.0}
	c.drive(p, Vector2.ZERO, dt)
	check(near(p.roll_in, -0.7), "a moved stick overrides the tilt")
	check(c.gyro_available(), "tilt option offered on a phone without controller sensors")
	c.gyro_enabled = false
	c.axes = {1: 0.0, 2: 0.0}
	c.drive(p, Vector2.ZERO, dt)
	check(near(p.roll_in, 0.0), "tilt option off: a centred stick is level, phone tilt ignored")
	var desk := joystick_controls()
	check(not desk.gyro_available(), "no tilt option on a desktop without controller sensors")

	# throttle: controller buttons step it unless the on-screen slider is held
	p.throttle = 0.5
	c.buttons = {6: true}
	c.drive(p, Vector2.ZERO, dt)
	check(p.throttle > 0.5, "controller throttle button on a phone")
	check(near(t.player_throttle, p.throttle), "slider shows the controller's throttle")
	t.throttle = 0.2
	c.drive(p, Vector2.ZERO, dt)
	check(near(p.throttle, 0.2), "held slider sets the throttle")
	t.throttle = -1.0
	c.buttons = {}
	c.pad = -1
	var before := p.throttle
	c.drive(p, Vector2.ZERO, dt)
	check(near(p.throttle, before), "phone without a controller: joystick throttle binding leaves the throttle alone")

	# desktop (no touch layer): the controller as before
	desk.pad = 0
	desk.axes = {1: -0.4, 2: 0.9}
	desk.drive(p, Vector2.ZERO, dt)
	check(near(p.roll_in, -0.4) and near(p.pitch_in, 0.9), "desktop controller unchanged")

	t.free()
	m.touch.free()
	p.free()
	print("Controls: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
