class_name UiArt
extends RefCounted
## Quiet industrial surfaces, shared typography and clear interaction states.

const FONT = preload("res://assets/fonts/bunkercrew/body.tres")
const MENU_FONT = preload("res://assets/fonts/bunkercrew/menu.tres")
const TITLE_FONT = preload("res://assets/fonts/bunkercrew/title.tres")
const ICONS = preload("res://assets/ui/icons.png")
const PICKUP_ART = preload("res://scripts/pickup_art.gd")
const IVORY := Color("e0decb")
const MUTED := Color("a1a18c")
const AMBER := Color("d9ac60")
const STEEL := Color("3b453d")
const EDGE := Color("63726c")
const SHADOW := Color("172529")
const RED := Color("c65b47")
const GREEN := Color("a8b976")
const ICON_NAMES := ["workshop","wall","fortress","rifle","shotgun","arcgun","boots","harness","craftsmanship","core","helmet","ammo","limestone","glass","lock","check","tungsten","alloy"]
static var _skins: Dictionary = {}
static var _slider_handle: ImageTexture
static var _steel_grain: ImageTexture
static var _switch_icons: Dictionary = {}


static func skin(kind: String = "normal") -> StyleBoxFlat:
	if _skins.has(kind):
		return _skins[kind]
	var style := StyleBoxFlat.new()
	style.bg_color = Color("29362f")
	style.border_width_bottom = 1
	style.border_color = Color("66716a")
	style.shadow_color = Color(0.025,0.045,0.05,0.5)
	style.shadow_size = 0
	style.shadow_offset = Vector2(0,2)
	match kind:
		"hover":
			style.bg_color = Color("39483b")
			style.border_color = Color("a8af95")
		"pressed":
			style.bg_color = Color("29362d")
			style.border_color = AMBER
			style.shadow_size = 0
		"disabled":
			style.bg_color = Color("2c372f")
			style.border_color = Color("495445")
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
	style.content_margin_top = 8
	style.content_margin_bottom = 8
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


static func hud_strip(node: CanvasItem,rect: Rect2) -> void:
	# Small translucent backing; no repeated picture frames or corner rivets.
	node.draw_rect(rect,Color(.095,.125,.108,.88))
	node.draw_line(rect.position,rect.position+Vector2(rect.size.x,0),Color(.42,.46,.37,.55),1)
	node.draw_line(rect.position+Vector2(0,rect.size.y),rect.end,Color(.03,.05,.04,.65),1)


static func world_label_visible(node: CanvasItem) -> bool:
	if not node is Node2D or not "game" in node or not is_instance_valid(node.game): return true
	var game = node.game
	if not "players" in game or ("started" in game and not game.started): return false
	# The screen-edge dock identifies stations without painting words over their
	# machinery. Warning labels still opt in through world_label's RED override.
	if "hud" in game and is_instance_valid(game.hud) and game.hud.overlay.is_empty(): return false
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
	if not world_label_visible(node) and status_color!=RED: return Rect2()
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
		node.draw_string_outline(FONT,at,line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,3,Color(0.025,0.035,0.04,0.92))
		text(node,at,line,font_size,IVORY if index==0 else status_color)
		var row := Rect2(at-Vector2(0,font_size),Vector2(line_width,font_size+3))
		bounds = row if index==0 else bounds.merge(row)
	return bounds


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
	if kind != "scrap" and ItemCatalog.draw_icon(node,kind,Rect2(at,Vector2(size,size))): return
	if kind in ["jaw_trap", "blast_trap", "sentry_kit", "limestone", "glass", "tungsten", "alloy"]:
		MaterialArt.draw_material(node,kind,at+Vector2.ONE*size*0.5,size/32.0)
		return
	if kind in ["core", "scrap"]:
		icon(node,kind,at,size)
		return


static func button(control: Button, size: int = 14) -> void:
	control.add_theme_font_override("font",FONT)
	control.add_theme_font_size_override("font_size",size)
	for state in ["normal","hover","pressed","focus","disabled"]:
		control.add_theme_stylebox_override(state,skin(state))
	control.add_theme_color_override("font_color",IVORY)
	control.add_theme_color_override("font_hover_color",Color("fff0c7"))
	control.add_theme_color_override("font_pressed_color",AMBER)
	control.add_theme_color_override("font_disabled_color",Color("777d70"))
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not control.has_meta("industrial_trim"):
		control.set_meta("industrial_trim",true)
		control.draw.connect(_button_trim.bind(control))
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


static func _button_trim(control: Button) -> void:
	if control.disabled or not control.has_focus(): return
	control.draw_rect(Rect2(0,6,2,maxf(0,control.size.y-12)),AMBER)


static func bar(node: CanvasItem, rect: Rect2, ratio: float, color: Color = GREEN) -> void:
	node.draw_rect(rect.grow(1),Color("142327"))
	node.draw_rect(rect,Color("46524b"))
	var fill := Rect2(rect.position,Vector2(floorf(rect.size.x*clampf(ratio,0,1)),rect.size.y))
	node.draw_rect(fill,color)
	if fill.size.x>1 and rect.size.y>=5:
		node.draw_rect(Rect2(fill.position,Vector2(fill.size.x,1)),color.lightened(.18))


static func key(node: CanvasItem, at: Vector2, value: String, color: Color = AMBER) -> void:
	value=LocaleText.text(value)
	var width := maxf(22.0,value.length()*7.0+12)
	node.draw_rect(Rect2(at,Vector2(width,21)),Color("142327"))
	node.draw_rect(Rect2(at,Vector2(width,18)),Color("51605b"))
	node.draw_line(at,at+Vector2(width,0),Color("829080"),1)
	centered(node,at+Vector2(width/2,14),value,11,color)


static func divider(node: CanvasItem, a: Vector2, b: Vector2) -> void:
	node.draw_line(a,b,Color("61706a"),1)


static func switch_icon(enabled: bool) -> ImageTexture:
	if not _switch_icons.has(enabled):
		var pixels := Image.create(28,16,false,Image.FORMAT_RGBA8)
		pixels.fill(Color("17251e"))
		pixels.fill_rect(Rect2i(1,1,26,13),Color("4e5d4c"))
		pixels.fill_rect(Rect2i(3,4,22,7),Color("263629"))
		var x := 15 if enabled else 3
		pixels.fill_rect(Rect2i(x,2,10,11),AMBER if enabled else Color("a1a18c"))
		pixels.fill_rect(Rect2i(x+1,3,8,1),IVORY)
		pixels.fill_rect(Rect2i(x+4,5,2,5),Color("60664d"))
		_switch_icons[enabled] = ImageTexture.create_from_image(pixels)
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
