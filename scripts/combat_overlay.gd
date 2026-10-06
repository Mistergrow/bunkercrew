class_name CombatOverlay
extends Control
const L := preload("res://scripts/locale_text.gd")
## Bounded, camera-aware combat messages. Decorative effects never affect damage.
const MAX_NUMBERS := 20
const MAX_BANNERS := 4
const BURST_GAP := 0.28
const CHASSIS := preload("res://assets/enemies/chassis_atlas.png")
const PORTRAITS := {"runner":Rect2(96,243,344,198),"strider":Rect2(558,220,396,252),"breaker":Rect2(1012,232,489,245),"colossus":Rect2(47,513,433,428),"assault":Rect2(508,626,442,271),"siege":Rect2(987,525,530,412)}
var game
var hud
var dispatcher
var numbers: Array[Dictionary] = []
var banners: Array[Dictionary] = []
var boss: Dictionary = {}
var clock := 0.0
var _number_sequence := 0
var _support_clock := 2.0
var _support_pending: Dictionary = {}
const ROLE_LABELS := {"team":"TEAMARBEIT","repair":"REPARATUR","production":"FERTIGUNG","supply":"VERSORGUNG","aid":"ERSTE HILFE","drive":"FAHRDIENST","craft":"HERSTELLUNG"}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_connect_dispatcher()

func _connect_dispatcher() -> void:
	if is_instance_valid(dispatcher): return
	if is_instance_valid(game) and "combat_events" in game and is_instance_valid(game.combat_events):
		dispatcher = game.combat_events
		if dispatcher.has_signal("event") and not dispatcher.event.is_connected(handle_event):
			dispatcher.event.connect(handle_event)

func reduced_effects() -> bool:
	return is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather) and game.weather.reduced_effects

func handle_event(kind: String,data: Dictionary) -> void:
	match kind:
		"support":
			var player_id := int(data.get("player_id",1))
			var session = game.get("network") if is_instance_valid(game) else null
			if is_instance_valid(session) and session.active and player_id!=int(session.local_player_id): return
			var earned := float(data.get("earned",0.0))
			if not is_finite(earned) or earned<=0: return
			var pending: Dictionary = _support_pending.get(player_id,{"earned":0.0,"action":str(data.get("action","team"))})
			pending.earned += earned
			if str(pending.action)!=str(data.get("action","team")): pending.action="team"
			_support_pending[player_id]=pending
		"hit", "kill":
			if not data.get("position") is Vector2: return
			var player_id := int(data.get("player_id",1))
			var amount := float(data.get("amount",data.get("damage",0.0)))
			var earned := float(data.get("earned",data.get("xp",0.0)))
			if kind=="hit" and amount<=0: return
			if kind=="hit":
				for entry in numbers:
					if entry.kind=="hit" and entry.player_id==player_id and entry.age<=BURST_GAP and _same_enemy(entry,data):
						entry.amount += amount
						entry.earned += earned
						entry.position = data.position
						entry.age = 0.0
						queue_redraw()
						return
			else:
				# The preceding hit event already contains the lethal bullet. The
				# kill contributes only its XP bonus, never that bullet's damage twice.
				var accumulated_damage := 0.0
				var had_hit := false
				for index in range(numbers.size()-1,-1,-1):
					var entry: Dictionary = numbers[index]
					if entry.kind=="hit" and entry.player_id==player_id and _same_enemy(entry,data):
						accumulated_damage += float(entry.amount)
						earned += float(entry.earned)
						had_hit = true
						numbers.remove_at(index)
				if had_hit: amount = accumulated_damage
			_number_sequence += 1
			numbers.append({"kind":kind,"player_id":player_id,"enemy_id":int(data.get("enemy_id",0)),"position":data.position,"amount":amount,"earned":earned,"age":0.0,"life":1.15 if kind=="kill" else 0.8,"sequence":_number_sequence})
			var limit := 8 if reduced_effects() else MAX_NUMBERS
			while numbers.size()>limit: numbers.pop_front()
		"level_up":
			_add_banner("level_up",L.format("P%d · LEVEL %02d", [int(data.get("player_id",1)),int(data.get("level",2))]),"Neuer Fähigkeitspunkt · P")
		"achievement":
			_add_banner("achievement",str(data.get("title","ERFOLG FREIGESCHALTET")),str(data.get("detail","")))
		"boss", "boss_phase":
			boss = {"title":str(data.get("title","SCHWERE MASCHINE")),"subtitle":str(data.get("subtitle","VERTEIDIGUNGSSTELLEN BESETZEN")),"portrait":str(data.get("portrait","siege")),"final_boss":bool(data.get("final_boss",false)),"age":0.0,"life":5.0}
	queue_redraw()

func _add_banner(kind: String,title: String,detail: String) -> void:
	banners.append({"kind":kind,"title":title,"detail":detail,"age":0.0,"life":3.8})
	while banners.size()>MAX_BANNERS: banners.pop_front()

func _process(delta: float) -> void:
	_connect_dispatcher()
	visible = is_instance_valid(game) and game.started and is_instance_valid(hud) and hud.overlay.is_empty() and not (hud.has_method("has_session_action") and hud.has_session_action())
	if get_tree().paused:
		return
	clock += delta
	_support_clock -= delta
	if _support_clock<=0:
		_support_clock = 2.0
		_flush_support()
	if reduced_effects():
		while numbers.size()>8: numbers.pop_front()
	for entry in numbers: entry.age += delta
	numbers = numbers.filter(func(entry): return entry.age<entry.life)
	if not boss.is_empty():
		boss.age += delta
		if boss.age>=boss.life: boss.clear()
	elif not banners.is_empty():
		banners[0].age += delta
		if banners[0].age>=banners[0].life: banners.pop_front()
	queue_redraw()

func _flush_support() -> void:
	if not is_instance_valid(game) or not "players" in game: return
	for player in game.players:
		if not is_instance_valid(player) or not _support_pending.has(player.player_id): continue
		var pending: Dictionary = _support_pending[player.player_id]
		_number_sequence += 1
		numbers.append({"kind":"support","action":pending.action,"player_id":player.player_id,"enemy_id":0,"position":player.global_position-Vector2(0,42),"amount":0.0,"earned":pending.earned,"age":0.0,"life":1.6,"sequence":_number_sequence})
	_support_pending.clear()
	while numbers.size()>MAX_NUMBERS: numbers.pop_front()

func _same_enemy(entry: Dictionary,data: Dictionary) -> bool:
	var enemy_id := int(data.get("enemy_id",0))
	if enemy_id>0:
		return int(entry.get("enemy_id",0))==enemy_id
	# Legacy/test emitters without identity still combine coincident pellets.
	return int(entry.get("enemy_id",0))==0 and entry.position.distance_to(data.position)<28

func _draw() -> void:
	for item in number_layout(): _draw_number(item.entry,item.position)
	_draw_boss_status()
	if not boss.is_empty():
		_draw_boss()
	elif not banners.is_empty():
		_draw_banner(banners[0])

func number_layout() -> Array[Dictionary]:
	# Resolve full two-line text rectangles, not just damage baselines. Fresh
	# impacts stay nearest their target; older neighbors occupy separate lanes.
	var result: Array[Dictionary] = []
	if numbers.is_empty(): return result
	var ordered: Array = numbers.duplicate()
	ordered.sort_custom(func(a,b): return int(a.sequence)>int(b.sequence) if is_equal_approx(a.age,b.age) else a.age<b.age)
	var reserved: Array[Rect2] = []
	if is_instance_valid(hud) and hud.has_method("occupied_gameplay_bounds"):
		reserved.append_array(hud.occupied_gameplay_bounds())
	if not boss.is_empty(): reserved.append(notification_bounds(true))
	elif not banners.is_empty(): reserved.append(notification_bounds())
	if is_instance_valid(dispatcher) and dispatcher.has_method("boss_status") and not dispatcher.boss_status().is_empty():
		reserved.append(boss_status_bounds())
	var viewport := _screen_rect()
	var bounds := Rect2(viewport.position + Vector2(25,160), viewport.size - Vector2(50,320))
	var dialogue = game.get("dialogue") if is_instance_valid(game) else null
	if is_instance_valid(dialogue) and not dialogue.active.is_empty() and dialogue.has_method("caption_layout"):
		var caption: Dictionary = dialogue.caption_layout()
		var caption_rect: Rect2 = caption.rect
		reserved.append(Rect2(caption_rect.position + viewport.position,caption_rect.size))
	for entry in ordered:
		var screen: Vector2 = get_global_transform_with_canvas().affine_inverse()*(get_viewport().get_canvas_transform()*entry.position)
		screen += Vector2(-24 if entry.player_id==1 else 24,-38-entry.age*(12 if reduced_effects() else 23))
		screen.x = clampf(screen.x,bounds.position.x + 75,bounds.end.x - 75)
		screen.y = clampf(screen.y,bounds.position.y + 27,bounds.end.y - 25)
		var lines := _number_lines(entry)
		var main_size := 11 if entry.kind=="support" else (17 if entry.kind=="kill" else 20)
		var width := maxf(UiArt.FONT.get_string_size(lines[0],HORIZONTAL_ALIGNMENT_LEFT,-1,main_size).x,UiArt.FONT.get_string_size(lines[1],HORIZONTAL_ALIGNMENT_LEFT,-1,11).x)+12
		var placed := false
		for column in [0,-1,1,-2,2,-3,3]:
			if placed: break
			for slot in range(21):
				var row := 0 if slot==0 else (-1 if slot%2==1 else 1)*floori((slot+1)/2.0)
				var candidate := screen+Vector2(column*(width+12),row*54)
				var rect := Rect2(candidate-Vector2(width/2,27),Vector2(width,50))
				if not bounds.encloses(rect): continue
				var overlaps := false
				for occupied in reserved:
					if rect.grow(2).intersects(occupied):
						overlaps = true
						break
				if overlaps: continue
				result.append({"entry":entry,"position":candidate,"rect":rect})
				reserved.append(rect)
				placed = true
				break
	return result

func _number_lines(entry: Dictionary) -> Array[String]:
	var main := _number_text(entry.amount)
	if entry.kind=="support": main=L.text(str(ROLE_LABELS.get(entry.get("action","team"),"TEAMARBEIT")))
	if entry.kind=="kill":
		main = (main+" · " if entry.amount>0 else "")+L.text("ABSCHUSS")
	return [main,L.format("+%s XP", _number_text(entry.earned))]

func _draw_number(entry: Dictionary,screen: Vector2) -> void:
	var progress: float = entry.age/entry.life
	var tint := PartyConfig.player_color(int(entry.player_id)).lightened(.18)
	tint.a = minf(1.0,(1.0-progress)*3.0)
	var lines := _number_lines(entry)
	var main_size := 11 if entry.kind=="support" else (14 if entry.kind=="kill" else 17)
	if entry.kind!="support" and not reduced_effects() and entry.age<0.09: main_size += 3
	for line in 2:
		if line==1 and entry.earned<=0: continue
		var font_size := main_size if line==0 else 11
		var value: String = lines[line]
		var width := UiArt.FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		var at := (screen+Vector2(-width/2,line*18)).round()
		draw_string_outline(UiArt.FONT,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,3,Color(0.02,0.03,0.03,tint.a))
		UiArt.text(self,at,value,font_size,tint)
	# The HUD already displays one current series per player. Repeating older
	# series on every corpse obscures both the earned XP and the battlefield.

func _number_text(amount: float) -> String:
	if amount>0.0 and amount<0.1: return "<0.1"
	return str(roundi(amount)) if is_equal_approx(amount,roundf(amount)) else L.format("%.1f", amount)

func _screen_rect() -> Rect2:
	return hud.screen_rect() if is_instance_valid(hud) and hud.has_method("screen_rect") else Rect2(0,0,1440,900)

func notification_bounds(boss_arrival: bool = false) -> Rect2:
	# Feedback shares one quiet edge location. It never covers the bunker center.
	var height := 64.0
	if boss_arrival:
		height = 118.0
	elif not banners.is_empty():
		var entry: Dictionary = banners[0]
		var titles := mini(2,UiArt.wrap_text(str(entry.title),282,15).size())
		var details := mini(3,UiArt.wrap_text(str(entry.detail),318,14).size())
		height = 26.0 + titles * 19.0 + details * 19.0
	return Rect2(_screen_rect().position + Vector2(18,74), Vector2(342,height))

func boss_status_bounds() -> Rect2:
	var status: Rect2 = hud.status_bounds() if is_instance_valid(hud) and hud.has_method("status_bounds") else Rect2(466,12,508,48)
	return Rect2(status.position + Vector2(0,status.size.y + 7),Vector2(status.size.x,37))

func _draw_wrapped(at: Vector2, value: String, width: float, font_size: int, tint: Color, max_lines: int = 2) -> void:
	var lines := UiArt.wrap_text(value,width,font_size)
	for index in mini(max_lines,lines.size()):
		var line := lines[index]
		if index == max_lines - 1 and lines.size() > max_lines:
			while UiArt.FONT.get_string_size(line + "…",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > width and not line.is_empty(): line = line.left(-1)
			line += "…"
		UiArt.text(self,at + Vector2(0,index * (font_size + 4)),line,font_size,tint)

func _draw_banner(entry: Dictionary) -> void:
	var age: float = entry.age
	var rect := notification_bounds()
	UiArt.hud_strip(self,rect)
	UiArt.icon(self,"helmet" if entry.kind=="level_up" else "check",rect.position+Vector2(13,7),18)
	_draw_wrapped(rect.position+Vector2(48,23),str(entry.title),282,15,UiArt.AMBER)
	var title_rows := mini(2,UiArt.wrap_text(str(entry.title),282,15).size())
	_draw_wrapped(rect.position+Vector2(12,23 + title_rows * 19),str(entry.detail),318,14,UiArt.IVORY,3)
	draw_line(rect.position+Vector2(0,rect.size.y-1),rect.position+Vector2(342*(1.0-age/entry.life),rect.size.y-1),UiArt.AMBER,1)

func _draw_boss_status() -> void:
	if not is_instance_valid(dispatcher) or not dispatcher.has_method("boss_status"): return
	var status: Dictionary = dispatcher.boss_status()
	if status.is_empty(): return
	var rect := boss_status_bounds()
	UiArt.hud_strip(self,rect)
	_draw_wrapped(rect.position+Vector2(12,17),str(status.get("title","SCHWERE MASCHINE")),385,12,UiArt.RED,1)
	UiArt.text(self,rect.position+Vector2(rect.size.x-91,17),L.format("PHASE %s", str(status.get("phase",1))),11,UiArt.MUTED)
	UiArt.bar(self,Rect2(rect.position+Vector2(12,26),Vector2(rect.size.x-24,4)),float(status.get("hp",0))/maxf(1,float(status.get("max_hp",1))),UiArt.RED)

func _draw_boss() -> void:
	var age: float = boss.age
	var rect := notification_bounds(true)
	UiArt.hud_strip(self,rect)
	draw_rect(Rect2(rect.position,Vector2(2,rect.size.y)),UiArt.RED)
	_draw_wrapped(rect.position+Vector2(12,22),str(boss.title),318,15,UiArt.RED)
	_draw_wrapped(rect.position+Vector2(12,63),str(boss.subtitle),231,12,UiArt.IVORY,3)
	var region: Rect2 = PORTRAITS.get(boss.portrait,PORTRAITS.siege)
	var scale_factor := minf(76.0/region.size.x,66.0/region.size.y)
	var portrait_size := region.size*scale_factor
	var portrait := Rect2(rect.position+Vector2(254,43)+(Vector2(76,66)-portrait_size)/2,portrait_size)
	draw_texture_rect_region(CHASSIS,portrait,region)
	if not reduced_effects():
		var scan_y := rect.position.y+43+fposmod(age*23,66)
		draw_line(Vector2(rect.position.x+254,scan_y),Vector2(rect.end.x-12,scan_y),Color(0.9,0.48,0.25,0.18),1)
