class_name HtmlView
extends Control
## Renderer for the original menu pages (language/english/Menus/*.html, missions/*/mission.html).
## The game drew them with its own HTML engine (Dive5 dcphtmlmenu) on a 640x480 page. Parsing and layout
## follow that engine as decompiled:
##   parser   FUN_0040d648 (cell/body content), FUN_0040d94c (text), FUN_0040df35 (tags), FUN_0040eebe /
##            FUN_0040f119 / FUN_0040f2f3 (table, tr, td). Content becomes a flat object list per body or
##            cell: text, img, table and the markers br, p, center, /center plus the td align/valign value.
##            Whitespace-only text makes no object; text keeps a trailing "pad" space; <a> stays open
##            across cells until </a>; td without </td> runs on until </td>, </tr> or </table>.
##   layout   FUN_0040b0d8 lines objects up left to right, every item at the top of its line;
##            FUN_0040b4c1 flows text word by word (words cut to the width, a quirk on the first word);
##            FUN_0040ba6d places images (position taken before wrapping, so a wrapped image keeps the
##            old line's position); items that do not fit the height are dropped.
##            Tables (FUN_0040bd80): column widths = width attribute or natural width, then scaled to the
##            table width by FUN_0040bf13; row heights the same way; cells are clipped to their box.
##            FUN_0040c1b0 shifts each line for left/center/right and the block for top/middle/bottom.
##   spacing  set by the game (decomp RedAce.c:45788): br 0, wrap 0, paragraph 3, alignment 2, table 0.
##   fonts    FUN_004025e2 / FUN_004294b0: height 2 * size + 12, bold from <b>, glyphs drawn without
##            antialiasing.

signal link_clicked(href: String)

const PAGE := Vector2(640, 480)
const ART_SCALE := 4  # tools/build_assets.py MENU_ART_SCALE
const BR_SPACING := 0
const WRAP_SPACING := 0
const PARAGRAPH_SPACING := 3
const ALIGNMENT_SPACING := 2
const TABLE_SPACING := 0
const GROW_AUTO_TABLES := true
const GLYPH_EMBOLDEN_PX := 7.0  # embolden strength * em size (game fonts)
const CORE_EMBOLDEN_PX := 12.0  # the system fonts (Arial, Courier, ...) come out heavier at small sizes
const BOLD_EMBOLDEN := 0.6

var _root: Dictionary = {}  # parsed body: {objs, attrs}
var _items: Array[Dictionary] = []  # laid-out draw items in page space
var _links: Array[Dictionary] = []  # {href, rects, alink}
var _hover := -1
var _bg_tex: Texture2D
var _bg_color := Color.BLACK
var _base_dir := "language/english/"
var _font_cache := {}
var _tex_cache := {}
var _width_cache := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


# ---------------------------------------------------------------- public

func show_html(text: String) -> void:
	_root = _parse(text)
	_layout()
	_hover = -1
	queue_redraw()


## Resolve a page-relative path ("Menus\x.jpg") to the converted resource path.
func resource_path(src: String) -> String:
	var rel := src.replace("\\", "/").to_lower()
	if rel.begins_with("./"):
		rel = rel.substr(2)
	var base := rel.get_basename()
	for ext in [".png", ".jpg", ".bmp"]:
		var p := Ini.data_path(_base_dir + base + ext)
		if ResourceLoader.exists(p):
			return p
	return ""


# ---------------------------------------------------------------- parsing

static var _tag_re := RegEx.create_from_string("<(/?)([a-zA-Z!][a-zA-Z0-9]*)([^>]*)>")
static var _attr_re := RegEx.create_from_string("([a-zA-Z_][a-zA-Z0-9_-]*)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>\"'<]+)")
static var _space_re := RegEx.create_from_string("\\s+")


class Parser:
	var body := {"objs": [], "attrs": {}}
	var fonts: Array = []  # font stack: {face, size, color}
	var bold := false
	var pad := true
	var link := -1
	var links: Array = []
	var cont: Array = []  # current object list (body or cell), null outside cells
	var tables: Array = []  # open tables: {table, row, outer}


func _parse(text: String) -> Dictionary:
	var comment := RegEx.create_from_string("<!--[\\s\\S]*?-->")
	text = comment.sub(text, "", true)
	var p := Parser.new()
	p.fonts.append({"face": "arial", "size": 3, "color": Color.WHITE})
	p.cont = p.body.objs
	var in_cell := true  # body content, or inside a td
	var pos := 0
	var skip_title := false
	for m in _tag_re.search_all(text):
		if m.get_start() > pos and in_cell and not skip_title:
			_text(p, text.substr(pos, m.get_start() - pos))
		pos = m.get_end()
		var closing := m.get_string(1) == "/"
		var name := m.get_string(2).to_lower()
		var rest := m.get_string(3)
		if name.begins_with("td") and name.length() > 2:  # "<tdheight=19>"
			rest = name.substr(2) + rest
			name = "td"
		if name == "title":
			skip_title = not closing
			continue
		var attrs := {}
		for a in _attr_re.search_all(rest):
			var v := a.get_string(2)
			if v.begins_with("\"") or v.begins_with("'"):
				v = v.substr(1, v.length() - 2)
			attrs[a.get_string(1).to_lower()] = v
		var tag := ("/" if closing else "") + name
		# table structure (FUN_0040eebe, FUN_0040f119, FUN_0040f2f3)
		if not p.tables.is_empty():
			var t: Dictionary = p.tables.back()
			if in_cell:
				if tag in ["/td", "/th", "/tr", "/table", "/body"]:
					in_cell = false
					p.cont = []
					if tag in ["/td", "/th"]:
						continue
				elif tag == "table":
					pass  # nested table, handled below
				else:
					_tag(p, tag, attrs)
					continue
			if tag == "table":
				pass
			elif tag == "tr":
				t.row = []
				t.table.rows.append(t.row)
				continue
			elif tag in ["td", "th"]:
				if t.row == null:
					continue  # cells only open inside a row
				var cell := {"attrs": attrs, "objs": []}
				for k in ["align", "valign"]:
					if attrs.has(k):
						cell.objs.append({"type": String(attrs[k]).to_lower()})
				t.row.append(cell)
				p.cont = cell.objs
				in_cell = true
				continue
			elif tag == "/tr":
				t.row = null
				continue
			elif tag == "/table":
				p.tables.pop_back()
				p.cont = t.outer
				in_cell = true
				continue
			else:
				continue  # anything else between cells is skipped
		if tag == "table":
			var tbl := {"type": "table", "attrs": attrs, "rows": []}
			p.cont.append(tbl)
			p.tables.append({"table": tbl, "row": null, "outer": p.cont})
			in_cell = false
			continue
		if tag == "body":
			p.body.attrs = attrs
			continue
		_tag(p, tag, attrs)
	if pos < text.length() and in_cell:
		_text(p, text.substr(pos))
	_links.assign(p.links)
	return p.body


## Tags inside body or cell content (FUN_0040df35).
func _tag(p: Parser, tag: String, attrs: Dictionary) -> void:
	match tag:
		"br", "p", "center":
			p.cont.append({"type": tag})
		"/center":
			p.cont.append({"type": "/center"})
		"b":
			p.bold = true
		"/b":
			p.bold = false
		"nopad":
			p.pad = false
		"/nopad":
			p.pad = true
		"font":
			var f: Dictionary = p.fonts.back().duplicate()
			if attrs.has("face"):
				f.face = attrs.face
			if attrs.has("size"):
				f.size = int(String(attrs.size).to_int())
			if attrs.has("color"):
				f.color = _color(attrs.color, f.color)
			p.fonts.append(f)
		"/font":
			if p.fonts.size() > 1:
				p.fonts.pop_back()
		"a":
			p.link = p.links.size()
			p.links.append({"href": attrs.get("href", ""), "rects": [], "alink": Color.RED})
		"/a":
			p.link = -1
		"img":
			p.cont.append({"type": "img", "src": attrs.get("src", ""), "roll": attrs.get("rolloversrc", ""),
				"width": attrs.get("width", ""), "height": attrs.get("height", ""), "link": p.link})


## Text: whitespace-separated tokens joined by single spaces (FUN_0040d94c); &nbsp; is a non-breaking space.
func _text(p: Parser, t: String) -> void:
	t = _space_re.sub(t, " ", true).strip_edges()
	if t.is_empty():
		return
	t = t.replace("&nbsp;", char(0x7f)).replace("&quot;", "\"").replace("&lt;", "<").replace("&gt;", ">")
	t = t.replace("&amp;", "&")
	var f: Dictionary = p.fonts.back()
	p.cont.append({"type": "text", "text": t, "face": f.face, "size": f.size, "color": f.color,
		"bold": p.bold, "pad": p.pad, "link": p.link})


# ---------------------------------------------------------------- style helpers

static func _color(s: String, default: Color) -> Color:
	s = s.strip_edges().trim_prefix("#")
	if s.length() >= 6 and s.substr(0, 6).is_valid_hex_number():
		return Color.html("#" + s.substr(0, 6))
	match s.to_lower():
		"white": return Color.WHITE
		"black": return Color.BLACK
		"red": return Color.RED
	return default


## Font size as the original HTML engine sets it (decomp FUN_004025e2): cell height = size * 2 + 12
## pixels (a Windows font height). Converted to the em size that gives the same cell for this font.
static func _cell_px(size: int) -> int:
	return clampi(size, 0, 16) * 2 + 12


func _em_px(f: Font, size: int) -> int:
	var h := f.get_height(100)
	return maxi(int(round(_cell_px(size) * 100.0 / maxf(h, 1.0))), 6)


func _font(face: String, bold: bool) -> Font:
	var key := face + str(bold)
	if _font_cache.has(key):
		return _font_cache[key]
	var f := face.to_lower()
	var path := ""
	if f.contains("morpheus"):
		path = Ini.data_path("ui/morpheus.ttf")
	elif f.contains("anni"):
		path = Ini.data_path("ui/annifont.ttf")
	elif f.contains("courier"):
		path = "res://fonts/Courier_New_Bold.ttf" if bold else "res://fonts/Courier_New.ttf"
	elif f.contains("times"):
		path = "res://fonts/Times_New_Roman_Bold.ttf" if bold else "res://fonts/Times_New_Roman.ttf"
	elif f.begins_with("verdana"):
		path = "res://fonts/Verdana_Bold.ttf" if bold else "res://fonts/Verdana.ttf"
	else:  # arial / helvetica / the engine default ("arial", FUN_004025e2)
		path = "res://fonts/Arial_Bold.ttf" if bold else "res://fonts/Arial.ttf"
	var font: Font = ThemeDB.fallback_font
	if ResourceLoader.exists(path):
		var src = load(path)
		if src is FontFile:
			# the engine copies GDI glyphs as on/off pixels (FUN_00429758): no antialiasing
			var ff: FontFile = src.duplicate()
			ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			ff.hinting = TextServer.HINTING_NORMAL
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			font = ff
		else:
			font = src
	_font_cache[key] = font
	return font


## Font for drawing at page size px. The engine copies GDI glyphs as on/off pixels where every touched
## pixel is set (FUN_00429758), which thickens strokes by about a pixel at any size; fonts without a bold
## face are emboldened for <b> as GDI does for lfWeight 700. Measuring uses the plain font.
func _draw_font(f: Font, px: int, fake_bold: bool, game_font: bool) -> Font:
	var key := [f.get_instance_id(), px, fake_bold, game_font]
	if not _font_cache.has(key):
		var v := FontVariation.new()
		v.base_font = f
		v.variation_embolden = (GLYPH_EMBOLDEN_PX if game_font else CORE_EMBOLDEN_PX) / maxf(px, 1.0)
		if fake_bold:
			v.variation_embolden += BOLD_EMBOLDEN
		_font_cache[key] = v
	return _font_cache[key]


func _tex(src: String) -> Texture2D:
	if src.is_empty():
		return null
	if not _tex_cache.has(src):
		var p := resource_path(src)
		_tex_cache[src] = load(p) if p != "" else null
	return _tex_cache[src]


## Character advance in whole pixels, as GDI measures single characters (FUN_00429d16).
func _char_w(f: Font, px: int, c: int) -> int:
	var key := [f.get_instance_id(), px, c]
	if not _width_cache.has(key):
		_width_cache[key] = int(round(f.get_char_size(32 if c == 0x7f else c, px).x))
	return _width_cache[key]


# ---------------------------------------------------------------- layout

## Line state of one block (the engine's 8-int struct, FUN_0040ab50).
class Lines:
	var x := 0  # width of the current line
	var y := 0
	var maxw := 0
	var maxh := 0
	var lineh := 0
	var maxlinew := 0
	var maxlinew_np := 0  # without trailing pad spaces
	var maxy := 0
	var objs: Array = []  # placed: {"k": "br", w, tw} / {"k": "mark", v} / {"k": "item", ...}


## FUN_0040abca: end the line. Nothing happens on an empty line unless a spacing is given.
func _newline(l: Lines, spacing: int) -> void:
	if spacing == 0 and l.lineh == 0 and l.x == 0:
		return
	l.objs.append({"k": "br", "w": l.x, "tw": l.maxw})
	l.y += l.lineh + spacing
	l.x = 0
	l.lineh = 0
	l.maxy = maxi(l.maxy, l.y)


## FUN_0040acc8
func _would_wrap(l: Lines, w: int) -> bool:
	return l.y <= l.maxh and w <= l.maxw and l.x + w > l.maxw


## FUN_0040ad07: add an item to the line, wrapping first if needed; false when it does not fit.
func _add(l: Lines, w: int, h: int) -> bool:
	if l.maxh < l.y or l.maxw < w:
		return false
	if _would_wrap(l, w):
		_newline(l, WRAP_SPACING)
		if l.maxh < l.y:
			return false
	l.lineh = maxi(l.lineh, h)
	l.x += w
	l.maxlinew = maxi(l.maxlinew, l.x)
	l.maxlinew_np = maxi(l.maxlinew_np, l.x)
	return true


## FUN_0040b0d8: lay out an object list in a w x h box. Returns {w, h, objs} with aligned positions.
func _flow(objs: Array, w: int, h: int) -> Dictionary:
	var l := Lines.new()
	l.maxw = w
	l.maxh = h
	for o in objs:
		match o.type:
			"br":
				_newline(l, BR_SPACING)
			"p":
				_newline(l, PARAGRAPH_SPACING)
			"left", "center", "right", "top", "middle", "bottom", "justify", "baseline":
				_newline(l, ALIGNMENT_SPACING)
				l.objs.append({"k": "mark", "v": o.type})
			"/center":
				_newline(l, ALIGNMENT_SPACING)
				l.objs.append({"k": "mark", "v": "left"})
			"text":
				_flow_text(l, o)
			"img":
				var tex := _tex(o.src)
				# page art is stored ART_SCALE x larger (Real-ESRGAN); layout uses the original pixel size
				var iw := int(String(o.width).to_int()) if String(o.width) != "" else (tex.get_width() / ART_SCALE if tex else 0)
				var ih := int(String(o.height).to_int()) if String(o.height) != "" else (tex.get_height() / ART_SCALE if tex else 0)
				var px := l.x
				var py := l.y
				if _add(l, iw, ih):
					l.objs.append({"k": "item", "type": "img", "x": px, "y": py, "w": iw, "h": ih, "tex": tex,
						"roll": _tex(o.roll), "link": o.link})
			"table":
				var size := _table(o, l.maxw, l.maxh)
				_newline(l, TABLE_SPACING)
				var px := l.x
				var py := l.y
				# a grown table takes the full line and runs over the right edge
				if _add(l, mini(size.x, l.maxw), size.y):
					l.objs.append({"k": "item", "type": "table", "x": px, "y": py, "w": size.x, "h": size.y,
						"cells": o.get("_cells", []), "over": maxi(size.x - l.maxw, 0)})
					_newline(l, TABLE_SPACING)
	_newline(l, 0)
	var content_h := l.maxy + l.lineh
	_align(l.objs, h, content_h)
	return {"w": l.maxlinew, "wn": l.maxlinew_np, "h": content_h, "objs": l.objs}


## FUN_0040b4c1: text flows word by word; a fragment is emitted per line.
func _flow_text(l: Lines, o: Dictionary) -> void:
	var f := _font(o.face, o.bold)
	var px := _em_px(f, o.size)
	var h := _cell_px(o.size)
	var sp := _char_w(f, px, 32)
	var col: Color = o.color
	var face := String(o.face).to_lower()
	var game_font := face.contains("morpheus") or face.contains("anni")
	var df := _draw_font(f, px, o.bold and game_font, game_font)
	var fx := l.x
	var fy := l.y
	var frag := ""
	var frag_w := 0
	for word: String in o.text.split(" ", false):
		var ww := 0
		for i in word.length():
			var cw := _char_w(f, px, word.unicode_at(i))
			if ww + cw > l.maxw:
				word = word.substr(0, i)
				break
			ww += cw
		if frag.is_empty():
			if not _would_wrap(l, ww + sp):
				if not _add(l, ww, h):
					return
			else:
				# the engine starts a new line here without counting the word on it
				_newline(l, WRAP_SPACING)
				fx = l.x
				fy = l.y
			frag = word
			frag_w = ww
		elif not _would_wrap(l, ww + sp):
			_add(l, ww + sp, h)
			frag += " " + word
			frag_w += sp + ww
		else:
			_emit_text(l, frag, fx, fy, frag_w, h, f, df, px, col, o.link)
			_newline(l, WRAP_SPACING)
			fx = l.x
			fy = l.y
			if not _add(l, ww, h):
				return
			frag = word
			frag_w = ww
	if not frag.is_empty():
		_emit_text(l, frag, fx, fy, frag_w, h, f, df, px, col, o.link)
	if o.pad and l.x != 0:
		# the pad space counts towards the engine's width, not the drawn natural width (deviation)
		var natural := l.maxlinew_np
		if _add(l, sp, 0):
			l.maxlinew_np = maxi(natural, l.x - sp)


func _emit_text(l: Lines, s: String, x: int, y: int, w: int, h: int, f: Font, df: Font, px: int,
		col: Color, link: int) -> void:
	l.objs.append({"k": "item", "type": "text", "text": s.replace(char(0x7f), " "), "x": x, "y": y, "w": w,
		"h": h, "font": f, "dfont": df, "px": px, "color": col, "link": link})


## FUN_0040c1b0: shift every line by its alignment, and the whole block for top/middle/bottom.
func _align(objs: Array, box_h: int, content_h: int) -> void:
	var halign := 0  # 0 left, 1 right, 2 center
	var dy := 0
	var dx := 0
	var i := 0
	var n := objs.size()
	while i < n:
		var o: Dictionary = objs[i]
		var marker := false
		if o.k == "mark":
			marker = true
			match o.v:
				"left": halign = 0
				"center": halign = 2
				"right": halign = 1
				"top": dy = 0
				"middle": dy = (box_h - content_h) / 2
				"bottom": dy = box_h - content_h
		elif o.k == "br":
			marker = true
		if not marker:
			var j := i
			while j < n:
				if objs[j].k == "br":
					var lw: int = objs[j].w
					var tw: int = objs[j].tw
					dx = 0 if halign == 0 else (tw - lw if halign == 1 else (tw - lw) >> 1)
					break
				j += 1
			while i < j:
				if objs[i].k == "item":
					objs[i].x += dx
					objs[i].y += dy
					# a grown table overflows evenly when centred, to the left when right-aligned
					var over: int = objs[i].get("over", 0)
					objs[i].x -= over if halign == 1 else (over >> 1 if halign == 2 else 0)
				i += 1
		i += 1


## FUN_0040bf13: fit column widths (or row heights) to the table size. Returns the table size.
static func _fit(sizes: Array, fixed: Array, has_attr: bool, total: int) -> int:
	var sum := 0
	var fixed_sum := 0
	for i in sizes.size():
		sum += sizes[i]
		if fixed[i]:
			fixed_sum += sizes[i]
	if total < sum:
		for i in sizes.size():
			if total < fixed_sum:
				sizes[i] = sizes[i] * total / sum
			else:
				sizes[i] = sizes[i] * (total - fixed_sum) / (sum - fixed_sum)
		return total
	if not has_attr:
		return sum
	if sum == 0:
		sizes.fill(0)
		return total
	for i in sizes.size():
		sizes[i] = sizes[i] * total / sum
	return total


## FUN_0040afa3
static func _grow(sizes: Array, fixed: Array, i: int, v: int, is_fixed: bool) -> void:
	if i < sizes.size():
		sizes[i] = maxi(sizes[i], v)
		if is_fixed:
			fixed[i] = true
	else:
		while sizes.size() <= i:
			sizes.append(0)
			fixed.append(false)
		sizes[i] = v
		fixed[i] = is_fixed


## FUN_0040bd80: size a table in an aw x ah box and lay out its cells (stored in t._cells).
func _table(t: Dictionary, aw: int, ah: int) -> Vector2i:
	var a: Dictionary = t.attrs
	var tw := int(String(a.width).to_int()) if a.has("width") else aw
	var th := int(String(a.height).to_int()) if a.has("height") else ah
	var col_w: Array = []
	var col_fixed: Array = []
	var nat_w: Array = []
	var nat_fixed: Array = []
	for r in t.rows:
		for c in r.size():
			var cell: Dictionary = r[c]
			if cell.attrs.has("width"):
				_grow(col_w, col_fixed, c, int(String(cell.attrs.width).to_int()), true)
				_grow(nat_w, nat_fixed, c, int(String(cell.attrs.width).to_int()), true)
			else:
				var m := _flow(cell.objs, aw, ah)
				_grow(col_w, col_fixed, c, m.w, false)
				_grow(nat_w, nat_fixed, c, m.wn, false)
	# deviation: a table without a width draws its cells at their natural widths (the exe squeezed
	# them, cutting "Controller"/"Sensitivity", wrapping "Fire Second Weapon" and pushing the volume
	# bars' end caps out of sight). Row heights still come from the squeezed widths, so every row keeps
	# the original's position; the table may run a few pixels past its cell.
	var natural_w: Array = nat_w
	tw = _fit(col_w, col_fixed, a.has("width"), tw)
	if GROW_AUTO_TABLES and not a.has("width"):
		var grown := 0
		for w in natural_w:
			grown += w
		if grown > tw:
			tw = grown
		else:
			natural_w = col_w
	else:
		natural_w = col_w
	var row_h: Array = []
	var row_fixed: Array = []
	for ri in t.rows.size():
		var r: Array = t.rows[ri]
		if r.is_empty():
			_grow(row_h, row_fixed, ri, 0, false)
		for c in r.size():
			var cell: Dictionary = r[c]
			if cell.attrs.has("height"):
				_grow(row_h, row_fixed, ri, int(String(cell.attrs.height).to_int()), true)
			else:
				_grow(row_h, row_fixed, ri, _flow(cell.objs, col_w[c], ah).h, false)
	th = _fit(row_h, row_fixed, a.has("height"), th)
	var cells: Array = []
	var y := 0
	for ri in t.rows.size():
		var r: Array = t.rows[ri]
		var x := 0
		var rh: int = row_h[ri] if ri < row_h.size() else 0
		for c in r.size():
			var cw: int = natural_w[c]
			cells.append({"x": x, "y": y, "w": cw, "h": rh, "objs": _flow(r[c].objs, cw, rh).objs})
			x += cw
		y += rh
	t._cells = cells
	return Vector2i(tw, th)


func _layout() -> void:
	_items.clear()
	for l in _links:
		l.rects = []
	var attrs: Dictionary = _root.get("attrs", {})
	_bg_color = _color(attrs.get("bgcolor", "#000000"), Color.BLACK)
	_bg_tex = _tex(attrs.get("background", ""))
	var link_col := _color(attrs.get("link", "#0000ee"), Color(0.2, 0.2, 1))
	var alink_col := _color(attrs.get("alink", "#ff0000"), Color.RED)
	for l in _links:
		l.alink = alink_col
	var page := _flow(_root.get("objs", []), int(PAGE.x), int(PAGE.y))
	_place(page.objs, Vector2.ZERO, Rect2(Vector2.ZERO, PAGE), link_col)


## Flatten laid-out objects into page-space draw items, clipped to their cell (FUN_00401ec3 / 0040116a).
func _place(objs: Array, origin: Vector2, clip: Rect2, link_col: Color) -> void:
	for o in objs:
		if o.k != "item":
			continue
		var r := Rect2(origin + Vector2(o.x, o.y), Vector2(o.w, o.h))
		if o.type == "table":
			for c in o.cells:
				var cr := Rect2(r.position + Vector2(c.x, c.y), Vector2(c.w, c.h))
				var cc := cr.intersection(clip)
				if cc.has_area():
					_place(c.objs, cr.position, cc, link_col)
			continue
		var vis := r.intersection(clip)
		if not vis.has_area():
			continue
		var it: Dictionary = o.duplicate()
		it.rect = r
		it.clip = vis
		if it.type == "text":
			it.pos = r.position + Vector2(0, it.font.get_ascent(it.px))
			if it.link >= 0:
				it.color = link_col
		_items.append(it)
		if it.link >= 0 and it.link < _links.size():
			_links[it.link].rects.append(vis)


# ---------------------------------------------------------------- drawing and input

func _page_xform() -> Array:
	var s := minf(size.x / PAGE.x, size.y / PAGE.y)
	var off := (size - PAGE * s) * 0.5
	return [s, off]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var x: Array = _page_xform()
	var s: float = x[0]
	var off: Vector2 = x[1]
	draw_rect(Rect2(off, PAGE * s), _bg_color)
	if _bg_tex:
		draw_texture_rect(_bg_tex, Rect2(off, PAGE * s), false)
	for it in _items:
		var hover: bool = it.link >= 0 and it.link == _hover
		var r: Rect2 = it.rect
		var vis: Rect2 = it.clip
		if it.type == "img":
			var t: Texture2D = it.roll if hover and it.roll else it.tex
			if t == null or r.size.x <= 0 or r.size.y <= 0:
				continue
			# source region of the visible part (the image is stretched to its width/height)
			var ts := Vector2(t.get_size())
			var src := Rect2((vis.position - r.position) / r.size * ts, vis.size / r.size * ts)
			draw_texture_rect_region(t, Rect2(off + vis.position * s, vis.size * s), src)
		else:
			# glyph by glyph at the measured advances (emboldening widens the font's own advances)
			var col: Color = _links[it.link].alink if hover else it.color
			var fs := int(round(it.px * s))
			var gx: float = it.pos.x
			for i in it.text.length():
				var c: int = it.text.unicode_at(i)
				draw_char(it.dfont, off + Vector2(gx, it.pos.y) * s, char(c), fs, col)
				gx += _char_w(it.font, it.px, c)


func _link_at(p: Vector2) -> int:
	var x: Array = _page_xform()
	var q: Vector2 = (p - x[1]) / x[0]
	for i in _links.size():
		for r in _links[i].rects:
			if (r as Rect2).has_point(q):
				return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _link_at(event.position)
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var h := _link_at(event.position)
		if h >= 0:
			accept_event()
			link_clicked.emit(_links[h].href)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
