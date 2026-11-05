extends CanvasLayer
## Red Baron screen overlays (not in the original): the wound effect (mission 8: the view dims, greys
## and blurs with a slow pulse) and a HUD counter line (mission 12). Drawn under the game's HUD layer.

var wound := 0.0  # 0 none .. 1 full
var _rect: ColorRect
var _mat: ShaderMaterial
var _counter: Label
var _time := 0.0

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


func _process(dt: float) -> void:
	_time += dt
	_rect.visible = wound > 0.0
	if wound > 0.0:
		# a slow pulse, like a heartbeat in the ears
		var pulse := 0.85 + 0.15 * sin(_time * 2.4)
		_mat.set_shader_parameter("amount", clampf(wound * pulse, 0.0, 1.0))


## A line of text at the top centre (below the timer), or "" to hide it.
func set_counter(text: String) -> void:
	if _counter == null:
		_counter = Label.new()
		_counter.anchor_left = 0.0
		_counter.anchor_right = 1.0
		_counter.offset_top = 52
		_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var fp := Ini.data_path("ui/morpheus.ttf")
		if ResourceLoader.exists(fp):
			_counter.add_theme_font_override("font", load(fp))
		_counter.add_theme_font_size_override("font_size", 26)
		_counter.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
		_counter.add_theme_color_override("font_shadow_color", Color.BLACK)
		var top := CanvasLayer.new()
		top.layer = 2
		add_child(top)
		top.add_child(_counter)
	_counter.text = text
	_counter.visible = text != ""
