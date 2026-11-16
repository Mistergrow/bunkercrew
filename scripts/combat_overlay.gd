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
## Lane offsets (columns of one number width, rows of one number height)
## tried for a combat number, nearest its own place first: one step up,
## beside it, then further out; never more than three rows or one column away.
const LANES: Array[Vector2i] = [Vector2i(0,0),Vector2i(0,-1),Vector2i(1,0),Vector2i(-1,0),Vector2i(1,-1),Vector2i(-1,-1),Vector2i(0,1),Vector2i(0,-2),Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-2),Vector2i(-1,-2),Vector2i(0,2),Vector2i(0,-3),Vector2i(1,2),Vector2i(-1,2),Vector2i(1,-3),Vector2i(-1,-3),Vector2i(0,3),Vector2i(1,3),Vector2i(-1,3)]
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
						_bind_target(entry,data)
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
			var number := {"kind":kind,"player_id":player_id,"enemy_id":int(data.get("enemy_id",0)),"position":data.position,"amount":amount,"earned":earned,"age":0.0,"life":1.15 if kind=="kill" else 0.8,"sequence":_number_sequence}
			_bind_target(number,data)
			numbers.append(number)
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
	for entry in numbers:
		entry.age += delta
		_follow_target(entry)
	numbers = numbers.filter(func(entry): return entry.age<entry.life)
	if not boss.is_empty():
		boss.age += delta
		if boss.age>=boss.life: boss.clear()
	elif not banners.is_empty():
		banners[0].age += delta
		if banners[0].age>=banners[0].life: banners.pop_front()
	queue_redraw()

## Support XP of one flush is ONE compact team line, a HUD tab under the status
## strip with a colour pip per earner, never a word over the crew: printed over
## a worker it covered the P tags (and the medic's callsign) of everyone at
## that post.
func _flush_support() -> void:
	if not is_instance_valid(game) or not "players" in game: return
	var earners: Array = []
	var total := 0.0
	var action := ""
	for player in game.players:
		if not is_instance_valid(player) or not _support_pending.has(player.player_id): continue
		var pending: Dictionary = _support_pending[player.player_id]
		earners.append(player)
		total += float(pending.earned)
		action = str(pending.action) if action.is_empty() or action==str(pending.action) else "team"
	_support_pending.clear()
	if not earners.is_empty():
		var ids: Array[int] = []
		for player in earners: ids.append(int(player.player_id))
		_number_sequence += 1
		numbers.append({"kind":"support","merged":true,"players":ids,"action":action,"player_id":ids[0],"enemy_id":0,"position":Vector2.ZERO,"amount":0.0,"earned":total,"age":0.0,"life":1.6,"sequence":_number_sequence})
	while numbers.size()>MAX_NUMBERS: numbers.pop_front()

## Damage and kill numbers ride on the machine they hit: the number keeps the
## hit's offset from that enemy and follows it while it lives, then holds its
## last place. Only a live enemy of this game at the reported hit position is
## bound, looked up among the enemies by identity (an id from another peer
## never latches onto an unrelated local node).
func _bind_target(entry: Dictionary,data: Dictionary) -> void:
	var enemy_id := int(data.get("enemy_id",0))
	if enemy_id<=0 or not is_inside_tree(): return
	var bound: Variant = entry.get("anchor")
	if bound is WeakRef and is_instance_valid(bound.get_ref()) and (bound.get_ref() as Node).get_instance_id()==enemy_id:
		entry.offset = data.position-(bound.get_ref() as Node2D).global_position
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.get_instance_id()!=enemy_id or not node is Node2D or node.get("game")!=game: continue
		var origin: Vector2 = (node as Node2D).global_position
		if origin.distance_to(data.position)>220.0: return
		entry.anchor = weakref(node)
		entry.offset = data.position-origin
		return

func _follow_target(entry: Dictionary) -> void:
	var bound: Variant = entry.get("anchor")
	if not bound is WeakRef: return
	var target: Variant = bound.get_ref()
	if target is Node2D and is_instance_valid(target) and not (target as Node).is_queued_for_deletion():
		entry.position = (target as Node2D).global_position+(entry.offset as Vector2)
	else:
		entry.erase("anchor")

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
	# Enemy bars and names of the threat read: a number printed over a bar
	# hid both.
	var threat: CanvasItem = get_parent().get_node_or_null("ThreatOverlay") as CanvasItem if is_instance_valid(get_parent()) else null
	if threat != null and threat.visible and "drawn_rects" in threat: reserved.append_array(threat.get("drawn_rects"))
	# The crew's P tags and SAN-1's callsign: a number never prints over them.
	if is_instance_valid(hud) and hud.has_method("world_label_rects"): reserved.append_array(hud.world_label_rects())
	if is_instance_valid(hud) and hud.has_method("wave_banner_rect") and hud.wave_banner_rect().has_area(): reserved.append(hud.wave_banner_rect())
	var viewport := _screen_rect()
	var bounds := Rect2(viewport.position + Vector2(25,160), viewport.size - Vector2(50,320))
	var dialogue = game.get("dialogue") if is_instance_valid(game) else null
	if is_instance_valid(dialogue) and not dialogue.active.is_empty() and dialogue.has_method("caption_layout"):
		var caption: Dictionary = dialogue.caption_layout()
		var caption_rect: Rect2 = caption.rect
		reserved.append(Rect2(caption_rect.position + viewport.position,caption_rect.size))
	var to_screen := get_global_transform_with_canvas().affine_inverse()*get_viewport().get_canvas_transform()
	var rise := 12.0 if reduced_effects() else 23.0
	for entry in ordered:
		var merged := bool(entry.get("merged",false))
		var screen: Vector2
		if merged:
			# The team line rests under the status strip; it only fades.
			screen = _team_anchor()
		else:
			screen = to_screen*entry.position
			# A number belongs next to its machine: when that point has left
			# the screen (beyond what the edge clamp below can absorb), the number
			# goes with it instead of sticking to the edge with nothing near it.
			if not viewport.grow(120).has_point(screen): continue
			screen += Vector2(-24 if entry.player_id==1 else 24,-30-entry.age*rise)
		screen.x = clampf(screen.x,bounds.position.x + 75,bounds.end.x - 75)
		screen.y = clampf(screen.y,bounds.position.y + 27,bounds.end.y - 25)
		var lines := _number_lines(entry)
		var main_size := _main_size(entry)
		var width := maxf(UiArt.FONT.get_string_size(lines[0],HORIZONTAL_ALIGNMENT_LEFT,-1,main_size).x+_pip_width(entry),UiArt.FONT.get_string_size(lines[1],HORIZONTAL_ALIGNMENT_LEFT,-1,12).x)+(20.0 if merged else 12.0)
		var height := 26.0 if merged else (30.0 if lines[1].is_empty() else 50.0)
		# Lanes stay close to the target: the free spot nearest the number's
		# own place (beside it before far above it, see LANES); a number that
		# finds none is left out rather than parked with no machine near it.
		for lane: Vector2i in LANES:
			var candidate := screen+Vector2(lane.x*(width+12),lane.y*(height+4))
			var rect := Rect2(candidate-Vector2(width/2,height*.54),Vector2(width,height))
			if not bounds.encloses(rect): continue
			var overlaps := false
			for occupied in reserved:
				if rect.grow(2).intersects(occupied):
					overlaps = true
					break
			if overlaps: continue
			result.append({"entry":entry,"position":candidate,"rect":rect})
			reserved.append(rect)
			break
	return result

## A hit reads as the damage it did, in whole points over the machine; a kill
## reads as the word and the XP it brought (the damage of the burst was already
## shown by its hits, and a bare "65.5" beside the word explained nothing).
func _number_lines(entry: Dictionary) -> Array[String]:
	var main := _damage_text(entry.amount)
	if entry.kind=="support": main=L.text(str(ROLE_LABELS.get(entry.get("action","team"),"TEAMARBEIT")))
	if entry.kind=="kill": main = L.text("ABSCHUSS")
	# The shared team line carries its XP on the same row.
	if bool(entry.get("merged",false)): return [main+"  "+L.format("+%s XP", _number_text(entry.earned)),""]
	# A running hit is one short damage line; its XP is summed into the kill
	# line (or the HUD's XP bar), so a burst never stacks two-line labels.
	if entry.kind=="hit": return [main,""]
	return [main,L.format("+%s XP", _number_text(entry.earned))]

func _main_size(entry: Dictionary) -> int:
	if bool(entry.get("merged",false)): return 13
	return 12 if entry.kind=="support" else (17 if entry.kind=="kill" else 20)

## Room for the earners' colour pips in front of a merged team line.
func _pip_width(entry: Dictionary) -> float:
	if not bool(entry.get("merged",false)): return 0.0
	return (entry.players as Array).size()*7.0+5.0

## Where the merged team line rests: centred under the status strip (wave,
## enemies, bunker), the team's own corner of the HUD, instead of over the
## crew in the world.
func _team_anchor() -> Vector2:
	var status: Rect2 = hud.status_bounds() if is_instance_valid(hud) and hud.has_method("status_bounds") else Rect2(466,12,508,48)
	return Vector2(status.get_center().x,status.end.y+24.0)

func _draw_number(entry: Dictionary,screen: Vector2) -> void:
	var progress: float = entry.age/entry.life
	var tint := PartyConfig.player_color(int(entry.player_id)).lightened(.18)
	tint.a = minf(1.0,(1.0-progress)*3.0)
	var lines := _number_lines(entry)
	# Drawn sizes; _main_size() measures with the brief +3 pop included.
	var main_size := _main_size(entry) if entry.kind=="support" else (14 if entry.kind=="kill" else 17)
	if entry.kind!="support" and not reduced_effects() and entry.age<0.09: main_size += 3
	# Every line carries a dark ink ring (UiArt.outlined), so pale player
	# colours stay readable on snow, bright sky and lit machinery alike.
	var step := UiArt.ring_step(self)
	if bool(entry.get("merged",false)):
		_draw_team_line(entry,screen,lines[0],main_size)
		return
	for line in 2:
		if line==1 and (entry.earned<=0 or lines[1].is_empty()): continue
		var font_size := main_size if line==0 else 12
		var value: String = lines[line]
		var width := UiArt.FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		var at := (screen+Vector2(-width/2,line*18)).round()
		UiArt.outlined(self,at,value,font_size,tint if line==0 else Color(tint.lerp(UiArt.IVORY,.45),tint.a),step)
	# The HUD already displays one current series per player. Repeating older
	# series on every corpse obscures both the earned XP and the battlefield.

## The shared team line is a HUD tab hanging under the status strip, not a
## word in the sky: a strip-coloured plate with an amber rule on top, the
## earners' colour pips and the line on it. It opens from its centre, holds
## fully opaque and closes back to its centre; the words only show while the
## plate is fully open, so they never fade over a bright sky or a dark one.
func _draw_team_line(entry: Dictionary,screen: Vector2,line: String,font_size: int) -> void:
	var opening := 1.0
	if UiMotion.enabled():
		opening = minf(clampf(float(entry.age)/UiMotion.QUICK,0.0,1.0),clampf((float(entry.life)-float(entry.age))/UiMotion.BASE,0.0,1.0))
		opening = UiMotion.ease_out(opening)
	var pips := _pip_width(entry)
	var text_width := UiArt.FONT.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	var full := Vector2(pips+text_width+20.0,23.0)
	var width := maxf(4.0,roundf(full.x*opening))
	var plate := Rect2(Vector2(roundf(screen.x-width*.5),roundf(screen.y-16.0)),Vector2(width,full.y))
	draw_rect(plate,Color(.095,.125,.108,.94))
	draw_rect(Rect2(plate.position,Vector2(plate.size.x,2)),UiArt.AMBER)
	draw_rect(Rect2(plate.position+Vector2(0,plate.size.y),Vector2(plate.size.x,1)),Color(.03,.05,.04,.65))
	if opening<1.0: return
	var left := roundf(screen.x-full.x*.5)+10.0
	var players: Array = entry.players
	for index in players.size():
		var pip := Rect2(Vector2(left+index*7.0,screen.y-font_size*.5-2.0).round(),Vector2(5,5))
		draw_rect(pip.grow(1),UiArt.INK)
		draw_rect(pip,PartyConfig.player_color(int(players[index])))
	draw_string(UiArt.FONT,Vector2(left+pips,screen.y).round(),line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,UiArt.IVORY.lerp(UiArt.AMBER,.35))

## XP with one decimal where it has one, in the player's language ("13,9" in
## German); a sliver below a tenth never shows as a rounded-up point.
func _number_text(amount: float) -> String:
	if amount>0.0 and amount<0.1: return "<"+L.decimal(0.1)
	var tenths := roundf(amount*10.0)
	return str(roundi(amount)) if is_equal_approx(fmod(tenths,10.0),0.0) else L.format("%.1f", tenths/10.0)

## Damage in whole points; a graze below one point reads "<1".
func _damage_text(amount: float) -> String:
	if amount>0.0 and amount<0.5: return "<1"
	return str(roundi(amount))

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
	# Anchored to the HUD's centred safe area like the notices below it.
	var safe: Rect2 = hud.hud_rect() if is_instance_valid(hud) and hud.has_method("hud_rect") else _screen_rect()
	return Rect2(safe.position + Vector2(18,74), Vector2(342,height))

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
	# The final machine's health reads at a glance: an inked 7 px meter with
	# quarter ticks under its title (a 4 px bar thinned out to 1-2 px lines).
	UiArt.meter(self,Rect2(rect.position+Vector2(12,23),Vector2(rect.size.x-24,7)),float(status.get("hp",0))/maxf(1,float(status.get("max_hp",1))),UiArt.RED)

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
