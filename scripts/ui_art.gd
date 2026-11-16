class_name UiArt
extends RefCounted
## Quiet industrial surfaces, shared typography and clear interaction states.

const FONT = preload("res://assets/fonts/bunkercrew/body.tres")
const MENU_FONT = preload("res://assets/fonts/bunkercrew/menu.tres")
const TITLE_FONT = preload("res://assets/fonts/bunkercrew/title.tres")
const ICONS = preload("res://assets/ui/icons.png")
const PICKUP_ART = preload("res://scripts/pickup_art.gd")
## Built by tools/build_material_icons.py; provenance in the adjacent source JSON.
const MATERIAL_ICONS = preload("res://assets/ui/materials/materials_v1.png")
const MATERIAL_ICON_COLUMNS := {"steel":0, "concrete":1, "scrap":2, "ammo":3}
const IVORY := Color("e0decb")
## Secondary text. Lifted from a1a18c: thin pixel strokes lose about a third of
## their intensity to anti-aliasing at fractional window scales, so hint and
## caption rows need ~9:1 nominal contrast on the dark plates to read as ~7:1.
const MUTED := Color("b6b49f")
const AMBER := Color("d9ac60")
const STEEL := Color("3b453d")
const EDGE := Color("63726c")
const SHADOW := Color("172529")
const RED := Color("c65b47")
const GREEN := Color("a8b976")
## Shared style tokens. Screens take spacing, text sizes and state colours from
## here instead of carrying one-off numbers. Spacing sits on a 4 px grid.
const SPACE_1 := 4.0
const SPACE_2 := 8.0
const SPACE_3 := 12.0
const SPACE_4 := 16.0
const SPACE_6 := 24.0
const SPACE_8 := 32.0
## Text sizes in design pixels (1440x900). TEXT_MICRO is the smallest size a
## label may use; anything smaller is unreadable in a 960x600 window.
## The Field face has 10-square capitals and 7-square lowercase on a 14 px em,
## so at 1920x1080 (1.2 real pixels per design pixel) a size of S px gives
## capitals of 0.86*S and lowercase of 0.6*S real pixels. Menu copy follows a
## floor measured on lowercase, not on capitals:
## - TEXT_LABEL for short UPPERCASE captions (11 px capitals at 1080p);
## - TEXT_NOTE for secondary sentences: descriptions, hints, stat lines
##   (9 px lowercase, 13 px capitals at 1080p);
## - TEXT_LEAD and up for primary reading copy.
## Nothing a player reads in a menu sentence goes below TEXT_NOTE.
const TEXT_MICRO := 12
const TEXT_LABEL := 13
const TEXT_BODY := 14
const TEXT_NOTE := 15
const TEXT_LEAD := 16
const TEXT_HEADING := 24
const TEXT_DISPLAY := 28
## Screen titles in the Signal face. Signal rasterises as a nearest-sampled
## pixel grid (one square per 14 px); 35 design px lands on whole squares at
## the common outputs, 3 px per square at 1920x1080 and 4 px at 2560x1440, so
## every stem keeps one width (36 gave alternating 3/4 px stems).
const TEXT_SIGNAL := 35
## State colours: one meaning each, on every screen.
const SURFACE := Color("19221e")
const SURFACE_RAISED := Color("33423a")
const SURFACE_HOVER := Color("405245")
const SURFACE_PRESSED := Color("242f29")
## Disabled: a sunken plate darker than the panel around it, framed on every
## side by a thin cold rim (so it still reads as a control, never as a ghost),
## with dim but readable type (about 5:1) and a lock cue drawn by the trim.
const SURFACE_DISABLED := Color("121a17")
const BORDER := Color("7d8a7c")
const BORDER_HOVER := Color("c9c6a4")
const BORDER_DISABLED := Color("46524b")
const TEXT_DISABLED := Color("979b8b")
const TEXT_HOVER := Color("fff0c7")
const SCRIM := Color(0.01,0.015,0.018,0.61)
const INK := Color("142327")
const ICON_NAMES := ["workshop","wall","fortress","rifle","shotgun","arcgun","boots","harness","craftsmanship","core","helmet","ammo","limestone","glass","lock","check","tungsten","alloy"]
static var _skins: Dictionary = {}
static var _slider_handle: ImageTexture
static var _steel_grain: ImageTexture
static var _switch_icons: Dictionary = {}
static var _theme: Theme


static func skin(kind: String = "normal") -> StyleBoxFlat:
	if _skins.has(kind):
		return _skins[kind]
	# An enabled control is a raised, lit surface with a firm lower edge. A
	# disabled one is flat and sinks into the plate, so the two never look alike.
	var style := StyleBoxFlat.new()
	style.bg_color = SURFACE_RAISED
	style.border_width_bottom = 2
	style.border_color = BORDER
	style.shadow_color = Color(0.025,0.045,0.05,0.5)
	style.shadow_size = 0
	style.shadow_offset = Vector2(0,2)
	var press_shift := 0
	match kind:
		"hover":
			style.bg_color = SURFACE_HOVER
			style.border_color = BORDER_HOVER
		"pressed":
			style.bg_color = SURFACE_PRESSED
			style.border_color = AMBER
			style.border_width_bottom = 1
			style.border_width_top = 1
			press_shift = 1
		"disabled":
			style.bg_color = SURFACE_DISABLED
			style.set_border_width_all(1)
			style.border_color = BORDER_DISABLED
		"focus":
			style.draw_center = false
			style.set_border_width_all(2)
			style.shadow_size = 0
			style.border_color = AMBER
		"input_focus":
			style.border_width_bottom = 2
			style.border_color = AMBER
	style.anti_aliasing = false
	style.content_margin_left = 16
	style.content_margin_right = 16
	# The pressed label drops one pixel with its surface.
	style.content_margin_top = 8+press_shift
	style.content_margin_bottom = 8-press_shift
	_skins[kind] = style
	return style


static func panel(node: CanvasItem, rect: Rect2, active: bool = false) -> void:
	plate(node,rect,active)


static func plate(node: CanvasItem, rect: Rect2, active: bool = false, opacity: float = 1.0) -> void:
	# One material surface; hierarchy comes from spacing and type, not frames.
	rect = Rect2(rect.position.round(),rect.size.round())
	node.draw_rect(rect,Color(.098,.133,.118,.985*opacity))
	node.draw_texture_rect(steel_grain(),rect.grow(-2),true,Color(1,1,1,.35*opacity))
	node.draw_line(rect.position,rect.position+Vector2(rect.size.x,0),Color(.42,.46,.37,.7*opacity),1)
	if active:
		node.draw_rect(Rect2(rect.position,Vector2(3,rect.size.y)),Color(AMBER,opacity))


## Dimming layer between the live scene and a reading surface.
static func scrim(node: CanvasItem, rect: Rect2, opacity: float = 1.0) -> void:
	node.draw_rect(rect,Color(SCRIM,SCRIM.a*opacity))


## Real output pixels per design pixel for `node` (window stretch included):
## 1.2 at 1920x1080, 2/3 in the minimum 960x600 window.
static func output_scale(node: CanvasItem) -> float:
	if not is_instance_valid(node) or not node.is_inside_tree(): return 1.0
	return absf(node.get_viewport().get_final_transform().get_scale().y*node.get_global_transform_with_canvas().get_scale().y)


## Pixel art in menus covers a whole number of real pixels per source texel.
## The 1.2 design stretch at 1080p would otherwise turn a whole design multiple
## into 2.4x or 3.6x, with 2 and 3 px wide texels alternating. pixel_fit()
## returns design units per texel for the largest whole real-pixel multiple that
## fits `room`; below one real pixel per texel no whole step exists and the
## exact fit is kept. Without a window (headless) design pixels count as real.
static func pixel_fit(node: CanvasItem, source: Vector2, room: Vector2) -> float:
	if source.x <= 0.0 or source.y <= 0.0: return 1.0
	var fit := minf(room.x/source.x, room.y/source.y)
	var pixels := output_scale(node)
	if pixels <= 0.0 or not is_finite(pixels): pixels = 1.0
	var whole := floorf(fit*pixels+0.001)
	return whole/pixels if whole >= 1.0 else fit


## `at` (local to `node`) moved onto the nearest real pixel corner, so texel
## edges of pixel art drawn from there meet the screen's pixel edges.
static func pixel_snap(node: CanvasItem, at: Vector2) -> Vector2:
	if not is_instance_valid(node) or not node.is_inside_tree(): return at.round()
	var screen := node.get_viewport().get_final_transform()*node.get_global_transform_with_canvas()
	if absf(screen.determinant()) < 0.000001: return at.round()
	return screen.affine_inverse()*(screen*at).round()


## Where pixel art of `source` texels lands inside `room` at pixel_fit():
## centred across, standing on the room's floor (feet stay on a frame's base),
## its corner on a real pixel. Draw the texture into the returned rect.
static func pixel_rect(node: CanvasItem, source: Vector2, room: Rect2, centre_vertically: bool = false) -> Rect2:
	var drawn := source*pixel_fit(node, source, room.size)
	var y := room.position.y+(room.size.y-drawn.y)*(0.5 if centre_vertically else 1.0)
	return Rect2(pixel_snap(node, Vector2(room.position.x+(room.size.x-drawn.x)*0.5, y)), drawn)


## Size factor for helper copy on screens that have room to grow it. The design
## canvas is drawn at 2/3 scale in a 960x600 window, where 14-16 px copy would
## land at 9-10 real pixels; this returns 1.0 at a 0.95 output scale and above
## and rises to 1.25 at the minimum window. Layout positions stay unchanged.
static func compact_boost(node: CanvasItem) -> float:
	var scale := output_scale(node)
	return clampf(remap(scale,0.95,0.667,1.0,1.25),1.0,1.25)


## One Theme for every code-built control below the HUD canvas. Screens that
## still carry their own overrides keep them; new controls need none.
static func theme() -> Theme:
	if _theme != null: return _theme
	_theme = Theme.new()
	_theme.default_font = FONT
	_theme.default_font_size = TEXT_BODY
	for type in ["Button","CheckButton","OptionButton","MenuButton"]:
		for state in ["normal","hover","pressed","focus","disabled"]:
			_theme.set_stylebox(state,type,skin(state))
		_theme.set_stylebox("hover_pressed",type,skin("pressed"))
		_theme.set_font("font",type,FONT)
		_theme.set_font_size("font_size",type,TEXT_BODY)
		_theme.set_color("font_color",type,IVORY)
		_theme.set_color("font_focus_color",type,IVORY)
		_theme.set_color("font_hover_color",type,TEXT_HOVER)
		_theme.set_color("font_hover_pressed_color",type,AMBER)
		_theme.set_color("font_pressed_color",type,AMBER)
		_theme.set_color("font_disabled_color",type,TEXT_DISABLED)
	for icon_name in ["checked","checked_disabled","checked_mirrored","checked_disabled_mirrored"]:
		_theme.set_icon(icon_name,"CheckButton",switch_icon(true))
	for icon_name in ["unchecked","unchecked_disabled","unchecked_mirrored","unchecked_disabled_mirrored"]:
		_theme.set_icon(icon_name,"CheckButton",switch_icon(false))
	_theme.set_font("font","Label",FONT)
	_theme.set_font_size("font_size","Label",TEXT_BODY)
	_theme.set_color("font_color","Label",IVORY)
	_theme.set_stylebox("normal","LineEdit",skin("normal"))
	_theme.set_stylebox("focus","LineEdit",skin("input_focus"))
	_theme.set_stylebox("read_only","LineEdit",skin("disabled"))
	_theme.set_font("font","LineEdit",FONT)
	_theme.set_font_size("font_size","LineEdit",TEXT_BODY)
	_theme.set_color("font_color","LineEdit",IVORY)
	_theme.set_color("font_placeholder_color","LineEdit",MUTED)
	_theme.set_color("caret_color","LineEdit",AMBER)
	_theme.set_stylebox("panel","PopupMenu",skin("normal"))
	_theme.set_stylebox("hover","PopupMenu",skin("hover"))
	_theme.set_font("font","PopupMenu",FONT)
	_theme.set_font_size("font_size","PopupMenu",TEXT_BODY)
	_theme.set_color("font_color","PopupMenu",IVORY)
	_theme.set_color("font_hover_color","PopupMenu",TEXT_HOVER)
	_theme.set_color("font_disabled_color","PopupMenu",TEXT_DISABLED)
	_theme.set_stylebox("panel","TooltipPanel",skin("normal"))
	_theme.set_font("font","TooltipLabel",FONT)
	_theme.set_font_size("font_size","TooltipLabel",TEXT_LABEL)
	_theme.set_color("font_color","TooltipLabel",IVORY)
	_theme.set_stylebox("slider","HSlider",slider_track(false))
	_theme.set_stylebox("grabber_area","HSlider",slider_track(true))
	_theme.set_stylebox("grabber_area_highlight","HSlider",slider_track(true))
	_theme.set_icon("grabber","HSlider",slider_handle())
	_theme.set_icon("grabber_highlight","HSlider",slider_handle())
	_theme.set_icon("grabber_disabled","HSlider",slider_handle())
	return _theme


static func steel_grain() -> ImageTexture:
	if _steel_grain == null:
		var pixels := Image.create(96,96,false,Image.FORMAT_RGBA8)
		pixels.fill(Color.TRANSPARENT)
		# Deterministic short horizontal marks, no per-frame noise or readbacks.
		for index in 110:
			var x := (index*37+11)%96
			var y := (index*53+7)%96
			var width := mini(96-x,2+index%9)
			pixels.fill_rect(Rect2i(x,y,width,1),Color(.72,.72,.57,.038) if index%3 else Color(.03,.08,.09,.065))
		_steel_grain = ImageTexture.create_from_image(pixels)
	return _steel_grain


static func desktop(node: CanvasItem, rect: Rect2) -> void:
	# Large quiet steel sheets give the menu a material surface without hiding
	# text behind decorative machinery or an expensive full-screen texture.
	node.draw_rect(rect,Color("28332d"))
	for x in range(floori(rect.position.x/320.0)*320,ceili(rect.end.x),320):
		node.draw_line(Vector2(x,rect.position.y),Vector2(x,rect.end.y),Color("354138"),1)
		node.draw_line(Vector2(x+1,rect.position.y),Vector2(x+1,rect.end.y),Color("1c2c25"),1)
	for y in range(floori(rect.position.y/224.0)*224,ceili(rect.end.y),224):
		node.draw_line(Vector2(rect.position.x,y),Vector2(rect.end.x,y),Color("354138"),1)
	for index in 22:
		var at := rect.position+Vector2(fposmod(index*173.0+71,rect.size.x),fposmod(index*97.0+41,rect.size.y))
		node.draw_rect(Rect2(at.round(),Vector2(7+index%11,1)),Color(.48,.49,.39,.09))


static func text(node: CanvasItem, at: Vector2, value: String, size: int = 14, color: Color = IVORY, font: Font = FONT) -> void:
	value=LocaleText.text(value)
	node.draw_string(font,at.round(),value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)


static func centered(node: CanvasItem, at: Vector2, value: String, size: int = 14, color: Color = IVORY, font: Font = FONT) -> void:
	value=LocaleText.text(value)
	text(node,at-Vector2(font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x/2.0,0),value,size,color,font)


static func wrap_text(value: String, width: float, size: int = 12, font: Font = FONT) -> Array[String]:
	return wrap_plain_text(LocaleText.text(value),width,size,font)


static func wrap_plain_text(value: String, width: float, size: int = 12, font: Font = FONT) -> Array[String]:
	# Delivered player text is literal; localized UI opts in via wrap_text.
	var lines: Array[String] = []
	for paragraph in value.split("\n"):
		var line := ""
		for word in paragraph.split(" ",false):
			var candidate := word if line.is_empty() else line+" "+word
			if font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=width:
				line = candidate
				continue
			if not line.is_empty():
				lines.append(line)
				line = ""
			# Long names and connection codes must also remain inside the panel.
			for character in word:
				if not line.is_empty() and font.get_string_size(line+character,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x>width:
					lines.append(line)
					line = ""
				line += character
		lines.append(line)
	return lines


static func hud_strip(node: CanvasItem,rect: Rect2,opacity: float = 1.0) -> void:
	# Small translucent backing; no repeated picture frames or corner rivets.
	node.draw_rect(rect,Color(.095,.125,.108,.88*opacity))
	node.draw_line(rect.position,rect.position+Vector2(rect.size.x,0),Color(.42,.46,.37,.55*opacity),1)
	node.draw_line(rect.position+Vector2(0,rect.size.y),rect.end,Color(.03,.05,.04,.65*opacity),1)


## True while a menu, report or reading panel covers the match. World words
## (station labels, callsigns, warnings) stay hidden then, so nothing written
## in the world shows through or collides with the panel's own text.
static func menu_covers_world(game: Variant) -> bool:
	if not is_instance_valid(game) or not "hud" in game or not is_instance_valid(game.hud): return false
	return not str(game.hud.overlay).is_empty()


static func world_label_visible(node: CanvasItem) -> bool:
	if not node is Node2D or not "game" in node or not is_instance_valid(node.game): return true
	var game = node.game
	if not "players" in game or ("started" in game and not game.started): return false
	# The screen-edge dock identifies stations without painting words over their
	# machinery during play, and an open menu covers the world entirely. Warning
	# labels still opt in through world_label's RED override, but only in play.
	if "hud" in game and is_instance_valid(game.hud): return false
	var online: bool="network" in game and is_instance_valid(game.network) and game.network.active
	for worker in game.players:
		if not is_instance_valid(worker): continue
		if online and worker.player_id!=game.network.local_player_id: continue
		# The focused target already has a concise title/status/action hint.
		if worker.focus==node and "hud" in game and is_instance_valid(game.hud) and game.hud.overlay.is_empty(): return false
		var point: Vector2=node.interaction_point() if node.has_method("interaction_point") else node.global_position
		var delta: Vector2=worker.global_position-Vector2(0,20)-point
		if absf(delta.y)<64 and delta.length()<94: return true
	return false


static func world_label(node: CanvasItem, anchor: Vector2, title: String, status: String = "", status_color: Color = MUTED, width: float = 150.0) -> Rect2:
	if not world_label_visible(node) and (status_color!=RED or menu_covers_world(node.get("game"))): return Rect2()
	title=LocaleText.text(title)
	status=LocaleText.text(status)
	var title_size := 12
	while title_size>10 and FONT.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,title_size).x>width:
		title_size -= 1
	var rows := [title,status]
	var bounds := Rect2()
	for index in rows.size():
		var line: String = rows[index]
		if line.is_empty(): continue
		var font_size := title_size if index==0 else 10
		while line.length()>1 and FONT.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:
			line = line.left(line.length()-2)+"…"
		var line_width := FONT.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		var at := (anchor+Vector2(-line_width*0.5,index*14)).round()
		# Each row sits on the same ink plate as the crew tags, so machinery,
		# sky or a passing sprite edge never runs through the letters.
		label_plate(node,at,line_width,font_size)
		text(node,at,line,font_size,IVORY if index==0 else status_color)
		var row := Rect2(at-Vector2(0,font_size),Vector2(line_width,font_size+3))
		bounds = row if index==0 else bounds.merge(row)
	return bounds


## Offsets of the ink ring drawn by outlined(): one real pixel (two from 1.9
## real pixels per design pixel up), on whole real pixels, in all eight
## directions. The pixel font's MSDF range is too narrow for draw_string_outline
## to draw anything wider than a hairline, so the ring is stamped instead.
const _RING := [Vector2(-1,-1),Vector2(0,-1),Vector2(1,-1),Vector2(-1,0),Vector2(1,0),Vector2(-1,1),Vector2(0,1),Vector2(1,1)]

static func ring_step(node: CanvasItem) -> float:
	var pixels := output_scale(node)
	if pixels <= 0.0: return 1.0
	return maxf(1.0,roundf(pixels*.8))/pixels

## Text that holds on any background, for words drawn over the world (damage
## numbers, XP, enemy names): a dark ink ring of one real pixel around every
## glyph. `at` is the baseline start; `step` comes from ring_step().
static func outlined(node: CanvasItem, at: Vector2, value: String, size: int, color: Color, step: float, ink: Color = Color(.02,.03,.03,.94), font: Font = FONT) -> void:
	var ring := Color(ink,ink.a*color.a)
	for offset: Vector2 in _RING:
		node.draw_string(font,at+offset*step,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,ring)
	node.draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

## Ink plate behind one line of world-space label text whose baseline is at
## `at` (the P1 tags' backing, two units of padding).
static func label_plate(node: CanvasItem, at: Vector2, width: float, size: int) -> void:
	var top := at.y-FONT.get_ascent(size)-1.0
	node.draw_rect(Rect2(Vector2(at.x-3.0,top).round(),Vector2(width+6.0,FONT.get_ascent(size)+FONT.get_descent(size)+3.0).round()),Color(INK,.94))


## A short identifier riding above an actor (SAN-1), on the crew tags' ink
## plate. Its owner draws it on a layer above the crew and their weapons.
static func callsign(node: CanvasItem, anchor: Vector2, value: String, size: int = 10, color: Color = Color("c3cdb5")) -> void:
	value=LocaleText.text(value)
	var width := FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	var at := (anchor-Vector2(width*0.5,0)).round()
	label_plate(node,at,width,size)
	node.draw_string(FONT,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)


static func wordmark(node: CanvasItem, rect: Rect2) -> void:
	# Original vector lettering, with a 700-unit cap height on a 1000-unit em.
	# Fit without horizontal stretching; all other text uses the readable body face.
	var font_size:=int(rect.size.y*1.4)
	while font_size>12 and TITLE_FONT.get_string_size("BUNKERCREW",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>rect.size.x: font_size-=1
	text(node,Vector2(rect.position.x,rect.end.y),"BUNKERCREW",font_size,IVORY,TITLE_FONT)


static func icon(node: CanvasItem, kind: String, at: Vector2, size: float = 32, tint: Color = Color.WHITE) -> void:
	if kind in ["core", "scrap"]:
		PICKUP_ART.draw_icon(node,kind,at,size,tint)
		return
	var index := ICON_NAMES.find(kind)
	if index < 0:
		index = 0
	node.draw_texture_rect_region(ICONS,Rect2(at.round(),Vector2(size,size)),Rect2(index*32,0,32,32),tint)


static func material(node: CanvasItem, kind: String, at: Vector2, size: float = 32) -> void:
	# Painted inventory pictures exist as pixel-exact 28 and 40 px icons and are
	# drawn 1:1, centred in the requested cell. Below 28 px the bold authored
	# sprites read better, so small HUD and world markers keep them.
	if size >= 28.0 and MATERIAL_ICON_COLUMNS.has(kind):
		var native := 40.0 if size >= 40.0 else 28.0
		var factor := maxf(1.0,floorf(size/native))
		var drawn := Vector2.ONE*native*factor
		node.draw_texture_rect_region(MATERIAL_ICONS,Rect2((at+(Vector2.ONE*size-drawn)*0.5).round(),drawn),Rect2(float(MATERIAL_ICON_COLUMNS[kind])*40.0,0.0 if native==40.0 else 40.0,native,native))
		return
	if kind != "scrap" and ItemCatalog.draw_icon(node,kind,Rect2(at,Vector2(size,size))): return
	if kind in ["jaw_trap", "blast_trap", "sentry_kit", "limestone", "glass", "tungsten", "alloy"]:
		MaterialArt.draw_material(node,kind,at+Vector2.ONE*size*0.5,size/32.0)
		return
	if kind in ["core", "scrap"]:
		icon(node,kind,at,size)
		return


## Inset item slot: the common frame for inventory and recipe materials.
static func slot(node: CanvasItem, rect: Rect2, complete: bool = false) -> void:
	rect = Rect2(rect.position.round(),rect.size.round())
	node.draw_rect(rect,INK)
	node.draw_rect(rect.grow(-1),Color("222e29"))
	node.draw_rect(Rect2(rect.position+Vector2(1,rect.size.y-2),Vector2(rect.size.x-2,1)),Color(GREEN if complete else BORDER,0.9 if complete else 0.45))


static func button(control: Button, size: int = 14) -> void:
	control.add_theme_font_override("font",FONT)
	control.add_theme_font_size_override("font_size",size)
	for state in ["normal","hover","pressed","focus","disabled"]:
		control.add_theme_stylebox_override(state,skin(state))
	control.add_theme_color_override("font_color",IVORY)
	control.add_theme_color_override("font_hover_color",TEXT_HOVER)
	control.add_theme_color_override("font_pressed_color",AMBER)
	control.add_theme_color_override("font_disabled_color",TEXT_DISABLED)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not control.has_meta("industrial_trim"):
		control.set_meta("industrial_trim",true)
		control.draw.connect(_button_trim.bind(control))
		control.pressed.connect(_button_pressed.bind(control))
	if control is CheckButton:
		for icon_name in ["checked","checked_disabled","unchecked","unchecked_disabled","checked_mirrored","unchecked_mirrored"]:
			control.add_theme_icon_override(icon_name,switch_icon(icon_name.begins_with("checked")))
	if control is OptionButton:
		var popup: PopupMenu = control.get_popup()
		popup.add_theme_stylebox_override("panel",skin("normal"))
		popup.add_theme_stylebox_override("hover",skin("hover"))
		popup.add_theme_font_override("font",FONT)
		popup.add_theme_font_size_override("font_size",size)
		popup.add_theme_color_override("font_color",IVORY)


static func _button_pressed(control: Button) -> void:
	if not UiMotion.enabled() or control.disabled: return
	control.set_meta("press_started",UiMotion.now())
	control.queue_redraw()


static func _button_trim(control: Button) -> void:
	# Selected (a toggled choice): a solid amber rail on the left edge and a
	# lit lower edge, kept even while the choice cannot be changed, so "chosen"
	# never collapses into "unavailable".
	var selected := control.toggle_mode and control.button_pressed
	if selected and not control.has_meta("quiet_focus"):
		control.draw_rect(Rect2(0,0,3,control.size.y),AMBER)
		control.draw_rect(Rect2(3,control.size.y-2,maxf(0,control.size.x-3),2),Color(AMBER,.55))
	if control.disabled:
		if not selected and not control.has_meta("quiet_focus") and control.size.x>=96.0: lock_glyph(control,Vector2(control.size.x-24,roundf(control.size.y*.5)-7),Color(TEXT_DISABLED,.85))
		return
	# Buttons restyled by SocialUiArt.button carry their own focus wash (and
	# their screen's marker); a second bar there read as a stray text caret.
	if control.has_focus() and not control.has_meta("quiet_focus") and not selected: control.draw_rect(Rect2(0,6,2,maxf(0,control.size.y-12)),AMBER)
	# Activation answers with a short amber sweep along the lower edge. It is
	# drawn on top of the settled style and never changes the hit rectangle.
	if not control.has_meta("press_started"): return
	var started := float(control.get_meta("press_started"))
	if not UiMotion.running(started,UiMotion.SLOW):
		control.remove_meta("press_started")
		return
	var sweep := UiMotion.progress(started,UiMotion.SLOW)
	var width := control.size.x*sweep
	control.draw_rect(Rect2((control.size.x-width)*0.5,control.size.y-2,width,2),Color(AMBER,1.0-UiMotion.linear(started,UiMotion.SLOW)))
	control.queue_redraw.call_deferred()


const _LOCK_ROWS := [".###.", "#...#", "#...#", "#####", "##.##", "#####"]
## Technikpunkte: a cog (teeth on four sides around a hollow hub).
const TECH_ROWS := ["..#.#..", ".#####.", "##...##", ".#...#.", "##...##", ".#####.", "..#.#.."]
## Done: a stepped tick.
const CHECK_ROWS := ["......#", ".....##", "#...##.", "##.##..", ".###...", "..#...."]

## A small pixel glyph from `rows` ('#' = filled cell), top left at `at`.
## Each cell is about `cell` design pixels rounded to whole real pixels (at
## least one), on the real pixel grid, so it stays crisp at every window
## scale: 7 cells are 14 px at 1080p and 7 px in a 960x600 window.
static func pixel_glyph(node: CanvasItem, rows: Array, at: Vector2, cell: float, color: Color) -> void:
	var pixels := output_scale(node)
	if pixels <= 0.0 or not is_finite(pixels): pixels = 1.0
	var step := maxf(1.0,roundf(cell*pixels))/pixels
	at = pixel_snap(node,at)
	for row in rows.size():
		var line: String = rows[row]
		for column in line.length():
			if line[column] == "#": node.draw_rect(Rect2(at+Vector2(column,row)*step,Vector2(step,step)),color)

## A small pixel padlock (5x6 cells of 2.5 design pixels, snapped to whole
## real pixels: 3 at 1080p) at `at` (top left): the cue of a control that
## cannot be used right now. About 13x15 design pixels.
static func lock_glyph(node: CanvasItem, at: Vector2, color: Color) -> void:
	var pixels := output_scale(node)
	var cell := 2.0 if pixels <= 0.0 else maxf(2.0,roundf(2.5*pixels))/pixels
	at = at.round() if pixels <= 0.0 else (at*pixels).round()/pixels
	for row in _LOCK_ROWS.size():
		var line: String = _LOCK_ROWS[row]
		for column in line.length():
			if line[column] == "#": node.draw_rect(Rect2(at+Vector2(column,row)*cell,Vector2(cell,cell)),color)


static func bar(node: CanvasItem, rect: Rect2, ratio: float, color: Color = GREEN) -> void:
	node.draw_rect(rect.grow(1),Color("142327"))
	node.draw_rect(rect,Color("46524b"))
	var fill := Rect2(rect.position,Vector2(floorf(rect.size.x*clampf(ratio,0,1)),rect.size.y))
	node.draw_rect(fill,color)
	if fill.size.x>1 and rect.size.y>=5:
		node.draw_rect(Rect2(fill.position,Vector2(fill.size.x,1)),color.lightened(.18))


## Status bar with an inked frame, a lit upper edge and quarter ticks. `trail`
## is the previous, larger ratio: the lost part stays visible for a moment
## before it drains, so a hit reads even at a glance.
static func meter(node: CanvasItem, rect: Rect2, ratio: float, color: Color = GREEN, trail: float = -1.0, glow: float = 0.0) -> void:
	rect = Rect2(rect.position.round(),rect.size.round())
	ratio = clampf(ratio,0.0,1.0)
	node.draw_rect(rect.grow(1),INK)
	node.draw_rect(rect,Color("2b3832"))
	if trail > ratio:
		node.draw_rect(Rect2(rect.position,Vector2(floorf(rect.size.x*clampf(trail,0.0,1.0)),rect.size.y)),Color("e9d9b0"))
	var fill := Rect2(rect.position,Vector2(floorf(rect.size.x*ratio),rect.size.y))
	if ratio > 0.0 and fill.size.x < 1.0: fill.size.x = 1.0
	node.draw_rect(fill,color.lerp(Color("ffd9c2"),glow*0.45))
	if fill.size.x > 1.0 and rect.size.y >= 5.0:
		node.draw_rect(Rect2(fill.position,Vector2(fill.size.x,1)),color.lightened(0.28))
		node.draw_rect(Rect2(fill.position+Vector2(0,rect.size.y-1),Vector2(fill.size.x,1)),color.darkened(0.22))
	if rect.size.x >= 48.0:
		for quarter in [0.25,0.5,0.75]:
			# Two design pixels wide: a one-pixel tick drops out in a 960x600 window.
			node.draw_rect(Rect2(rect.position+Vector2(roundf(rect.size.x*quarter)-1,0),Vector2(2,rect.size.y)),Color(INK,0.42))


## Width of one input glyph drawn by `prompt`.
static func prompt_width(value: String, pad: bool, size: int = TEXT_LABEL) -> float:
	if pad and value == "dpad": return size+5.0
	var inner := FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	return maxf(size+5.0,inner+(8.0 if pad else 10.0))


## One input glyph: a keycap for the keyboard, a round face button or a
## directional cross for the controller. `at` is the text baseline.
static func prompt(node: CanvasItem, at: Vector2, value: String, pad: bool, size: int = TEXT_LABEL, color: Color = IVORY) -> float:
	var width := prompt_width(value,pad,size)
	var height := size+5.0
	var box := Rect2(Vector2(roundf(at.x),roundf(at.y-size-1.0)),Vector2(width,height))
	if pad and value == "dpad":
		var arm := floorf(height/3.0)
		node.draw_rect(Rect2(box.position+Vector2(arm,0),Vector2(height-arm*2.0,height)),Color("51605b"))
		node.draw_rect(Rect2(box.position+Vector2(0,arm),Vector2(height,height-arm*2.0)),Color("51605b"))
		node.draw_rect(Rect2(box.position+Vector2(arm,0),Vector2(height-arm*2.0,1)),Color("829080"))
		node.draw_rect(Rect2(box.position+Vector2(arm+1,1),Vector2(height-arm*2.0-2,arm-1)),color)
		node.draw_rect(Rect2(box.position+Vector2(arm+1,height-arm),Vector2(height-arm*2.0-2,arm-1)),color)
		return width
	if pad:
		# Stepped pixel disc: three stacked bars read as a round face button.
		node.draw_rect(Rect2(box.position+Vector2(3,0),Vector2(width-6,height)),Color("51605b"))
		node.draw_rect(Rect2(box.position+Vector2(1,1),Vector2(width-2,height-2)),Color("51605b"))
		node.draw_rect(Rect2(box.position+Vector2(0,3),Vector2(width,height-6)),Color("51605b"))
		node.draw_rect(Rect2(box.position+Vector2(3,0),Vector2(width-6,1)),Color("829080"))
	else:
		node.draw_rect(Rect2(box.position+Vector2(0,2),box.size),INK)
		node.draw_rect(box,Color("51605b"))
		node.draw_rect(Rect2(box.position,Vector2(width,1)),Color("829080"))
	var inner := FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	node.draw_string(FONT,Vector2(roundf(box.position.x+(width-inner)*0.5),roundf(at.y)),value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
	return width


## A row of input hints. Each entry is [glyphs: Array[String], caption]; the
## glyphs are already resolved for the active device. Returns the row width.
static func hints(node: CanvasItem, at: Vector2, entries: Array, pad: bool, size: int = TEXT_LABEL, color: Color = MUTED, measure_only: bool = false) -> float:
	var x := at.x
	for entry: Array in entries:
		for glyph: String in entry[0]:
			if measure_only: x += prompt_width(glyph,pad,size)+SPACE_1
			else: x += prompt(node,Vector2(x,at.y),glyph,pad,size)+SPACE_1
		var caption := LocaleText.text(str(entry[1]))
		if not measure_only: node.draw_string(FONT,Vector2(roundf(x+2.0),roundf(at.y)),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
		x += 2.0+FONT.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x+SPACE_4
	return x-at.x-SPACE_4


static func key(node: CanvasItem, at: Vector2, value: String, color: Color = AMBER) -> void:
	value=LocaleText.text(value)
	var width := maxf(22.0,value.length()*7.0+12)
	node.draw_rect(Rect2(at,Vector2(width,21)),Color("142327"))
	node.draw_rect(Rect2(at,Vector2(width,18)),Color("51605b"))
	node.draw_line(at,at+Vector2(width,0),Color("829080"),1)
	centered(node,at+Vector2(width/2,14),value,11,color)


static func divider(node: CanvasItem, a: Vector2, b: Vector2) -> void:
	node.draw_line(a,b,Color("61706a"),1)


## Option switch: 12x6 pixel-art cells, each SWITCH_CELL design pixels, so a
## cell lands on whole real pixels at the common outputs (6 at 1080p, 8 at
## 1440p and 3440x1440): 60x30 design pixels, 72x36 at 1080p.
const SWITCH_CELLS := Vector2i(12,6)
const SWITCH_CELL := 5
static func switch_icon(enabled: bool) -> ImageTexture:
	if not _switch_icons.has(enabled):
		# A recessed track and a raised knob with a grip groove. On is an amber
		# knob at the right on a warm lit track, off a grey knob at the left on a
		# cold one, so the state reads by position and by colour, and survives
		# greyscale.
		var ink := Color("0e1714")
		var pixels := Image.create(SWITCH_CELLS.x,SWITCH_CELLS.y,false,Image.FORMAT_RGBA8)
		pixels.fill(Color.TRANSPARENT)
		pixels.fill_rect(Rect2i(0,1,12,4),ink)
		pixels.fill_rect(Rect2i(1,2,10,2),Color("8a6c38") if enabled else Color("2c3a32"))
		pixels.fill_rect(Rect2i(1,2,10,1),Color("5a4625") if enabled else Color("1a241f"))
		var x := 6 if enabled else 0
		var knob := AMBER if enabled else Color("8e9180")
		pixels.fill_rect(Rect2i(x,0,6,6),ink)
		pixels.fill_rect(Rect2i(x+1,1,4,4),knob)
		pixels.fill_rect(Rect2i(x+1,1,4,1),knob.lightened(0.35))
		pixels.fill_rect(Rect2i(x+1,4,4,1),knob.darkened(0.3))
		pixels.fill_rect(Rect2i(x+2,2,2,2),knob.darkened(0.42))
		var texture := ImageTexture.create_from_image(pixels)
		texture.set_size_override(SWITCH_CELLS*SWITCH_CELL)
		_switch_icons[enabled] = texture
	return _switch_icons[enabled]


static func slider_track(filled: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = AMBER if filled else Color("1c2c30")
	style.border_width_bottom = 1
	style.border_color = Color("667166")
	style.anti_aliasing = false
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


static func slider_handle() -> ImageTexture:
	if _slider_handle == null:
		var pixels := Image.create(8,20,false,Image.FORMAT_RGBA8)
		pixels.fill(Color("243438"))
		pixels.fill_rect(Rect2i(1,1,6,17),Color("bdbaa0"))
		pixels.fill_rect(Rect2i(2,3,4,1),IVORY)
		pixels.fill_rect(Rect2i(3,6,2,8),Color("788277"))
		_slider_handle = ImageTexture.create_from_image(pixels)
	return _slider_handle
