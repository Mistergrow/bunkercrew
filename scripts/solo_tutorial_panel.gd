extends Control
## Passive guidance shares the HUD's typography and edge placement. It owns
## no input handler: the field manual is the only place to operate the guide.
const L := preload("res://scripts/locale_text.gd")
const Marker := preload("res://scripts/story_objective_panel.gd")
var game: Node
var hud: Node
var _view: Dictionary = {}
var _refresh_clock := 1.0
var _presented := false

func _ready() -> void:
	name = "SoloTutorialPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440,900)

func controller() -> Node:
	return game.solo_tutorial if is_instance_valid(game) and "solo_tutorial" in game and is_instance_valid(game.solo_tutorial) else null

func _process(delta: float) -> void:
	_refresh_clock += delta
	if _refresh_clock >= .2:
		_refresh_clock = 0.0
		refresh_view()
	# Target coordinates belong to the world, while the card belongs to the HUD.
	# Reproject every rendered frame, including camera movement and zoom.
	var present := displays_guidance()
	if present or _presented: queue_redraw()
	_presented = present

func refresh_view() -> void:
	var guide := controller()
	var next: Dictionary = guide.get_view() if is_instance_valid(guide) else {}
	if next!=_view:
		_view = next
		queue_redraw()

func displays_guidance() -> bool:
	var guide := controller()
	if not is_instance_valid(guide) or not guide.is_available() or not bool(_view.get("active",false)): return false
	if not is_instance_valid(hud) or not hud.overlay.is_empty() or hud.blocks_gameplay_input() or get_tree().paused: return false
	if is_instance_valid(game.air_raid_intro) and game.air_raid_intro.active: return false
	if is_instance_valid(game.travel_cinematic) and game.travel_cinematic.is_presented(): return false
	if is_instance_valid(game.dialogue) and not game.dialogue.active.is_empty(): return false
	# Comic speech has precedence over onboarding, including authored worker
	# remarks. Its own presenter already computes visible state once per frame.
	if is_instance_valid(game.speech_bubbles) and bool(game.speech_bubbles.get("_visible")): return false
	return true

func card_layout() -> Dictionary:
	if not displays_guidance(): return {}
	var screen: Rect2 = hud.screen_rect()
	var width := minf(380.0,screen.size.x-36.0)
	var scale_factor := maxf(.1,hud.canvas.scale.x)
	var body_size := maxi(17,ceili(13.0/scale_factor))
	var title_size := maxi(21,ceili(15.0/scale_factor))
	var secondary_size := maxi(13,ceili(11.0/scale_factor))
	var line_height := float(body_size+5)
	var titles := UiArt.wrap_plain_text(str(_view.get("title","")),width-30.0,title_size,UiArt.MENU_FONT)
	var rows := UiArt.wrap_plain_text(str(_view.get("body","")),width-30.0,body_size)
	var title_height := float(title_size+5)
	var footer := UiArt.wrap_text("Pause → Handbuch: Tutorial verwalten",width-30.0,secondary_size)
	var height := 46.0+secondary_size+titles.size()*title_height+rows.size()*line_height+footer.size()*(secondary_size+4)
	var top := screen.position.y+74.0
	if is_instance_valid(hud.combat_overlay) and (not hud.combat_overlay.boss.is_empty() or not hud.combat_overlay.banners.is_empty()):
		top = hud.combat_overlay.notification_bounds(not hud.combat_overlay.boss.is_empty()).end.y+12.0
	if game.notice_time>0 and not game.notice.is_empty(): top = maxf(top,hud.notice_bounds().end.y+12.0)
	# Try the two calm edges, then move below any blocking instruments. These
	# rectangles are queried without this card, so HUD reservations cannot recurse.
	var occupied: Array[Rect2] = hud.occupied_gameplay_bounds(false)
	for worker: Node2D in game.players:
		if not is_instance_valid(worker): continue
		var head: Vector2 = hud.world_to_ui(worker.global_position+Vector2(-26,-70))
		var foot: Vector2 = hud.world_to_ui(worker.global_position+Vector2(26,10))
		occupied.append(Rect2(head,foot-head).abs().grow(8))
	var guide := controller()
	var target: Vector2 = guide.target_position()
	if target.is_finite(): occupied.append(Rect2(hud.world_to_ui(target)-Vector2(70,80),Vector2(140,105)))
	var left := screen.position.x+18.0
	var right := screen.end.x-width-18.0
	var candidates: Array[Vector2] = [Vector2(left,top),Vector2(right,top)]
	for blocked: Rect2 in occupied:
		if blocked.position.y<screen.get_center().y:
			candidates.append(Vector2(left,maxf(top,blocked.end.y+12.0)))
			candidates.append(Vector2(right,maxf(top,blocked.end.y+12.0)))
	var rect := Rect2()
	for at: Vector2 in candidates:
		var candidate := Rect2(at,Vector2(width,height))
		if candidate.end.y>screen.end.y-180.0: continue
		var clear := true
		for blocked: Rect2 in occupied:
			if blocked.grow(6).intersects(candidate): clear = false; break
		if clear: rect = candidate; break
	# Long modded instructions yield rather than covering workers or machinery.
	if not rect.has_area(): return {}
	return {"rect":rect,"titles":titles,"rows":rows,"footer":footer,"secondary_size":secondary_size,"body_size":body_size,"title_size":title_size,"line_height":line_height,"title_height":title_height}

func card_bounds() -> Rect2:
	return card_layout().get("rect",Rect2())

func marker_layout() -> Dictionary:
	var guide := controller()
	if not is_instance_valid(guide) or card_layout().is_empty(): return {}
	var target: Vector2 = guide.target_position()
	if not target.is_finite(): return {}
	for objective in get_tree().get_nodes_in_group("story_objective_panels"):
		if not is_instance_valid(objective.director) or objective.director.game!=game or objective.objective_bounds().has_area()==false: continue
		var story_target: Vector2 = objective.director.target_position()
		if story_target.is_finite() and story_target.distance_squared_to(target)<32.0*32.0: return {}
	var screen: Rect2 = hud.screen_rect()
	var top := screen.position.y+120.0
	var bottom := screen.end.y-160.0
	for occupied: Rect2 in hud.occupied_gameplay_bounds():
		if occupied.get_center().y<screen.get_center().y: top = maxf(top,occupied.end.y+24.0)
		else: bottom = minf(bottom,occupied.position.y-24.0)
	top = minf(top,bottom-100.0)
	return Marker.marker_layout(hud.world_to_ui(target),Rect2(screen.position.x+28.0,top,screen.size.x-56.0,bottom-top))

func _draw() -> void:
	var layout := card_layout()
	if layout.is_empty(): return
	var rect: Rect2 = layout.rect
	UiArt.hud_strip(self,rect)
	draw_rect(Rect2(rect.position,Vector2(2,rect.size.y)),UiArt.AMBER)
	UiArt.text(self,rect.position+Vector2(15,13+int(layout.secondary_size)),L.format("SOLO-TUTORIAL · %d / %d",[int(_view.get("index",0))+1,int(_view.get("count",1))]),int(layout.secondary_size),UiArt.AMBER)
	var baseline := 21.0+float(layout.secondary_size)+float(layout.title_size)
	for title: String in layout.titles:
		UiArt.text(self,rect.position+Vector2(15,baseline),title,int(layout.title_size),UiArt.IVORY,UiArt.MENU_FONT)
		baseline += float(layout.title_height)
	baseline += 3.0
	for row: String in layout.rows:
		UiArt.text(self,rect.position+Vector2(15,baseline),row,int(layout.body_size),UiArt.IVORY)
		baseline += float(layout.line_height)
	baseline += 5.0
	for row: String in layout.footer:
		UiArt.text(self,rect.position+Vector2(15,baseline),row,int(layout.secondary_size),UiArt.MUTED)
		baseline += float(int(layout.secondary_size)+4)
	var marker := marker_layout()
	if marker.is_empty(): return
	var point: Vector2 = marker.point
	if marker.offscreen:
		var direction: Vector2 = marker.direction
		var side := direction.orthogonal()*4.0
		var tail := point-direction*10.0
		draw_colored_polygon(PackedVector2Array([point,tail+side,tail-side]),UiArt.AMBER)
		UiArt.centered(self,marker.label,"TUTORIAL",maxi(13,ceili(11.0/maxf(.1,hud.canvas.scale.x))),UiArt.AMBER)
	else:
		draw_colored_polygon(PackedVector2Array([point+Vector2(-5,-8),point+Vector2(5,-8),point]),UiArt.AMBER)
