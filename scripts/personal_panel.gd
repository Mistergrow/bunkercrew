class_name PersonalPanel
extends Control
const L := preload("res://scripts/locale_text.gd")
const Dances := preload("res://scripts/worker_dance_catalog.gd")
var game
var hud
var selected_player := 0
var tab := "skills"
var elapsed := 0.0
var player_buttons: Array[Button] = []
var skill_buttons: Dictionary = {}
var tab_buttons: Dictionary = {}
var close_button: Button
var achievement_page:=0
var page_buttons: Array[Button]=[]
var dance_buttons: Array[Button] = []
var _dance_style_ids: Array[String] = []
var _roster_ids := PackedInt64Array()
var decoration: Control
var _landscape: Dictionary = {}
const ACHIEVEMENTS_PER_PAGE:=9
const TAB_TITLES := {"skills":"Fähigkeiten","achievements":"Erfolge","dances":"Tänze"}
const ACHIEVEMENT_TITLE_WIDTH := 244.0
const ACHIEVEMENT_DETAIL_WIDTH := 270.0
const SKILL_ICONS := {"vitality":"helmet","combat":"rifle","engineering":"craftsmanship"}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440,900)
	if not game.started:
		var environment := str(hud._main_menu_navigation.get("environment",hud.scenario_options.get("environment","sector07")))
		_landscape = SocialUiArt.create_landscape(self,game,hud,environment)
	decoration = Control.new()
	decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decoration.draw.connect(_draw_foreground)
	add_child(decoration)
	if _online():
		for index in game.players.size():
			if game.players[index].player_id==game.network.local_player_id:
				selected_player = index
				break
	_refresh_player_roster()
	for index in TAB_TITLES.size():
		var id: String = TAB_TITLES.keys()[index]
		var button := _button(TAB_TITLES[id],Rect2(80,224+index*64,290,50),func(): select_tab(id))
		SocialUiArt.button(button,24,"",0)
		button.toggle_mode = true
		button.gui_input.connect(_category_input.bind(id))
		tab_buttons[id] = button
	for index in PlayerProgression.SKILL_SPECS.size():
		var id: String = PlayerProgression.SKILL_SPECS.keys()[index]
		var button := _button("Verbessern · 1 Punkt",Rect2(1060,512+index*107,300,40),func(): purchase(id))
		skill_buttons[id] = button
	close_button = _button("Zurück  ·  P / Esc / B",Rect2(80,746,300,48),hud._close_personnel)
	SocialUiArt.button(close_button,20,"back",0)
	page_buttons.append(_button("‹",Rect2(1100,769,52,38),func(): change_achievement_page(-1)))
	page_buttons.append(_button("›",Rect2(1308,769,52,38),func(): change_achievement_page(1)))
	for index in 9:
		var rect := Rect2(480,420,880,42)
		if index in [1,2,3]: rect = Rect2(480+(index-1)*300,502,280,44)
		elif index>=4: rect = Rect2(480,581+(index-4)*42,880,40)
		var button := _button("",rect,func(): select_dance_index(index))
		button.add_theme_font_size_override("font_size",16)
		dance_buttons.append(button)
	if is_instance_valid(game.get("combat_events")) and game.combat_events.has_signal("dance_progress_changed"):
		game.combat_events.dance_progress_changed.connect(_dance_progress_changed)
	_refresh()
	tab_buttons[tab].grab_focus.call_deferred()

func select_player(index: int) -> void:
	if index<0 or index>=game.players.size(): return
	selected_player = index
	_refresh()

func select_tab(next: String) -> void:
	if next not in ["skills","achievements","dances"]: return
	tab = next
	_refresh()

func change_achievement_page(direction: int) -> void:
	var pages:=ceili(float(CombatEvents.ACHIEVEMENTS.size())/ACHIEVEMENTS_PER_PAGE)
	achievement_page=clampi(achievement_page+direction,0,maxi(0,pages-1))
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if tab!="achievements" or not visible: return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
			change_achievement_page(1)
			get_viewport().set_input_as_handled()
		elif event.button_index==MOUSE_BUTTON_WHEEL_UP:
			change_achievement_page(-1)
			get_viewport().set_input_as_handled()

func purchase(id: String) -> void:
	if not is_instance_valid(game) or selected_player<0 or selected_player>=game.players.size(): return
	var player = game.players[selected_player]
	if _online():
		if player.player_id!=game.network.local_player_id: return
		game.network.send_command("skill",{"id":id,"player_id":player.player_id})
	else:
		player.progression.purchase_skill(id)
	_refresh()

func _dance_player() -> Node:
	if not is_instance_valid(game) or not "players" in game or selected_player<0 or selected_player>=game.players.size(): return null
	return game.players[selected_player]

func _dance_level(player: Node) -> int:
	if not is_instance_valid(player) or not is_instance_valid(player.get("progression")): return 1
	var level := int(player.progression.level)
	if is_instance_valid(game.get("combat_events")) and game.combat_events.has_method("dance_level"):
		return int(game.combat_events.dance_level(str(player.character_id),level))
	return level

func select_dance_index(index: int) -> bool:
	if index<0 or index>=_dance_style_ids.size(): return false
	return select_dance(_dance_style_ids[index])

func select_dance(style: String) -> bool:
	var player := _dance_player()
	if not is_instance_valid(player) or not is_instance_valid(game.get("audio")): return false
	if _online() and player.player_id!=game.network.local_player_id: return false
	var id := str(player.character_id)
	if id not in Dances.IDS: return false
	if style not in Dances.styles_for(id) or not Dances.allowed(id,style,_dance_level(player)): return false
	var profiles := Dances.normalized_profiles(game.audio.dance_profiles)
	profiles[id].style = style
	game.audio.set_dance_configuration(float(game.audio.dance_intensity),profiles)
	_refresh()
	return true

func _dance_progress_changed(_character_id: String,_level: int) -> void:
	_refresh()

func _refresh_player_roster() -> bool:
	if not is_instance_valid(game): return false
	var ids := PackedInt64Array()
	for player: Node in game.players: ids.append(player.get_instance_id())
	if ids==_roster_ids: return false
	_roster_ids = ids
	var roster_had_focus := player_buttons.any(func(button: Button): return button.has_focus())
	for button: Button in player_buttons:
		remove_child(button)
		button.queue_free()
	player_buttons.clear()
	for index in game.players.size():
		var width: float = (880.0-(game.players.size()-1)*18.0)/game.players.size()
		var slot_rect := Rect2(480+index*(width+18),186,width,42)
		var button := _button(L.format("P%d",index+1),slot_rect,func(): select_player(index))
		player_buttons.append(button)
		var progression = game.players[index].progression
		if is_instance_valid(progression) and not progression.changed.is_connected(_refresh): progression.changed.connect(_refresh)
	if roster_had_focus and tab_buttons.has(tab): tab_buttons[tab].grab_focus.call_deferred()
	return true

func _button(title: String,rect: Rect2,callback: Callable) -> Button:
	var button := Button.new()
	button.text = L.text(title)
	button.position = rect.position
	button.size = rect.size
	SocialUiArt.button(button,17,"",0)
	button.pressed.connect(callback)
	add_child(button)
	return button

func _refresh() -> void:
	if not is_instance_valid(game): return
	var previous_focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	_refresh_player_roster()
	selected_player=clampi(selected_player,0,maxi(0,game.players.size()-1))
	var progression = game.players[selected_player].progression if not game.players.is_empty() else null
	if is_instance_valid(close_button): close_button.text = L.text("Zurück  ·  P / Esc / B")
	for id in skill_buttons:
		var button: Button = skill_buttons[id]
		button.visible = tab=="skills" and is_instance_valid(progression)
		button.disabled = not is_instance_valid(progression) or (_online() and game.players[selected_player].player_id!=game.network.local_player_id) or progression.skill_points<=0 or int(progression.skills[id])>=PlayerProgression.MAX_SKILL_RANK
		button.text = L.text("Maximaler Rang" if is_instance_valid(progression) and int(progression.skills[id])>=PlayerProgression.MAX_SKILL_RANK else "Verbessern · 1 Punkt")
	for index in player_buttons.size():
		player_buttons[index].text = L.format("Spieler %d%s" if player_buttons.size()<=2 else "P%d%s", [index+1,""])
		player_buttons[index].visible = tab!="achievements"
		_style_tab(player_buttons[index],selected_player==index)
	for id in tab_buttons:
		tab_buttons[id].text = L.text(TAB_TITLES[id])
		_style_tab(tab_buttons[id],tab==id)
	_refresh_dance_buttons()
	for button in page_buttons: button.visible=tab=="achievements"
	if page_buttons.size()==2:
		page_buttons[0].disabled=achievement_page<=0
		page_buttons[1].disabled=(achievement_page+1)*ACHIEVEMENTS_PER_PAGE>=CombatEvents.ACHIEVEMENTS.size()
		page_buttons[0].tooltip_text=L.text("Vorherige Seite")
		page_buttons[1].tooltip_text=L.text("Nächste Seite")
	_wire_focus()
	if is_instance_valid(previous_focus) and is_ancestor_of(previous_focus) and (not previous_focus.is_visible_in_tree() or (previous_focus is BaseButton and previous_focus.disabled)):
		tab_buttons[tab].grab_focus.call_deferred()
	_redraw()

func _content_controls() -> Array[Button]:
	var controls: Array[Button] = []
	for group: Array in [player_buttons,skill_buttons.values(),dance_buttons,page_buttons]:
		for button: Button in group:
			if button.is_visible_in_tree() and not button.disabled: controls.append(button)
	controls.sort_custom(func(first: Button,second: Button):
		return first.position.x<second.position.x if is_equal_approx(first.position.y,second.position.y) else first.position.y<second.position.y)
	return controls

func _category_input(event: InputEvent,id: String) -> void:
	var index := TAB_TITLES.keys().find(id)
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		var next := index+(-1 if event.is_action_pressed("ui_up") else 1)
		if next<0 or next>=TAB_TITLES.size():
			close_button.grab_focus()
		else:
			var next_id: String = TAB_TITLES.keys()[next]
			select_tab(next_id)
			tab_buttons[next_id].grab_focus()
		tab_buttons[id].accept_event()
	elif event.is_action_pressed("ui_right"):
		select_tab(id)
		var controls := _content_controls()
		if not controls.is_empty(): controls[0].grab_focus()
		tab_buttons[id].accept_event()

func _wire_focus() -> void:
	if not is_instance_valid(close_button) or tab_buttons.is_empty(): return
	var categories: Array[Button] = []
	for id: String in TAB_TITLES: categories.append(tab_buttons[id])
	var content := _content_controls()
	var order: Array[Button] = categories.duplicate()
	order.append_array(content)
	order.append(close_button)
	for index in order.size():
		var button := order[index]
		button.focus_next = button.get_path_to(order[(index+1)%order.size()])
		button.focus_previous = button.get_path_to(order[posmod(index-1,order.size())])
	for index in categories.size():
		var button := categories[index]
		button.focus_neighbor_top = button.get_path_to(close_button if index==0 else categories[index-1])
		button.focus_neighbor_bottom = button.get_path_to(close_button if index==categories.size()-1 else categories[index+1])
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(content[0] if not content.is_empty() else close_button)
	for button in content:
		for direction: String in ["top","bottom","left","right"]:
			var nearest: Button
			var score := INF
			var center := button.position+button.size*.5
			for candidate in content:
				if candidate==button: continue
				var offset := candidate.position+candidate.size*.5-center
				var vertical := direction in ["top","bottom"]
				var primary := offset.y if vertical else offset.x
				var cross := absf(offset.x if vertical else offset.y)
				if (direction in ["top","left"] and primary>=-1) or (direction in ["bottom","right"] and primary<=1): continue
				if not vertical and cross>1: continue
				var candidate_score := absf(primary)*10000+cross
				if candidate_score<score:
					score = candidate_score
					nearest = candidate
			if nearest==null:
				nearest = close_button if direction=="bottom" else tab_buttons[tab] if direction in ["left","top"] else button
			button.set("focus_neighbor_"+direction,button.get_path_to(nearest))
	close_button.focus_neighbor_top = close_button.get_path_to(categories[-1])
	close_button.focus_neighbor_bottom = close_button.get_path_to(categories[0])
	close_button.focus_neighbor_left = close_button.get_path_to(close_button)
	close_button.focus_neighbor_right = close_button.get_path_to(content[0] if not content.is_empty() else categories[0])

func _refresh_dance_buttons() -> void:
	var player := _dance_player()
	var id := str(player.character_id) if is_instance_valid(player) else Dances.IDS[0]
	_dance_style_ids = Dances.styles_for(id)
	var level := _dance_level(player)
	var audio = game.get("audio")
	var chosen := "character_default"
	if is_instance_valid(audio) and audio.get("dance_profiles") is Dictionary:
		chosen = str(audio.dance_profiles.get(id,{}).get("style","character_default"))
	if chosen not in _dance_style_ids or not Dances.allowed(id,chosen,level): chosen = "character_default"
	var can_edit: bool = is_instance_valid(player) and is_instance_valid(audio) and (not _online() or player.player_id==game.network.local_player_id)
	for index in dance_buttons.size():
		var button := dance_buttons[index]
		button.visible = tab=="dances" and is_instance_valid(player)
		var style := _dance_style_ids[index]
		var unlocked := Dances.allowed(id,style,level)
		var label := L.text("Automatisch · freigeschaltete Moves wechseln") if style=="character_default" else L.text(Dances.label(style))
		button.text = label if unlocked else L.format("%s · ab Level %d",[label,Dances.required_level(style)])
		button.disabled = not can_edit or not unlocked
		button.tooltip_text = L.text("Immer verfügbar") if style in Dances.SHARED_STYLES else L.text("Freigeschaltet") if unlocked else L.format("Wird auf Level %d dauerhaft freigeschaltet.",Dances.required_level(style))
		_style_tab(button,chosen==style)

func _process(delta: float) -> void:
	elapsed += delta
	if _refresh_player_roster(): _refresh()
	if _landscape.get("bounds")!=SocialUiArt.bounds(hud): SocialUiArt.layout_landscape(_landscape,hud)
	_redraw()

func _style_tab(button: Button,selected: bool) -> void:
	if button.toggle_mode: button.set_pressed_no_signal(selected)
	button.add_theme_color_override("font_color",UiArt.AMBER if selected else UiArt.IVORY)

func _redraw() -> void:
	if is_instance_valid(decoration): decoration.queue_redraw()

func _draw_foreground() -> void:
	if not is_instance_valid(game): return
	var bounds := SocialUiArt.bounds(hud)
	decoration.draw_rect(bounds,Color(.01,.015,.018,.20))
	SocialUiArt.reading_shade(decoration,bounds,420,800)
	UiArt.text(decoration,Vector2(80,112),"Personalakte",36,UiArt.IVORY,UiArt.TITLE_FONT)
	UiArt.text(decoration,Vector2(480,160),TAB_TITLES[tab],30,UiArt.IVORY,UiArt.MENU_FONT)
	var category: Button = tab_buttons[tab]
	decoration.draw_line(Vector2(64,category.position.y+14),Vector2(64,category.position.y+category.size.y-14),UiArt.AMBER,2)
	if tab=="achievements":
		_draw_achievements()
	elif tab=="dances":
		_draw_dances()
	else:
		_draw_personal()
	decoration.draw_line(Vector2(80,724),Vector2(360,724),Color(UiArt.MUTED,.22),1)
	UiArt.text(decoration,Vector2(80,819),"Pfeile / Steuerkreuz: wählen · Enter / A: bestätigen",13,UiArt.MUTED)
	UiArt.text(decoration,Vector2(480,855),"P: Figuren · F6: Erfolge",13,UiArt.MUTED)

func _draw_personal() -> void:
	if game.players.is_empty():
		UiArt.text(decoration,Vector2(480,270),"Fähigkeiten sind während einer Schicht verfügbar.",20,UiArt.MUTED)
		return
	var player = game.players[selected_player]
	var progression = player.progression
	var character: Dictionary = CharacterCatalog.data(player.character_id)
	var accent := Color(character.accent)
	UiArt.text(decoration,Vector2(480,269),L.text(str(character.title)).capitalize(),26,accent)
	UiArt.text(decoration,Vector2(480,293),L.format("Level %d",progression.level),15,UiArt.MUTED)
	CharacterSelectPanel.draw_portrait(decoration,player.character_id,Rect2(1160,237,190,180),elapsed)
	UiArt.text(decoration,Vector2(480,325),L.format("%d / %d LP",[ceili(player.hp),roundi(player.max_hp)]),16,UiArt.GREEN)
	UiArt.text(decoration,Vector2(660,325),L.format("Traglast  %d",player.capacity()),16,UiArt.MUTED)
	UiArt.text(decoration,Vector2(860,325),L.format("%d Abschüsse",progression.kills),16,UiArt.MUTED)
	UiArt.text(decoration,Vector2(480,357),L.format("Erfahrung  %d / %d XP",[floori(progression.xp),int(progression.xp_required())]),15)
	UiArt.bar(decoration,Rect2(480,371,270,5),progression.xp/progression.xp_required(),UiArt.AMBER)
	UiArt.text(decoration,Vector2(480,407),L.format("%d Fähigkeitspunkte",progression.skill_points),18,UiArt.AMBER)
	var armor: String = ["Arbeitskleidung","Schutzweste I","Panzerweste II"][clampi(progression.armor_tier,0,2)]
	UiArt.text(decoration,Vector2(800,357),armor,15)
	UiArt.text(decoration,Vector2(800,380),L.format("%d %% weniger Schaden",roundi(progression.armor_reduction()*100)),13,UiArt.MUTED)
	UiArt.text(decoration,Vector2(800,407),L.format("Trefferserie  %d ×",progression.combo),14,UiArt.MUTED)
	UiArt.bar(decoration,Rect2(800,419,270,4),progression.combo_time/PlayerProgression.COMBO_WINDOW,UiArt.AMBER)
	for index in PlayerProgression.SKILL_SPECS.size():
		var id: String = PlayerProgression.SKILL_SPECS.keys()[index]
		var spec: Dictionary = PlayerProgression.SKILL_SPECS[id]
		var rank := int(progression.skills[id])
		var y := 459+index*107
		UiArt.divider(decoration,Vector2(480,y-11),Vector2(1360,y-11))
		UiArt.icon(decoration,SKILL_ICONS[id],Vector2(480,y+3),32)
		UiArt.text(decoration,Vector2(528,y+25),L.text(str(spec.title)).capitalize(),21)
		UiArt.text(decoration,Vector2(1132,y+25),L.format("Rang %d / %d",[rank,PlayerProgression.MAX_SKILL_RANK]),14,UiArt.MUTED)
		for point in PlayerProgression.MAX_SKILL_RANK:
			decoration.draw_rect(Rect2(528+point*35,y+38,27,4),UiArt.AMBER if point<rank else Color("394039"))
		var lines := UiArt.wrap_text(str(spec.detail),490,16)
		for line in lines.size(): UiArt.text(decoration,Vector2(528,y+65+line*22),lines[line],16,UiArt.MUTED)

func _draw_achievements() -> void:
	var records: Array = game.combat_events.records() if "combat_events" in game and is_instance_valid(game.combat_events) else []
	var unlocked := 0
	for record in records:
		if record.unlocked: unlocked += 1
	UiArt.text(decoration,Vector2(480,195),L.format("%d von %d erreicht",[unlocked,records.size()]),15,UiArt.MUTED)
	var start:=achievement_page*ACHIEVEMENTS_PER_PAGE
	for index in mini(records.size()-start,ACHIEVEMENTS_PER_PAGE):
		var record: Dictionary = records[start+index]
		var pos := Vector2(480+(index%3)*300,232+floori(index/3.0)*168)
		if index>=3: UiArt.divider(decoration,pos+Vector2(0,-13),pos+Vector2(280,-13))
		UiArt.icon(decoration,"check" if record.unlocked else "lock",pos+Vector2(0,7),22,Color.WHITE if record.unlocked else UiArt.MUTED)
		var titles := UiArt.wrap_text(str(record.title),ACHIEVEMENT_TITLE_WIDTH,16)
		for line in titles.size(): UiArt.text(decoration,pos+Vector2(36,25+line*22),titles[line],16,UiArt.AMBER if record.unlocked else UiArt.MUTED)
		var details := UiArt.wrap_text(str(record.detail),ACHIEVEMENT_DETAIL_WIDTH,13)
		for line in details.size(): UiArt.text(decoration,pos+Vector2(0,72+line*19),details[line],13,UiArt.IVORY if record.unlocked else UiArt.MUTED)
		if int(record.get("goal",0))>0 and not record.unlocked:
			UiArt.text(decoration,pos+Vector2(0,150),L.format("%d / %d",[mini(int(record.progress),int(record.goal)),record.goal]),12,UiArt.AMBER)
	var public_count := 0
	var secret_count := 0
	for record: Dictionary in records:
		if bool(record.get("hidden",false)): secret_count += 1
		else: public_count += 1
	UiArt.text(decoration,Vector2(480,794),L.format("%d öffentliche · %d geheime Erfolge",[public_count,secret_count]),13,UiArt.MUTED)
	UiArt.centered(decoration,Vector2(1230,794),L.format("Seite %d / %d",[achievement_page+1,ceili(float(records.size())/ACHIEVEMENTS_PER_PAGE)]),13,UiArt.MUTED)

func _draw_dances() -> void:
	var player := _dance_player()
	if not is_instance_valid(player):
		UiArt.text(decoration,Vector2(480,270),"Starte eine Schicht, um Tänze auszuwählen.",20,UiArt.MUTED)
		return
	var id := str(player.character_id)
	var character := CharacterCatalog.data(id)
	var level := _dance_level(player)
	var learned := 0
	for style: String in Dances.UNIQUE_STYLES.get(id,[]):
		if Dances.required_level(style)<=level: learned += 1
	UiArt.text(decoration,Vector2(480,269),L.text(str(character.title)).capitalize(),26,Color(character.accent))
	UiArt.text(decoration,Vector2(480,293),L.format("Level %d · Tänze bis Level %d",[int(player.progression.level),level]),15,UiArt.MUTED)
	CharacterSelectPanel.draw_portrait(decoration,id,Rect2(1160,237,190,165),elapsed)
	UiArt.text(decoration,Vector2(480,325),L.format("Eigene Moves: %d / 5",learned),18,UiArt.AMBER)
	UiArt.bar(decoration,Rect2(480,340,540,5),float(learned)/5.0,UiArt.AMBER)
	UiArt.text(decoration,Vector2(480,372),"Tänze bleiben nach der Schicht freigeschaltet.",15,UiArt.MUTED)
	UiArt.text(decoration,Vector2(480,398),"Neue Moves: Level 2, 4, 6, 8, 10",14,UiArt.MUTED)
	UiArt.text(decoration,Vector2(480,488),"Drei Crew-Moves · immer verfügbar",15,UiArt.MUTED)
	UiArt.text(decoration,Vector2(480,567),"Fünf eigene Moves · durch Charakterlevel",15,UiArt.AMBER)
	UiArt.text(decoration,Vector2(480,819),"Tanzt nur in Ruhe und zum hörbaren Beat.",13,UiArt.MUTED)

func _online() -> bool:
	return "network" in game and is_instance_valid(game.network) and game.network.active

func refresh_locale() -> void:
	_refresh()
	_redraw()
