class_name ExpeditionPanel
extends Control
## A route chart with one selected destination. Live cargo controls use the same
## authoritative request path in solo, local co-op and network play.
const L := preload("res://scripts/locale_text.gd")
const MAP_RECT := Rect2(74,185,848,457)
static var LOAD_KINDS: Array[String]:
	get: return ItemCatalog.cargo_kinds()
var game
var hud
var selected_id := "harbor"
var cargo_kind := "steel"
var route_buttons: Dictionary = {}
var stop_buttons: Array[Button] = []
var cargo_selector: OptionButton
var depart_button: Button
var load_button: Button
var unload_button: Button
var refuel_button: Button
var repair_button: Button
var garage_button: Button
var _refresh_clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var state := _state()
	if state != null:
		if state.pending_node != CampaignCatalog.ENTRY: selected_id = state.pending_node
		state.changed.connect(_refresh)
	for entry: Dictionary in CampaignCatalog.NODES:
		var marker := _button("",Rect2(_map_position(entry)-Vector2(19,19),Vector2(38,38)),func(): _choose_route(entry.id))
		marker.tooltip_text = L.text(entry.title)
		marker.draw.connect(func(): _paint_marker(marker,entry))
		route_buttons[entry.id] = marker
	for index in 4:
		var slot := index
		var button := _button("",Rect2(980,419+index*43,366,37),func(): _choose_stop(slot))
		stop_buttons.append(button)
	depart_button = _button("Abfahrt",Rect2(980,638,366,38),_depart)
	garage_button = _button("Zur Garage · letzter Reisepunkt",Rect2(980,752,366,34),func(): _request("garage"))
	cargo_selector = OptionButton.new()
	cargo_selector.position = Vector2(77,717)
	cargo_selector.size = Vector2(326,38)
	UiArt.button(cargo_selector,12)
	for kind: String in LOAD_KINDS: cargo_selector.add_item(L.text(Balance.RESOURCE_NAMES[kind]))
	cargo_selector.select(LOAD_KINDS.find(cargo_kind))
	cargo_selector.item_selected.connect(func(index: int): cargo_kind=LOAD_KINDS[index]; _refresh())
	add_child(cargo_selector)
	load_button = _button("Einladen +1",Rect2(424,717,191,39),func(): _request("load",{"kind":cargo_kind,"amount":1}))
	unload_button = _button("Ausladen −1",Rect2(626,717,213,39),func(): _request("unload",{"kind":cargo_kind,"amount":1}))
	refuel_button = _button("Tanken · 2 Schrott",Rect2(424,765,191,39),func(): _request("refuel"))
	repair_button = _button("Reparieren · 2 Stahl",Rect2(626,765,213,39),func(): _request("repair"))
	_button("Zurück · Esc",Rect2(1182,93,164,38),func(): _request("back"))
	_refresh()
	if route_buttons.has(selected_id): route_buttons[selected_id].grab_focus.call_deferred()

func _state() -> CampaignState:
	if is_instance_valid(game) and "expedition" in game and is_instance_valid(game.expedition):
		return game.expedition.state
	return null

func _request(action: String, args: Dictionary = {}) -> void:
	if is_instance_valid(game) and is_instance_valid(game.expedition): game.expedition.request(action,args)
	_refresh()

func _process(delta: float) -> void:
	_refresh_clock += delta
	if _refresh_clock>=0.3:
		_refresh_clock = 0.0
		_refresh()

func _can_manage() -> bool:
	return is_instance_valid(game) and is_instance_valid(game.expedition) and game.expedition.can_manage() and (not is_instance_valid(game.network) or not game.network.active or game.network.is_host)

func _choose_route(id: String) -> void:
	selected_id = id
	var state := _state()
	if state != null and state.route_status(id).can_travel: _request("route",{"id":id})
	_refresh()

func _choose_stop(index: int) -> void:
	var state := _state()
	if state == null or selected_id!=state.pending_node: return
	_request("stop",{"id":"" if index==0 else selected_id+":"+["fuel","salvage","weapon"][index-1]})

func _depart() -> void:
	var state := _state()
	if state == null: return
	if game.expedition.can_retry_journey(): _request("retry"); return
	if state.expedition.stage in ["travel","stop","occupation"] or game.expedition.outpost_pending():
		var can_collect: bool=state.expedition.stage=="stop" and game.expedition.guard_count==0 and game.expedition.authoritative()
		_request("resume" if can_collect else "back")
		return
	if state.route_status(selected_id).can_unlock:
		_request("route",{"id":selected_id,"unlock":true})
		return
	_request("depart")

func _refresh() -> void:
	var state := _state()
	if state == null: return
	for id: String in route_buttons:
		route_buttons[id].queue_redraw()
	var can_manage := _can_manage()
	var route_selected := selected_id==state.pending_node and not CampaignCatalog.journey(selected_id).is_empty()
	for index in stop_buttons.size():
		var id: String = "" if index==0 else selected_id+":"+["fuel","salvage","weapon"][index-1]
		var entry := CampaignCatalog.stop(id)
		var chosen: bool = state.expedition.selected_stop==id
		var claimed: bool = state.expedition.claimed_stops.has(id)
		var title := "Direkte Route" if index==0 else str(entry.get("title",""))
		stop_buttons[index].visible = not state.completed.has(selected_id)
		stop_buttons[index].text = L.text(title).capitalize() + ("  ✓" if chosen or claimed else "")
		stop_buttons[index].disabled = not can_manage or not route_selected or claimed or state.completed.has(selected_id)
		stop_buttons[index].tooltip_text = L.text("Bereits geborgen") if claimed else L.text(str(entry.get("detail","Ohne Zwischenhalt zur nächsten Basis.")))
		if not entry.is_empty(): stop_buttons[index].tooltip_text += "\n"+L.format("%d Wachposten · Zusatzbedarf: %d Treibstoff",[entry.guards,entry.extra_fuel])
	var cost := CampaignCatalog.route_fuel(selected_id,state.expedition.selected_stop,state.expedition.vehicle.upgrades)
	var status := state.route_status(selected_id)
	var retry: bool=game.expedition.can_retry_journey()
	var underway: bool=state.expedition.stage in ["travel","stop","occupation"] or game.expedition.outpost_pending()
	garage_button.visible=state.expedition.stage in ["failed","travel","stop","occupation"]
	garage_button.disabled=not game.expedition.authoritative()
	garage_button.tooltip_text=L.text("Zur letzten gesicherten Abfahrt zurück. Fracht und Munition bleiben endlich.")
	if retry:
		depart_button.text=L.text("Erneut versuchen")
		depart_button.disabled=not game.expedition.authoritative()
	elif underway:
		depart_button.text=L.text("Zurück") if state.expedition.stage in ["occupation","defense"] else L.text("Fahrt fortsetzen")
		depart_button.disabled=false
	else:
		depart_button.text=L.text("Route entschlüsseln") if status.can_unlock else L.text("Crew einsteigen lassen")
		depart_button.disabled=not (can_manage and (status.can_unlock or (route_selected and status.can_travel and cost>0 and float(state.expedition.vehicle.fuel)>=cost)))
	var vehicle: Dictionary = state.expedition.vehicle
	var stats := CampaignCatalog.vehicle_stats(vehicle.upgrades)
	load_button.disabled = not can_manage or CampaignCatalog.cargo_count(vehicle.cargo)>=int(stats.cargo_capacity) or int(state.expedition.garage_stock.get(cargo_kind,0))<1
	unload_button.disabled = not can_manage or int(vehicle.cargo.get(cargo_kind,0))<1
	refuel_button.disabled = not can_manage or float(vehicle.fuel)>=float(stats.fuel_capacity) or int(state.expedition.garage_stock.get("scrap",0))<2
	repair_button.disabled = not can_manage or float(vehicle.hp)>=float(stats.max_hp) or int(state.expedition.garage_stock.get("steel",0))<2
	for index in LOAD_KINDS.size():
		cargo_selector.set_item_text(index,L.text(Balance.RESOURCE_NAMES[LOAD_KINDS[index]]))
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(0.02,0.04,0.04,0.8))
	UiArt.panel(self,Rect2(44,64,1352,777))
	UiArt.text(self,Vector2(77,112),"KONVOI · EINSATZKARTE",24)
	UiArt.text(self,Vector2(78,141),"Wähle den nächsten Bunker und einen optionalen Zwischenhalt.",12,UiArt.MUTED)
	var state := _state()
	if state == null: return
	_draw_chart(state)
	UiArt.divider(self,Vector2(951,185),Vector2(951,672))
	_draw_details(state)
	UiArt.divider(self,Vector2(78,682),Vector2(1345,682))
	var vehicle: Dictionary = state.expedition.vehicle
	var stats := CampaignCatalog.vehicle_stats(vehicle.upgrades)
	UiArt.text(self,Vector2(79,705),L.format("LADERAUM  %d / %d",[CampaignCatalog.cargo_count(vehicle.cargo),stats.cargo_capacity]),12,UiArt.AMBER)
	UiArt.text(self,Vector2(758,706),L.format("PANZERUNG  %d / %d",[int(vehicle.hp),stats.max_hp]),12)
	UiArt.text(self,Vector2(1054,706),L.format("TREIBSTOFF  %.1f / %d",[float(vehicle.fuel),stats.fuel_capacity]),12)
	UiArt.text(self,Vector2(79,789),L.format("An Bord: %d · Lager: %d",[int(vehicle.cargo.get(cargo_kind,0)),int(state.expedition.garage_stock.get(cargo_kind,0))]),12,UiArt.MUTED)
	if not garage_button.visible: UiArt.text(self,Vector2(866,773),"Ladung unterstützt die nächste Basis.",11,UiArt.MUTED)
	if is_instance_valid(game.expedition):
		var lines := UiArt.wrap_text(game.expedition.status_text(),466,11)
		for index in mini(lines.size(),2): UiArt.text(self,Vector2(866,807+index*15 if garage_button.visible else 797+index*15),lines[index],11,UiArt.AMBER)

func _draw_chart(state: CampaignState) -> void:
	draw_rect(MAP_RECT,Color("202e2b"))
	# Quiet contour lines and survey grid keep the map readable at QHD and HD.
	for index in 10:
		var points := PackedVector2Array()
		for step in 37:
			var at := Vector2(MAP_RECT.position.x+step*23.5,MAP_RECT.position.y+22+index*44+sin(step*0.43+index*0.8)*12)
			points.append(at)
		draw_polyline(points,Color("304039"),1)
	for index in 8:
		draw_line(Vector2(107+index*112,185),Vector2(107+index*112,642),Color(0.36,0.42,0.35,0.1),1)
	for entry: Dictionary in CampaignCatalog.NODES:
		if str(entry.parent).is_empty(): continue
		var from := _map_position(CampaignCatalog.node(entry.parent))
		var to := _map_position(entry)
		var tint := UiArt.AMBER if selected_id==entry.id else UiArt.GREEN if state.completed.has(entry.id) else Color("58634e")
		draw_line(from,to,tint,2 if selected_id==entry.id else 1)
	for entry: Dictionary in CampaignCatalog.NODES:
		var at := _map_position(entry)
		var title: String = L.text(entry.title).capitalize()
		var label_lines := UiArt.wrap_text(title,134,10)
		var color := UiArt.IVORY if selected_id==entry.id else UiArt.MUTED
		for index in mini(label_lines.size(),2):
			UiArt.centered(self,at+Vector2(0,35+index*13),label_lines[index],10,color)
	UiArt.text(self,Vector2(91,625),"● Gesichert   ◇ Nächstes Ziel",10,UiArt.MUTED)

func _draw_details(state: CampaignState) -> void:
	var entry := CampaignCatalog.node(selected_id)
	if entry.is_empty(): return
	var title_lines := UiArt.wrap_text(L.text(entry.title).capitalize(),359,21)
	for index in mini(title_lines.size(),2): UiArt.text(self,Vector2(982,211+index*27),title_lines[index],21)
	var detail_lines := UiArt.wrap_text(entry.detail,361,12)
	for index in mini(detail_lines.size(),4): UiArt.text(self,Vector2(982,278+index*18),detail_lines[index],12,UiArt.MUTED)
	var route := CampaignCatalog.journey(selected_id)
	if route.is_empty(): return
	var status := state.route_status(selected_id)
	UiArt.text(self,Vector2(982,372),status.reason,12,UiArt.GREEN if status.completed else UiArt.AMBER)
	if status.completed:
		var revisit_lines := UiArt.wrap_text(L.text("Sicherer Wiederbesuch · Keine neue Schicht oder Belohnung. Nimm Material für offene Crewkontakte mit."),361,12)
		for index in mini(revisit_lines.size(),4): UiArt.text(self,Vector2(982,425+index*18),revisit_lines[index],12,UiArt.MUTED)
	if not status.completed: UiArt.text(self,Vector2(982,405),"ZWISCHENHALT",11,UiArt.MUTED)
	var cost := CampaignCatalog.route_fuel(selected_id,state.expedition.selected_stop if selected_id==state.pending_node else "",state.expedition.vehicle.upgrades)
	var chosen: Dictionary = CampaignCatalog.stop(state.expedition.selected_stop) if selected_id==state.pending_node else {}
	var reward := L.text("Ohne Zwischenhalt zur nächsten Basis.")
	if status.completed: reward=L.text("Crewkontakte besuchen · mitgebrachte Fracht bleibt erhalten")
	if not chosen.is_empty():
		match str(chosen.kind):
			"fuel": reward = L.format("+%d Treibstoff · %d Wachposten",[chosen.fuel,chosen.guards])
			"salvage": reward = L.format("+4 Stahl · +3 Munition · %d Wachposten",chosen.guards)
			"weapon": reward = L.format("Episch: %s",WorkerWeapon.WEAPONS[str(chosen.weapon)].title)
	UiArt.text(self,Vector2(982,606),reward,10,UiArt.MUTED)
	UiArt.text(self,Vector2(982,626),L.format("Reisebedarf: %d Treibstoff",maxi(cost,0)),12,UiArt.AMBER)

func _paint_marker(button: Button, entry: Dictionary) -> void:
	var state := _state()
	if state==null: return
	var tint := UiArt.GREEN if state.completed.has(entry.id) else UiArt.AMBER if state.route_status(entry.id).can_travel else UiArt.MUTED
	var center := Vector2(19,19)
	if state.completed.has(entry.id):
		button.draw_circle(center,6,tint)
	else:
		button.draw_polyline(PackedVector2Array([center+Vector2(0,-8),center+Vector2(8,0),center+Vector2(0,8),center+Vector2(-8,0),center+Vector2(0,-8)]),tint,2)
	if selected_id==entry.id: button.draw_rect(Rect2(2,2,34,34),UiArt.AMBER,false,1)

func _map_position(entry: Dictionary) -> Vector2:
	return MAP_RECT.position+Vector2(10,12)+Vector2(float(entry.map[0])*(MAP_RECT.size.x-20),float(entry.map[1])*(MAP_RECT.size.y-90))

func _button(title: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = L.text(title)
	button.set_meta("source_text",title)
	button.position = rect.position
	button.size = rect.size
	UiArt.button(button,11)
	button.pressed.connect(callback)
	add_child(button)
	return button

func refresh_locale() -> void:
	for child in get_children():
		if child is Button and child.has_meta("source_text"):
			child.text = L.text(str(child.get_meta("source_text")))
	_refresh()
