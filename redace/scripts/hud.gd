class_name Hud
extends Control
## In-flight HUD drawn like the original (decomp FUN_0042f026 status dial, FUN_0042f7db map,
## FUN_0042fdc0 map icons). Coordinates are the original pixel values at 480 lines, scaled to the window.
##   status dial: speeddial.bmp 128x128 at the top left; speedo.bmp needle shows the throttle at
##     angle 0.628 - throttle * 1.256 on an arc (centre 64,85, radius 35, y squashed 0.75);
##     bullet holes along the lower arc (radius 42) - one per 1/9 of endurance lost, at most 10;
##     bomb or rocket icon at 36..68 x 70..102 and the remaining count at 66,68.
##   map: disc of radius 58 centred 92 px from the top right, map texture radius 0.2, heading up;
##     compass ring (128 px) rotated with the heading; icons for groups 6 (AA guns), 7 (targets),
##     8 (allies), 9 (enemies) placed at offset * 256 / map size, clamped to 46 px (half alpha when clamped).
##   timer: top centre on timed missions.

const GROUP_AA := 6
const GROUP_TARGET := 7
const GROUP_ALLY := 8
const GROUP_ENEMY := 9

var world: World
var map_texture: Texture2D
var hit_flash := 0.0  # 1 when hit, fades out (original 0x3c4)

var _tex := {}
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in ["speeddial", "speedo", "compass", "planeicon", "smallally", "smallenemy", "smalltarget",
			"gun", "bomb", "rocket", "bullethole"]:
		var p := Ini.data_path("ui/%s.png" % n)
		if ResourceLoader.exists(p):
			_tex[n] = with_mipmaps(load(p))
	# the bitmaps are stored 4-8x the original size and drawn smaller: sample from mipmaps
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var fp := Ini.data_path("ui/morpheus.ttf")
	_font = load(fp) if ResourceLoader.exists(fp) else ThemeDB.fallback_font


static func with_mipmaps(t: Texture2D) -> Texture2D:
	var img := t.get_image()
	if img == null:
		return t
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _process(dt: float) -> void:
	hit_flash = maxf(hit_flash - dt * 2.0, 0.0)
	queue_redraw()


func _draw() -> void:
	if world == null or world.player == null:
		return
	var s := size.y / 480.0
	_draw_status(world.player, s)
	_draw_map(world.player, s)
	if world.time_limit > 0.0:
		var left := maxf(world.time_limit - world.mission_time, 0.0)
		var txt := "%d:%02d" % [int(left) / 60, int(left) % 60]
		var fs := int(28 * s)
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, Vector2(size.x * 0.5 - w * 0.5, 34 * s), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1, 0.9, 0.5) if left > 10.0 else Color(1, 0.3, 0.2))


func _draw_status(p: Aircraft, s: float) -> void:
	if _tex.has("speeddial"):
		draw_texture_rect(_tex.speeddial, Rect2(Vector2.ZERO, Vector2(128, 128) * s), false)
	# throttle needle: base on an arc, pointing outward
	var a := 0.628 - p.throttle * 1.256
	var base := Vector2(64.0 - sin(a) * 35.0, 85.0 - cos(a) * 35.0 * 0.75) * s
	if _tex.has("speedo"):
		draw_set_transform(base, -a, Vector2(s, s))
		draw_texture_rect(_tex.speedo, Rect2(-16, -32, 32, 32), false)
		draw_set_transform(Vector2.ZERO)
	# damage: bullet holes along the bottom arc
	var damage := p.endurance - p.health
	var step := p.endurance / 9.0
	var holes := 0
	while holes < 10 and holes * step < damage:
		holes += 1
	for i in holes:
		var b := 0.9106 - i * 0.18212
		var c := Vector2(64.0 - sin(b) * 42.0, cos(b) * 42.0 * 0.95 + 85.0) * s
		if _tex.has("bullethole"):
			draw_set_transform(c, -b, Vector2(s, s))
			draw_texture_rect(_tex.bullethole, Rect2(-4, -4, 8, 8), false)
			draw_set_transform(Vector2.ZERO)
		if i == holes - 1 and hit_flash > 0.0:
			var r := (1.0 - hit_flash) * 30.0 * s
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), Color(1, 0, 0, hit_flash * 0.6))
	# bombs / rockets: icon by ordnance type, count always (decomp FUN_0042f026 prints it unconditionally)
	if p.ordnance_type in [1, 2]:
		var icon: Texture2D = _tex.get("bomb" if p.ordnance_type == 1 else "rocket")
		if icon:
			draw_texture_rect(icon, Rect2(Vector2(36, 70) * s, Vector2(32, 32) * s), false)
	draw_string(_font, Vector2(66, 68 + 26) * s, str(p.ordnance_left), HORIZONTAL_ALIGNMENT_LEFT, -1,
		int(24 * s), Color(1, 1, 1))


## Heading angle as the original computes it: atan(at.z / at.x) (+pi when at.x >= 0) - pi/2.
func _heading(p: Aircraft) -> float:
	var at := p.flight_basis.z
	var h := atan(at.z / at.x) if not is_zero_approx(at.x) else PI * 0.5 * signf(at.z)
	if at.x >= 0.0:
		h += PI
	return h - PI * 0.5


func _draw_map(p: Aircraft, s: float) -> void:
	var bounds := world.map_bounds
	if bounds.size.x <= 0.0:
		return
	var centre := Vector2(size.x - 92.0 * s, 92.0 * s)
	var h := _heading(p)
	var uv0 := Vector2((p.global_position.x - bounds.position.x) / bounds.size.x,
		(p.global_position.z - bounds.position.y) / bounds.size.y)
	if map_texture:
		# 10-segment disc, texture coordinates rotated by the heading
		var pts := PackedVector2Array([centre])
		var uvs := PackedVector2Array([uv0])
		for i in 11:
			var ang := i * 0.628318
			pts.append(centre + Vector2(cos(ang), sin(ang)) * 58.0 * s)
			uvs.append(uv0 + Vector2(cos(h + ang), sin(h + ang)) * 0.2)
		var cols := PackedColorArray()
		cols.resize(pts.size())
		cols.fill(Color(1, 1, 1, 0.8))
		draw_polygon(pts, cols, uvs, map_texture)
	if _tex.has("compass"):
		# quad corners at 45 deg, radius 128; texture coordinates radius 1 rotated by the heading
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for k in 4:
			var ang := 0.785 + k * 1.57
			pts.append(centre + Vector2(cos(ang), sin(ang)) * 128.0 * s)
			uvs.append(Vector2(0.5, 0.5) + Vector2(cos(h + k * 1.57), sin(h + k * 1.57)))
		draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs, _tex.compass)

	var icon_centre := Vector2(size.x - 90.0 * s, 90.0 * s)
	var scale := Vector2(256.0 / bounds.size.x, 256.0 / bounds.size.y)
	var right := p.flight_basis.x  # RenderWare "right" = model +x (appears on the left)
	var at := p.flight_basis.z
	for t in world.targets:
		if t.dead:
			continue
		var g: int = t.groups
		if g & (1 << GROUP_AA):
			_icon("gun", t.node.global_position, p, right, at, scale, icon_centre, s)
		elif g & (1 << GROUP_TARGET):
			_icon("smalltarget", t.node.global_position, p, right, at, scale, icon_centre, s)
	for q in world.planes:
		if q == p or not q.present():
			continue
		if q.groups & (1 << GROUP_ENEMY):
			_icon("smallenemy", q.global_position, p, right, at, scale, icon_centre, s)
		elif q.groups & (1 << GROUP_ALLY):
			_icon("smallally", q.global_position, p, right, at, scale, icon_centre, s)
	_icon("planeicon", p.global_position, p, right, at, scale, icon_centre, s)


func _icon(name: String, pos: Vector3, p: Aircraft, right: Vector3, at: Vector3, scale: Vector2,
		centre: Vector2, s: float) -> void:
	var tex: Texture2D = _tex.get(name)
	if tex == null:
		return
	var d := Vector3((pos.x - p.global_position.x) * scale.x, 0.0, (pos.z - p.global_position.z) * scale.y)
	var alpha := 1.0
	var len := d.length()
	if len > 46.0:
		d *= 46.0 / len
		alpha = 0.5
	var off := Vector2(-right.dot(d), -at.dot(d)) * s
	draw_texture_rect(tex, Rect2(centre + off - Vector2(4, 4) * s, Vector2(8, 8) * s), false, Color(1, 1, 1, alpha))
