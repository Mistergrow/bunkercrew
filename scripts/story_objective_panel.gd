extends Control
const L := preload("res://scripts/locale_text.gd")
var director: Node
var _clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("story_objective_panels")

func _process(delta: float) -> void:
	_clock += delta
	# Marker coordinates are projected into HUD space in _draw(). Camera
	# motion must invalidate that projection every rendered frame, otherwise
	# a cached arrow drifts away from its worker even though world art moves.
	var anchored: bool = is_instance_valid(director) and director.displays_objectives() and director.target_position().is_finite()
	if anchored or _clock >= .05:
		_clock = 0
		queue_redraw()

func objective_layout() -> Dictionary:
	if not is_instance_valid(director) or not director.displays_objectives(): return {}
	var game = director.game
	if not is_instance_valid(game.hud) or not game.hud.overlay.is_empty(): return {}
	var screen: Rect2 = game.hud.screen_rect()
	var width := minf(430.0,screen.size.x - 36.0)
	var top := screen.position.y + 74.0
	if is_instance_valid(game.dialogue) and not game.dialogue.active.is_empty() and game.dialogue.canvas.visible and not bool(game.dialogue.active.ending):
		var caption: Dictionary = game.dialogue.caption_layout()
		var caption_rect: Rect2 = caption.rect
		top = screen.position.y + caption_rect.end.y + 12.0
	var titles := UiArt.wrap_text(director.act_title(),width - 32.0,14)
	var rows := UiArt.wrap_text(director.objective(),width - 32.0,14)
	var height := 23.0 + titles.size() * 19.0 + rows.size() * 20.0
	return {"rect":Rect2(screen.end.x - width - 18.0,top,width,height),"titles":titles,"rows":rows}

func objective_bounds() -> Rect2:
	# HUD-local bounds are safe to query from its occupied-area registry. This
	# function never queries that registry itself, so marker layout cannot recurse.
	var layout := objective_layout()
	return layout.get("rect",Rect2())

func marker_safe_bounds() -> Rect2:
	var hud = director.game.hud
	var screen: Rect2 = hud.screen_rect()
	var top := maxf(screen.position.y + 220.0,objective_bounds().end.y + 28.0)
	var bottom := screen.end.y - 160.0
	var dialogue = director.game.dialogue
	if is_instance_valid(dialogue) and not dialogue.active.is_empty() and dialogue.canvas.visible and bool(dialogue.active.ending):
		var caption: Dictionary = dialogue.caption_layout()
		var caption_rect: Rect2 = caption.rect
		bottom = minf(bottom,screen.position.y + caption_rect.position.y - 28.0)
	if hud.has_method("occupied_gameplay_bounds"):
		for occupied: Rect2 in hud.occupied_gameplay_bounds():
			if occupied.position.y > screen.get_center().y:
				bottom = minf(bottom,occupied.position.y - 28.0)
	# Authored captions/objectives fit well above the docks. Preserve a usable
	# ray rectangle if a mod supplies an unusually long objective.
	top = minf(top,bottom - 100.0)
	return Rect2(screen.position.x + 28.0,top,screen.size.x - 56.0,bottom - top)

func _draw() -> void:
	var layout := objective_layout()
	if layout.is_empty(): return
	var game = director.game
	var rect: Rect2 = layout.rect
	UiArt.hud_strip(self,rect)
	draw_rect(Rect2(rect.position,Vector2(2,rect.size.y)),UiArt.AMBER)
	var titles: Array[String] = layout.titles
	for index in titles.size():
		UiArt.text(self,rect.position + Vector2(16,23 + index * 19),titles[index],14,UiArt.AMBER)
	var rows: Array[String] = layout.rows
	for index in rows.size():
		UiArt.text(self,rect.position + Vector2(16,26 + titles.size() * 19 + index * 20),rows[index],14)
	var at: Vector2 = director.target_position()
	if not at.is_finite(): return
	var marker := marker_layout(game.hud.world_to_ui(at),marker_safe_bounds())
	var point: Vector2 = marker.point
	if marker.offscreen:
		var direction: Vector2 = marker.direction
		var side := direction.orthogonal() * 4.0
		var tail := point - direction * 10.0
		draw_colored_polygon(PackedVector2Array([point,tail + side,tail - side]),UiArt.AMBER)
		UiArt.world_label(self,marker.label,"AUFTRAG","",UiArt.MUTED,90)
	else:
		draw_colored_polygon(PackedVector2Array([point + Vector2(-6,-7),point + Vector2(6,-7),point]),UiArt.AMBER)
		UiArt.world_label(self,point + Vector2(0,-16),"AUFTRAG","",UiArt.MUTED,90)

static func marker_layout(target: Vector2,safe: Rect2 = Rect2(28,220,1384,480)) -> Dictionary:
	# Keep the full label clear of edge instruments, not only the arrow point.
	# The true ray preserves direction when both horizontal and vertical limits
	# are reached. Defaults retain the standalone directional-marker API.
	if safe.grow(-20).has_point(target):
		return {"point":target.round(),"direction":Vector2.DOWN,"label":target + Vector2(0,-16),"offscreen":false}
	var center := safe.get_center()
	var direction: Vector2 = (target - center).normalized()
	var distance_x := safe.size.x * .5 / absf(direction.x) if absf(direction.x) > .0001 else INF
	var distance_y := safe.size.y * .5 / absf(direction.y) if absf(direction.y) > .0001 else INF
	var point: Vector2 = (center + direction * minf(distance_x,distance_y)).round()
	var label: Vector2 = point - direction * 26.0 + Vector2(0,4)
	label.x = clampf(label.x,safe.position.x + 38.0,safe.end.x - 38.0)
	return {"point":point,"direction":direction,"label":label.round(),"offscreen":true}

static func _wrap_lines(message: String,width: float,font_size: int) -> PackedStringArray:
	return PackedStringArray(UiArt.wrap_text(message,width,font_size))
