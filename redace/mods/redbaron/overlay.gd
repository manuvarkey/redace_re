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

## Brackets, labels and edge arrows in the 3D view are switched off (user request, 11 November 2026: targets are
## found on the minimap only). Missions still add and remove them, so setting this true brings them back.
const SHOW_BRACKETS := false

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
var _box: VBoxContainer  # the counter and objective lines
var _message_top := -1.0  # World's message line, as World placed it
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
	_keep_message_clear()


## World's status messages sit at a fixed height; with several HUD lines (mission 12: four pilots, a distance and
## the objective) the box reaches below it. Moves the message line down under the box while it would overlap.
func _keep_message_clear() -> void:
	if world == null or not is_instance_valid(world.message_label):
		return
	if _message_top < 0.0:
		_message_top = world.message_label.offset_top
	var top := _message_top
	if _box and _box.visible and (_counter.visible or _objective.visible):
		top = maxf(top, _box.get_global_rect().end.y + 10.0)
	world.message_label.offset_top = top


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
	_box = box
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
	if not SHOW_BRACKETS:
		return
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


## Letterbox bars (top and bottom) with a caption, for a short scripted camera cut-in; off removes them.
var _bars: Array[ColorRect] = []
var _caption: Label


func letterbox(on: bool, caption := "") -> void:
	if _bars.is_empty():
		for top in [true, false]:
			var r := ColorRect.new()
			r.color = Color.BLACK
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.anchor_left = 0.0
			r.anchor_right = 1.0
			r.anchor_top = 0.0 if top else 0.86
			r.anchor_bottom = 0.14 if top else 1.0
			_top.add_child(r)
			_bars.append(r)
		_caption = _label(0, 22, Color(0.95, 0.92, 0.8))
		_caption.anchor_top = 0.89
		_caption.anchor_bottom = 0.89
	for r in _bars:
		r.visible = on
	_caption.text = caption
	_caption.visible = on


func letterbox_caption(text: String) -> void:
	if _caption:
		_caption.text = text


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


# ---------------------------------------------------------------- the campaign's closing sequence (mission 12)

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _title: Label
var _muffle_fx: AudioEffectLowPassFilter
var _muffle_bus := -1


## A black screen over everything (the HUD included): 0 clear .. 1 black.
func fade(alpha: float) -> void:
	_fade_nodes()
	_fade_rect.color.a = clampf(alpha, 0.0, 1.0)
	_fade_rect.visible = alpha > 0.0


## A line of text centred on the screen, over the fade; "" hides it. alpha fades it in and out.
func title(text: String, alpha := 1.0) -> void:
	_fade_nodes()
	_title.text = text
	_title.modulate.a = clampf(alpha, 0.0, 1.0)
	_title.visible = text != ""


func _fade_nodes() -> void:
	if _fade_layer:
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 10
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.visible = false
	_fade_layer.add_child(_fade_rect)
	_title = Label.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", _font)
	_title.add_theme_font_size_override("font_size", 34)
	_title.add_theme_color_override("font_color", Color(0.93, 0.9, 0.82))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.visible = false
	_fade_layer.add_child(_title)


## Muffles every sound (a low-pass on the Master bus) and turns it down: 0 normal .. 1 dull and quiet. Removed
## again with 0, and always when the overlay goes (the bus outlives the flight).
func muffle(amount: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if amount <= 0.0:
		_unmuffle()
		return
	if _muffle_fx == null:
		_muffle_fx = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(bus, _muffle_fx)
		_muffle_bus = bus
		set_meta("volume_db", AudioServer.get_bus_volume_db(bus))
	amount = clampf(amount, 0.0, 1.0)
	_muffle_fx.cutoff_hz = lerpf(8000.0, 350.0, amount)
	AudioServer.set_bus_volume_db(bus, float(get_meta("volume_db")) - 18.0 * amount)


func _unmuffle() -> void:
	if _muffle_fx == null:
		return
	for i in AudioServer.get_bus_effect_count(_muffle_bus):
		if AudioServer.get_bus_effect(_muffle_bus, i) == _muffle_fx:
			AudioServer.remove_bus_effect(_muffle_bus, i)
			break
	AudioServer.set_bus_volume_db(_muffle_bus, float(get_meta("volume_db")))
	_muffle_fx = null


func _exit_tree() -> void:
	_unmuffle()


# ---------------------------------------------------------------- the frozen last frame (mission 12)

var _freeze_rect: TextureRect
var _freeze_mat: ShaderMaterial

const FREEZE_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;  // 0 sharp .. 1 blurred and red
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * (1.0 + amount * 7.0);
	vec3 c = vec3(0.0);
	float w = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float k = 1.0 / (1.0 + float(x * x + y * y));
			c += texture(TEXTURE, UV + vec2(float(x), float(y)) * px).rgb * k;
			w += k;
		}
	}
	c /= w;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	vec3 red = vec3(lum * 1.25 + 0.06, lum * 0.32, lum * 0.24);
	c = mix(c, red, amount * 0.7);
	vec2 d = UV - 0.5;
	c *= 1.0 - amount * 0.6 * dot(d, d) * 2.5;
	COLOR = vec4(c, 1.0);
}
"""


## Holds img (the last rendered frame) over everything, under the title; null: nothing to hold (headless).
func freeze(img: Image) -> void:
	_fade_nodes()
	if _freeze_rect == null:
		_freeze_rect = TextureRect.new()
		_freeze_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_freeze_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_freeze_rect.stretch_mode = TextureRect.STRETCH_SCALE
		_freeze_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_freeze_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = FREEZE_SHADER
		_freeze_mat.shader = sh
		_freeze_rect.material = _freeze_mat
		_fade_layer.add_child(_freeze_rect)
		_fade_layer.move_child(_freeze_rect, 0)  # under the fade and the title
	if img != null and not img.is_empty():
		_freeze_rect.texture = ImageTexture.create_from_image(img)
	_freeze_rect.visible = true


func freeze_amount(k: float) -> void:
	if _freeze_mat:
		_freeze_mat.set_shader_parameter("amount", clampf(k, 0.0, 1.0))
