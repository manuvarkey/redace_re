extends CanvasLayer
## Red Baron screen overlays (not in the original):
##   - the wound effect (mission 8: the view dims, greys and blurs with a slow pulse);
##   - HUD lines at the top centre: the counter (one or more lines) and the current objective;
##   - target brackets in the 3D view, one colour per kind, the same in every mission:
##       priority  red-orange  the targets the objective names (spotters, the recon plane, bombers, balloons, tanks)
##       protect   green       what must survive (the photo plane, hangars, the rail yard)
##       threat    yellow      a short warning highlight (an ambush, a fresh wave)
##       ally      pale blue   a wingman whose cover the player should see
##     A bracket can carry a label and, when its object is off screen, an arrow at the screen edge;
##   - cue sounds (objective change, warning, impact) and a short camera jolt.
## Drawn under the game's HUD layer (World's UI layer is 1), the brackets and lines above it.

const COLOURS := {
	"priority": Color(1.0, 0.38, 0.2),
	"protect": Color(0.45, 1.0, 0.45),
	"threat": Color(1.0, 0.9, 0.2),
	"ally": Color(0.65, 0.82, 1.0),
}

var world: World
var wound := 0.0  # 0 none .. 1 full
var _rect: ColorRect
var _mat: ShaderMaterial
var _top: CanvasLayer
var _counter: Label
var _objective: Label
var _marks: Control
var _time := 0.0
var _font: Font
var _brackets: Array[Dictionary] = []  # {node, kind, label, arrow, until, range}
var _jolt := 0.0
var _jolt_amount := 0.0
var _player: AudioStreamPlayer
var _cues := {}

const WOUND_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * (0.5 + 1.5 * amount);
	vec3 c = vec3(0.0);
	float n = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			c += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px).rgb;
			n += 1.0;
		}
	}
	c /= n;
	float grey = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(grey), 0.35 * amount);
	// darker towards the edges
	float edge = smoothstep(0.25, 0.75, length(SCREEN_UV - vec2(0.5)));
	c *= 1.0 - amount * (0.15 + 0.5 * edge);
	COLOR = vec4(c, 1.0);
}
"""


func _ready() -> void:
	layer = 0  # above the 3D view, below the HUD (World's UI layer is 1)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = WOUND_SHADER
	_mat.shader = sh
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)
	var fp := Ini.data_path("ui/morpheus.ttf")
	_font = load(fp) if ResourceLoader.exists(fp) else ThemeDB.fallback_font
	_top = CanvasLayer.new()
	_top.layer = 2
	add_child(_top)
	_marks = Control.new()
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_brackets)
	_top.add_child(_marks)
	_player = AudioStreamPlayer.new()
	_player.volume_db = -6.0
	add_child(_player)


func _process(dt: float) -> void:
	_time += dt
	_rect.visible = wound > 0.0
	if wound > 0.0:
		# a slow pulse, like a heartbeat in the ears
		var pulse := 0.85 + 0.15 * sin(_time * 2.4)
		_mat.set_shader_parameter("amount", clampf(wound * pulse, 0.0, 1.0))
	if world and is_instance_valid(world.camera):
		if _jolt > 0.0:
			_jolt = maxf(_jolt - dt, 0.0)
			var a := _jolt_amount * minf(_jolt * 4.0, 1.0)
			world.camera.h_offset = randf_range(-a, a)
			world.camera.v_offset = randf_range(-a, a)
		elif world.camera.h_offset != 0.0 or world.camera.v_offset != 0.0:
			world.camera.h_offset = 0.0
			world.camera.v_offset = 0.0
	_marks.queue_redraw()


func _label(offset_top: float, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.offset_top = offset_top
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(l)
	return l


## Lines of text at the top centre (below the timer), or "" to hide them. "\n" separates lines.
func set_counter(text: String) -> void:
	_lines()
	_counter.text = text
	_counter.visible = text != ""


## The current objective, a smaller line under the counter; "" hides it.
func set_objective(text: String) -> void:
	_lines()
	_objective.text = text
	_objective.visible = text != ""


## The counter and objective labels, stacked in a box at the top centre (the box spaces them, whatever the font).
func _lines() -> void:
	if _counter != null:
		return
	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.offset_top = 48
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(box)
	_counter = _label(0, 24, Color(1, 0.9, 0.5))
	_objective = _label(0, 18, Color(0.92, 0.92, 0.85))
	for l in [_counter, _objective]:
		_top.remove_child(l)
		box.add_child(l)
		l.visible = false


## A bracket on node (an Aircraft or a ground object's node). arrow: show an arrow at the screen edge when the
## object is off screen. seconds > 0: the bracket goes after that long. max_range: no bracket (on screen) beyond it.
func add_bracket(node: Node3D, kind: String, label := "", arrow := false, seconds := 0.0, max_range := 2500.0) -> void:
	remove_bracket(node, kind)
	_brackets.append({"node": node, "kind": kind, "label": label, "arrow": arrow,
		"until": _time + seconds if seconds > 0.0 else INF, "range": max_range})


func remove_bracket(node: Node3D, kind := "") -> void:
	_brackets = _brackets.filter(func(b: Dictionary) -> bool:
		return not (b.node == node and (kind == "" or b.kind == kind)))


func _draw_brackets() -> void:
	if world == null or not is_instance_valid(world.camera) or world.player == null:
		return
	var cam := world.camera
	var vp := _marks.size
	var s := vp.y / 480.0
	var keep: Array[Dictionary] = []
	for b in _brackets:
		var n = b.node
		if not is_instance_valid(n) or _time > b.until:
			continue
		if n is Aircraft and (n.state == Aircraft.State.DEAD or n.hidden):
			continue
		if not (n is Aircraft) and not n.visible:
			continue
		keep.append(b)
		var pos: Vector3 = (n as Node3D).global_position
		var colour: Color = COLOURS.get(b.kind, Color.WHITE)
		if b.kind == "threat":
			colour.a = 0.55 + 0.45 * sin(_time * 10.0)
		var dist := cam.global_position.distance_to(pos)
		var on_screen := not cam.is_position_behind(pos)
		var sp := cam.unproject_position(pos) if on_screen else Vector2.ZERO
		if on_screen and Rect2(Vector2.ZERO, vp).grow(-4.0).has_point(sp):
			if dist > float(b.range):
				continue
			var half := clampf(1600.0 / maxf(dist, 1.0), 9.0, 34.0) * s
			_corners(sp, half, colour, s)
			var text: String = b.label
			if (b.kind == "protect" or b.kind == "ally") and n is Aircraft:
				text = ("%s  %dm" % [text, int(dist / 2.5)]) if text != "" else "%dm" % int(dist / 2.5)
			if text != "":
				var fs := int(13 * s)
				var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				_marks.draw_string(_font, sp + Vector2(-w * 0.5, -half - 4.0 * s), text, HORIZONTAL_ALIGNMENT_LEFT,
					-1, fs, colour)
		elif b.arrow:
			_edge_arrow(cam, pos, vp, colour, b.label, s)
	_brackets = keep


func _corners(c: Vector2, h: float, col: Color, s: float) -> void:
	var l := h * 0.45
	var w := maxf(2.0 * s * 0.6, 1.5)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := c + Vector2(sx * h, sy * h)
			_marks.draw_line(p, p - Vector2(sx * l, 0), col, w)
			_marks.draw_line(p, p - Vector2(0, sy * l), col, w)


## An arrow on the screen edge toward an off-screen point (behind the camera: mirrored, so it points the way to turn).
func _edge_arrow(cam: Camera3D, pos: Vector3, vp: Vector2, col: Color, label: String, s: float) -> void:
	var local := cam.global_transform.affine_inverse() * pos
	var dir := Vector2(local.x, -local.y)
	if dir.length_squared() < 0.0001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var centre := vp * 0.5
	var margin := 30.0 * s
	var k := minf((centre.x - margin) / maxf(absf(dir.x), 0.001), (centre.y - margin) / maxf(absf(dir.y), 0.001))
	var tip := centre + dir * k
	tip.y = maxf(tip.y, 215.0 * s)  # below the speed dial, the map and the HUD lines at the top
	var side := Vector2(-dir.y, dir.x)
	var size := 11.0 * s
	_marks.draw_colored_polygon(PackedVector2Array([tip, tip - dir * size * 1.6 + side * size,
		tip - dir * size * 1.6 - side * size]), col)
	if label != "":
		var fs := int(12 * s)
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := tip - dir * size * 3.0
		_marks.draw_string(_font, at + Vector2(-w * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## A short shake of the view (camera offsets), e.g. when a burst hits.
func jolt(seconds := 0.35, amount := 1.2) -> void:
	_jolt = seconds
	_jolt_amount = amount


## Cue sounds: "objective" (two rising notes), "warning" (three short low notes), or a game sound file name.
func cue(name: String) -> void:
	var stream: AudioStream
	if name == "objective" or name == "warning":
		if not _cues.has(name):
			_cues[name] = _tones([[660.0, 0.11], [990.0, 0.22]] if name == "objective"
				else [[330.0, 0.09], [0.0, 0.05], [330.0, 0.09], [0.0, 0.05], [330.0, 0.14]])
		stream = _cues[name]
	else:
		stream = World.load_sound(name)
	if stream == null:
		return
	var p := _player if not _player.playing else AudioStreamPlayer.new()
	if p != _player:
		p.volume_db = _player.volume_db
		add_child(p)
		p.finished.connect(p.queue_free)
	p.stream = stream
	p.play()


## A short soft tone sequence ([hz, seconds], hz 0 = rest) as 16-bit mono PCM.
static func _tones(notes: Array) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	for n in notes:
		var hz: float = n[0]
		var count := int(float(n[1]) * rate)
		for i in count:
			var t := float(i) / rate
			var env := minf(t * 80.0, 1.0) * exp(-t * 9.0)
			var v := 0.0 if hz <= 0.0 else sin(TAU * hz * t) * env * 0.45 + sin(TAU * hz * 2.0 * t) * env * 0.12
			var sample := int(clampf(v, -1.0, 1.0) * 32767.0)
			data.append(sample & 0xff)
			data.append((sample >> 8) & 0xff)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
