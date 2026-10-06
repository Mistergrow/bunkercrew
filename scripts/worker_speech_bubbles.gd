extends CanvasLayer
## Screen-sized comic lettering tracks world actors at every camera zoom.
## Only delivered public chat, authored dialogue and authenticated voice appear.
const Chat := preload("res://scripts/network_chat.gd")
const PRESETS := Chat.PRESET_TEXTS
const MAX_TEXT := 240
const MAX_ROWS := 3
const FONT_SIZE := 16
const MIN_FONT_PIXELS := 14.0
const TEXT_WIDTH := 260.0
const HORIZONTAL_PADDING := 13.0
const VERTICAL_PADDING := 22.0
const LINE_HEIGHT := 21.0
const FIRST_BASELINE := 27.0
const MINIMUM_WIDTH := 38.0
var game: Node
var canvas: Control
var _network: Node
var _generation := -1
var _messages: Dictionary = {}
var _clock := 0.0
var _visible := false

func _ready() -> void:
	layer = 64
	process_mode = Node.PROCESS_MODE_ALWAYS
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw)
	add_child(canvas)

func _process(delta: float) -> void:
	_clock += delta
	_bind_network()
	for seat in _messages.keys():
		if float(_messages[seat].until) <= _clock or _chat_blocked(int(seat)): _messages.erase(seat)
	var present := not bubble_layout().is_empty()
	if present or _visible: canvas.queue_redraw()
	_visible = present

func _bind_network() -> void:
	var current: Node = game.get("network") if is_instance_valid(game) else null
	if current != _network:
		if is_instance_valid(_network) and _network.chat_received.is_connected(show_chat): _network.chat_received.disconnect(show_chat)
		_network = current
		_messages.clear()
		if is_instance_valid(_network): _network.chat_received.connect(show_chat)
	if is_instance_valid(_network) and int(_network.get("_generation")) != _generation:
		_generation = int(_network.get("_generation"))
		_messages.clear()

func show_chat(row: Dictionary) -> bool:
	if not Chat.valid_row(row) or bool(row.get("private", false)): return false
	var seat := int(row.player_id)
	if _chat_blocked(seat): return false
	var message := LocaleText.text(str(PRESETS[row.preset])) if PRESETS.has(row.preset) else str(row.text)
	_messages[seat] = {"text":message.left(MAX_TEXT), "preset":str(row.preset), "until":_clock + clampf(message.length() / 18.0 + 2.0, 3.0, 9.0)}
	return true

func _chat_blocked(seat: int) -> bool:
	return is_instance_valid(_network) and _network.has_method("is_player_blocked") and bool(_network.is_player_blocked(seat))

func bubble_layout() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(game) or not bool(game.get("started")): return result
	var hud: Node = game.get("hud")
	if is_instance_valid(hud) and str(hud.get("overlay")) not in ["", "pause"]: return result
	var scale_factor := 1.0
	if is_instance_valid(hud) and is_instance_valid(hud.get("canvas")): scale_factor = hud.canvas.scale.x
	canvas.scale = Vector2.ONE * scale_factor
	var screen := get_viewport().get_visible_rect().size / scale_factor
	var lettering := _lettering()
	var font_size: int = lettering.font_size
	var padding: Vector2 = lettering.padding
	var speaking: Array[int] = []
	if is_instance_valid(game.get("voice")): speaking = game.voice.speaking_players()
	var dialogue: Node = game.get("dialogue")
	var active: Dictionary = dialogue.get("active") if is_instance_valid(dialogue) else {}
	for player: Node2D in game.get("players"):
		if not is_instance_valid(player) or player.is_queued_for_deletion() or not player.is_visible_in_tree(): continue
		var seat := int(player.get("player_id"))
		var message := ""
		var voice_only := false
		if _messages.has(seat) and _chat_blocked(seat): _messages.erase(seat)
		if _messages.has(seat):
			var preset := str(_messages[seat].get("preset",""))
			message = LocaleText.text(str(PRESETS[preset])) if PRESETS.has(preset) else str(_messages[seat].text)
		elif not active.is_empty() and not bool(active.get("ending", false)) and str(active.get("speaker_id", "")) == str(player.get("character_id")) and int(active.get("anchor_player_id", 0)) in [0, seat]: message = str(active.get("text", ""))
		elif seat in speaking:
			message = "…"
			voice_only = true
		if message.is_empty(): continue
		var tip: Vector2 = (player.get_global_transform_with_canvas() * Vector2(0, -68)) / scale_factor
		if not Rect2(Vector2(8, 72), screen - Vector2(16, 144)).has_point(tip): continue
		var rows := UiArt.wrap_plain_text(message,lettering.text_width,font_size)
		if rows.size() > MAX_ROWS:
			rows.resize(MAX_ROWS)
			while UiArt.FONT.get_string_size(rows[-1] + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > lettering.text_width and not rows[-1].is_empty(): rows[-1] = rows[-1].left(rows[-1].length() - 1)
			rows[-1] += "…"
		var width: float = lettering.minimum_width
		for row: String in rows: width = maxf(width, UiArt.FONT.get_string_size(row, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + padding.x*2)
		var height: float = padding.y+rows.size()*lettering.line_height
		var rect := _place_bubble(Vector2(ceilf(width),height),tip,screen,result)
		if not rect.has_area(): continue
		result.append({"seat":seat,"rect":rect,"tip":tip.round(),"rows":rows,"voice":voice_only,"font_size":font_size,"text_width":lettering.text_width,"line_height":lettering.line_height,"padding":padding,"baseline":lettering.baseline})
	return result

func _lettering() -> Dictionary:
	# Canvas-item stretching can shrink a 960px window independently of the HUD.
	# Increase logical lettering together with its box, retaining readable output
	# pixels rather than enlarging only the font and clipping the same narrow box.
	# Embedded windows omit viewport stretch from CanvasItem.screen_transform.
	# Apply stretch to the canvas transform once, without relying on that shortcut.
	var output_transform := get_viewport().get_stretch_transform()*canvas.get_global_transform_with_canvas()
	var screen_scale := maxf(.01,absf(output_transform.get_scale().x))
	var font_size := maxi(FONT_SIZE,ceili(MIN_FONT_PIXELS/screen_scale))
	var factor := float(font_size)/FONT_SIZE
	return {"font_size":font_size,"text_width":TEXT_WIDTH*factor,"line_height":ceilf(LINE_HEIGHT*factor),"padding":Vector2(ceilf(HORIZONTAL_PADDING*factor),ceilf(VERTICAL_PADDING*factor)),"baseline":ceilf(FIRST_BASELINE*factor),"minimum_width":ceilf(MINIMUM_WIDTH*factor)}

func _place_bubble(size: Vector2, tip: Vector2, screen: Vector2, occupied: Array[Dictionary]) -> Rect2:
	# At most four crew: five base candidates plus two per previous bubble on
	# each axis (at most 121 pairs). All accepted positions respect both gutters.
	var bounds := Rect2(Vector2(8,72),Vector2(floorf(screen.x-16),floorf(screen.y-144)))
	if size.x>bounds.size.x or size.y>bounds.size.y: return Rect2()
	var maximum := bounds.end-size
	var preferred := tip-Vector2(size.x*.5,size.y+9)
	var initial := Rect2(Vector2(clampf(preferred.x,bounds.position.x,maximum.x),clampf(preferred.y,bounds.position.y,maximum.y)).round(),size)
	if _clear_rect(initial,tip,occupied): return initial
	var horizontal: Array[float] = [preferred.x,tip.x-size.x-12,tip.x+12,bounds.position.x,maximum.x]
	var vertical: Array[float] = [preferred.y,tip.y+9,bounds.position.y,maximum.y]
	for previous: Dictionary in occupied:
		var rect: Rect2 = previous.rect
		horizontal.append(rect.position.x-size.x-7)
		horizontal.append(rect.end.x+7)
		vertical.append(rect.position.y-size.y-7)
		vertical.append(rect.end.y+7)
	var best := Rect2()
	var best_distance := INF
	for x: float in horizontal:
		for y: float in vertical:
			var at := Vector2(clampf(x,bounds.position.x,maximum.x),clampf(y,bounds.position.y,maximum.y)).round()
			var candidate := Rect2(at,size)
			if not _clear_rect(candidate,tip,occupied): continue
			var distance := at.distance_squared_to(preferred)
			if distance<best_distance:
				best = candidate
				best_distance = distance
	return best

func _clear_rect(candidate: Rect2, tip: Vector2, occupied: Array[Dictionary]) -> bool:
	# A clamped top bubble must not swallow its own actor's speech anchor.
	if candidate.grow(5).has_point(tip): return false
	for previous: Dictionary in occupied:
		if previous.rect.grow(4).intersects(candidate): return false
	return true

func _tail_points(rect: Rect2, tip: Vector2) -> PackedVector2Array:
	# A side placement needs a side connector; a bottom-only triangle would run
	# through its own text or another crew member's bubble near the upper edge.
	var at := rect.position
	var end := rect.end
	if tip.x<at.x or tip.x>end.x:
		var side_x := at.x+1 if tip.x<at.x else end.x-1
		var side_y := clampf(tip.y,at.y+8,end.y-12)
		return PackedVector2Array([Vector2(side_x,side_y),Vector2(side_x,side_y+8),tip])
	var x := clampf(tip.x,at.x+8,end.x-12)
	var y := at.y+1 if tip.y<at.y else end.y-1
	return PackedVector2Array([Vector2(x,y),Vector2(x+8,y),tip])

func _draw() -> void:
	var layout := bubble_layout()
	var face := Color("d8d8be")
	var ink := Color("14231f")
	var rim := Color("9b9b7b")
	# Connectors sit behind all lettering, including a different crew bubble.
	for bubble: Dictionary in layout:
		var tail := _tail_points(bubble.rect,bubble.tip)
		canvas.draw_colored_polygon(tail, face)
		canvas.draw_line(tail[0], tail[2], ink, 2)
		canvas.draw_line(tail[1], tail[2], ink, 2)
	for bubble: Dictionary in layout:
		var rect: Rect2 = bubble.rect
		var at := rect.position
		var end := rect.end
		# Stepped corners and a restrained printed edge fit the existing pixel art.
		canvas.draw_rect(rect.grow(1), ink)
		canvas.draw_rect(Rect2(at + Vector2(0, 3), rect.size - Vector2(0, 6)), face)
		canvas.draw_rect(Rect2(at + Vector2(3, 0), rect.size - Vector2(6, 0)), face)
		canvas.draw_line(at + Vector2(4, 2), Vector2(end.x - 4, at.y + 2), rim, 1)
		for index in bubble.rows.size(): canvas.draw_string(UiArt.FONT,(at+Vector2(bubble.padding.x,bubble.baseline+index*bubble.line_height)).round(),bubble.rows[index],HORIZONTAL_ALIGNMENT_LEFT,-1,bubble.font_size,ink)
