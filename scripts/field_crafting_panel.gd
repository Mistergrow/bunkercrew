extends Control
## Local order inspector. Every payment and collection is validated by the host.
const L := preload("res://scripts/locale_text.gd")
const NetInput := preload("res://scripts/network_input.gd")
const Workshop := preload("res://scripts/field_workshop.gd")
var game: Node
var hud: Node
var bench: Node
var player: Node
var selected_index := 0
var recipe_buttons: Array[Button] = []
var confirm_button: Button
var close_button: Button
var blocker: Control
var recipe_scroll: ScrollContainer
var detail_scroll: ScrollContainer
var detail_canvas: Control
var _pending_signature: Array = []
var _pending_deadline := 0
var _pending_index := -1
var _notice := ""

func _ready() -> void:
	name = "FieldCraftingPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(1440,900)
	blocker = Control.new()
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	selected_index = bench.recipe_index(player)
	recipe_scroll = ScrollContainer.new()
	recipe_scroll.position = Vector2(225,234)
	recipe_scroll.size = Vector2(960,142)
	recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	recipe_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	recipe_scroll.follow_focus = true
	_style_scroll(recipe_scroll.get_h_scroll_bar())
	recipe_scroll.get_h_scroll_bar().focus_mode = Control.FOCUS_NONE
	add_child(recipe_scroll)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation",10)
	recipe_scroll.add_child(strip)
	for index in Workshop.RECIPES.size():
		var button := _button("",Rect2(0,0,184,125),_select.bind(index),strip)
		button.custom_minimum_size = Vector2(184,125)
		button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		button.add_theme_constant_override("outline_size",0)
		button.draw.connect(_draw_recipe.bind(button,index))
		button.toggle_mode = true
		button.focus_entered.connect(_select.bind(index))
		recipe_buttons.append(button)
	detail_scroll = ScrollContainer.new()
	detail_scroll.position = Vector2(225,389)
	detail_scroll.size = Vector2(960,217)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_style_scroll(detail_scroll.get_v_scroll_bar())
	add_child(detail_scroll)
	detail_canvas = Control.new()
	detail_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_canvas.draw.connect(_draw_details)
	detail_scroll.add_child(detail_canvas)
	confirm_button = _button("",Rect2(620,673,570,50),_confirm)
	close_button = _button("Zurück  ·  Esc / B",Rect2(225,673,300,50),hud.close_crafting)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh()
	_wire_focus()
	recipe_buttons[selected_index].grab_focus.call_deferred()

func _button(label: String,rect: Rect2,callback: Callable,parent: Node = null) -> Button:
	var button := Button.new()
	button.text = L.text(label)
	button.position = rect.position
	button.size = rect.size
	SocialUiArt.button(button,19,"",0)
	button.pressed.connect(callback)
	(parent if parent != null else self).add_child(button)
	return button

func _style_scroll(bar: ScrollBar) -> void:
	for state: String in ["scroll","grabber","grabber_highlight","grabber_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(UiArt.STEEL,.45) if state=="scroll" else Color(UiArt.MUTED,.6) if state=="grabber" else Color(UiArt.AMBER,.8)
		style.content_margin_left = 3
		style.content_margin_right = 3
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		bar.add_theme_stylebox_override(state,style)

func _layout() -> void:
	var bounds: Rect2 = hud.screen_rect()
	blocker.position = bounds.position
	blocker.size = bounds.size
	queue_redraw()

func _wire_focus() -> void:
	var active: Array[Control] = []
	active.assign(recipe_buttons)
	var detail_bar := detail_scroll.get_v_scroll_bar()
	var scrollable := detail_canvas.custom_minimum_size.y>detail_scroll.size.y
	if scrollable: active.append(detail_bar)
	if not confirm_button.disabled: active.append(confirm_button)
	active.append(close_button)
	for index in active.size():
		var button := active[index]
		button.focus_next = button.get_path_to(active[(index+1)%active.size()])
		button.focus_previous = button.get_path_to(active[posmod(index-1,active.size())])
		if button is Button and recipe_buttons.has(button):
			var recipe_index := recipe_buttons.find(button)
			button.focus_neighbor_left = button.get_path_to(recipe_buttons[posmod(recipe_index-1,recipe_buttons.size())])
			button.focus_neighbor_right = button.get_path_to(recipe_buttons[(recipe_index+1)%recipe_buttons.size()])
			var below: Control = close_button if confirm_button.disabled else confirm_button
			if scrollable: below = detail_bar
			button.focus_neighbor_bottom = button.get_path_to(below)
			button.focus_neighbor_top = NodePath(".")
		else:
			button.focus_neighbor_left = button.get_path_to(close_button)
			button.focus_neighbor_right = button.get_path_to(confirm_button if not confirm_button.disabled else close_button)
			button.focus_neighbor_top = button.get_path_to(recipe_buttons[selected_index])
			button.focus_neighbor_bottom = NodePath(".")
	detail_bar.focus_mode = Control.FOCUS_ALL if scrollable else Control.FOCUS_NONE
	if scrollable:
		detail_bar.focus_neighbor_top = detail_bar.get_path_to(recipe_buttons[selected_index])
		detail_bar.focus_neighbor_bottom = detail_bar.get_path_to(confirm_button if not confirm_button.disabled else close_button)
		detail_bar.focus_neighbor_left = detail_bar.get_path_to(recipe_buttons[selected_index])
		detail_bar.focus_neighbor_right = detail_bar.get_path_to(confirm_button if not confirm_button.disabled else close_button)
		detail_bar.focus_previous = detail_bar.get_path_to(recipe_buttons[selected_index])
		detail_bar.focus_next = detail_bar.get_path_to(confirm_button if not confirm_button.disabled else close_button)

func _select(index: int) -> void:
	if selected_index != index: detail_scroll.scroll_vertical = 0
	selected_index = index
	_notice = ""
	_refresh()
	_wire_focus()
	if not recipe_buttons[index].has_focus(): recipe_buttons[index].grab_focus()
	recipe_scroll.ensure_control_visible.call_deferred(recipe_buttons[index])

func _network_ready() -> bool:
	var network = NetInput.for_game(game)
	return network == null or network.is_host or network.peer_connected

func _signature(index: int) -> Array:
	return [bench.order_view(player,index).duplicate(true),player.inventory.duplicate(),bench.armor_tier(player)]

func _process(_delta: float) -> void:
	if not is_instance_valid(bench) or not is_instance_valid(player) or not game.started or not hud.overlay.is_empty() or not bench.can_interact(player) or not game.valid_focus(player,bench):
		hud.close_crafting()
		return
	if not _pending_signature.is_empty():
		if _signature(_pending_index)!=_pending_signature:
			_pending_signature.clear()
		elif Time.get_ticks_msec()>=_pending_deadline:
			_pending_signature.clear()
			_notice = "Keine Bestätigung erhalten. Prüfe die Verbindung und versuche es erneut."
	_refresh()

func _refresh() -> void:
	var locked: String = bench.recipe_lock(player,selected_index)
	var order: Dictionary = bench.order_view(player,selected_index)
	var recipe: Dictionary = Workshop.RECIPES[selected_index]
	var note_lines := UiArt.wrap_text(str(recipe.note),940,16)
	var titles := UiArt.wrap_text(str(recipe.label),940,23,UiArt.MENU_FONT)
	var height := 113+maxi(0,titles.size()-1)*29+maxi(0,note_lines.size()-2)*23+maxi(0,recipe.cost.size()-1)*43+32
	detail_canvas.custom_minimum_size = Vector2(0,maxi(217,height))
	detail_canvas.queue_redraw()
	for index in recipe_buttons.size():
		recipe_buttons[index].queue_redraw()
		recipe_buttons[index].tooltip_text = L.text(str(Workshop.RECIPES[index].label))
		recipe_buttons[index].set_pressed_no_signal(index==selected_index)
	close_button.text = L.text("Zurück  ·  Esc / B")
	var can_supply := false
	var can_complete := true
	for kind: String in Workshop.RECIPES[selected_index].cost:
		can_supply = can_supply or (int(order.materials.get(kind,0))<int(Workshop.RECIPES[selected_index].cost[kind]) and int(player.inventory.get(kind,0))>0)
		can_complete = can_complete and int(order.materials.get(kind,0))+int(player.inventory.get(kind,0))>=int(Workshop.RECIPES[selected_index].cost[kind])
	var capacity: bool = bool(Workshop.RECIPES[selected_index].has("armor")) or player.carried_count()+int(Workshop.RECIPES[selected_index].get("amount",1))<=Balance.capacity_for(player)
	var was_disabled := confirm_button.disabled
	confirm_button.disabled = not _network_ready() or not _pending_signature.is_empty() or not locked.is_empty() or bool(order.working) or (not capacity if bool(order.ready) else not can_supply)
	var collect_label := "Rüstung anlegen" if recipe.has("armor") else "Bausatz abholen" if Workshop.KITS.has(recipe.kind) else "Gegenstand abholen"
	confirm_button.text = L.text("Warte auf den Gastgeber …" if not _pending_signature.is_empty() else "Fertigung läuft" if bool(order.working) else collect_label if bool(order.ready) else "Material einbauen · Fertigung starten" if can_complete else "Material einbauen")
	if was_disabled != confirm_button.disabled:
		_wire_focus()
		if confirm_button.disabled and confirm_button.has_focus(): recipe_buttons[selected_index].grab_focus()
	queue_redraw()

func _confirm() -> void:
	if confirm_button.disabled or not is_instance_valid(player) or not bench.can_interact(player): return
	var action_name := "collect" if bool(bench.order_view(player,selected_index).ready) else "supply"
	var network = NetInput.for_game(game)
	if network != null and not network.is_host:
		_pending_signature = _signature(selected_index)
		_pending_index = selected_index
		_pending_deadline = Time.get_ticks_msec()+8000
		network.send_command("craft",{"action":action_name,"recipe":CraftingCatalog.id(selected_index)})
	else:
		bench.request(player,action_name,selected_index)
	_refresh()
	_wire_focus()

func _input(event: InputEvent) -> void:
	if not visible or event.is_echo(): return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		hud.close_crafting()
		return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventAction:
		for action: String in ["ui_accept","ui_left","ui_right","ui_up","ui_down","ui_focus_next","ui_focus_prev"]:
			if event.is_action(action): return
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not is_instance_valid(bench) or not is_instance_valid(player): return
	var bounds: Rect2 = SocialUiArt.bounds(hud)
	draw_rect(bounds,Color(.01,.015,.018,.25))
	SocialUiArt.sheet(self,Rect2(195,145,1050,620))
	UiArt.text(self,Vector2(225,199),"Feldwerkbank",28,UiArt.IVORY,UiArt.TITLE_FONT)
	UiArt.text(self,Vector2(770,197),L.format("Persönliche Fertigung · Spieler %d",player.player_id),15,UiArt.MUTED)
	var recipe: Dictionary = Workshop.RECIPES[selected_index]
	var order: Dictionary = bench.order_view(player,selected_index)
	var status := _notice
	if not _network_ready(): status = "Verbindung unterbrochen. Wiederverbindung läuft …"
	elif bool(order.working): status = L.format("Herstellung · noch %.1f s",float(order.remaining))
	elif bool(order.ready): status = "Abholbereit" if player.carried_count()+int(recipe.get("amount",1))<=Balance.capacity_for(player) or recipe.has("armor") else "Inventar voll · Material einlagern"
	elif not _pending_signature.is_empty(): status = "Warte auf den Gastgeber …"
	if status.is_empty():
		status = bench.recipe_lock(player,selected_index)
	if status.is_empty(): status = L.format("Fertigungszeit: %.1f s",float(recipe.time))
	var lines := UiArt.wrap_text(status,960,16)
	for index in lines.size(): UiArt.text(self,Vector2(225,620+index*23),lines[index],16,UiArt.AMBER)
	UiArt.text(self,Vector2(225,750),"Einzahlungen und fertige Aufträge bleiben beim Planwechsel erhalten.",13,UiArt.MUTED)

func _draw_details() -> void:
	if not is_instance_valid(bench) or not is_instance_valid(player): return
	var recipe: Dictionary = Workshop.RECIPES[selected_index]
	var order: Dictionary = bench.order_view(player,selected_index)
	var titles := UiArt.wrap_text(str(recipe.label),940,23,UiArt.MENU_FONT)
	for index in titles.size(): UiArt.text(detail_canvas,Vector2(0,17+index*29),titles[index],23,UiArt.IVORY,UiArt.MENU_FONT)
	var title_extra := maxi(0,titles.size()-1)*29
	var notes := UiArt.wrap_text(str(recipe.note),940,16)
	for index in notes.size(): UiArt.text(detail_canvas,Vector2(0,49+title_extra+index*23),notes[index],16,UiArt.MUTED)
	var material_y := 95+title_extra+maxi(0,notes.size()-2)*23
	UiArt.text(detail_canvas,Vector2(0,material_y),"MATERIAL",12,UiArt.MUTED)
	var row := 0
	for kind: String in recipe.cost:
		var at := Vector2(0,material_y+18+row*43)
		UiArt.material(detail_canvas,kind,at,28)
		UiArt.text(detail_canvas,at+Vector2(44,22),Balance.RESOURCE_NAMES.get(kind,kind),18)
		UiArt.text(detail_canvas,at+Vector2(255,22),L.format("Eingebaut: %d / %d",[int(order.materials.get(kind,0)),int(recipe.cost[kind])]),17,UiArt.GREEN if int(order.materials.get(kind,0))>=int(recipe.cost[kind]) else UiArt.MUTED)
		UiArt.text(detail_canvas,at+Vector2(510,22),L.format("Bei dir: %d",int(player.inventory.get(kind,0))),17,UiArt.MUTED)
		row += 1

func _draw_recipe(button: Button,index: int) -> void:
	var recipe: Dictionary = Workshop.RECIPES[index]
	CraftingCatalog.draw_picture(button,index,Rect2(42,0,100,100))
	var tint := UiArt.AMBER if index==selected_index or button.has_focus() else UiArt.IVORY
	var labels := UiArt.wrap_text(str(recipe.label),172,16)
	for row in mini(2,labels.size()): UiArt.centered(button,Vector2(92,111 if labels.size()==1 else 101+row*17),labels[row],16,tint)
	if index==selected_index: button.draw_line(Vector2(12,123),Vector2(172,123),Color(UiArt.AMBER,.75),1)
