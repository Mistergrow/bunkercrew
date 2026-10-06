extends SceneTree
## Actual research controls, input ownership and authoritative transactions.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const L := preload("res://scripts/locale_text.gd")
const PREPARED_OWNED := ["bunker_workshop","core_resilience","medic_logistics","weapon_handling","boots"]
const OUTPUT := "res://artifacts/technology-style-20261005/regression/"
var game
var view: SubViewport
var checks := 0
var failures := 0
var transactions := 0
var observations: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("TECHNOLOGY PRESENTATION %s: %s"%["PASS" if ok else "FAIL",label])

func frames(count: int = 3) -> void:
	for unused in count:
		await process_frame

func raw_key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		view.push_input(event,true)

func raw_joy(code: JoyButton) -> void:
	for down in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		view.push_input(event,true)

func key(code: Key,shift: bool = false) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = down
		view.push_input(event,true)
		await process_frame
	await frames()

func joy(code: JoyButton) -> void:
	for down in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		view.push_input(event,true)
		await process_frame
	await frames()

func mouse_point(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas()*(control.size*.5)

func mouse_move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point-view.get_mouse_position()
	view.push_input(event,true)
	await frames()

func mouse_button(point: Vector2,button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.pressed = down
		view.push_input(event,true)
		await process_frame
	await frames()

func canvas_bounds(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	return Rect2(transform*Vector2.ZERO,control.size*transform.get_scale())

func focused_inside(panel: Control) -> bool:
	var control := view.gui_get_focus_owner()
	return is_instance_valid(control) and control.is_visible_in_tree() and panel.is_ancestor_of(control) and not (control is BaseButton and control.disabled)

func focusable(panel: Control) -> Array[Control]:
	var result: Array[Control] = []
	var pending: Array[Node] = [panel]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children(true))
		if not node is Control or not node.is_visible_in_tree() or node.focus_mode==Control.FOCUS_NONE:
			continue
		if node is BaseButton and node.disabled:
			continue
		result.append(node)
	return result

func seed_research(wave: int = 16,points: int = 19,owned: Array = PREPARED_OWNED) -> void:
	game.rounds.wave = wave
	game.rounds.phase = "build"
	game.upgrades.points = points
	game.upgrades.owned.clear()
	for id: String in owned:
		game.upgrades.owned[id] = true
	if is_instance_valid(game.hud.upgrade_panel):
		game.hud.upgrade_panel._refresh()

func fixture(resolution: Vector2i = Vector2i(1280,720),locale: String = "de") -> void:
	L.set_locale(locale,false)
	view = SubViewport.new()
	view.size = resolution
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.gui_embed_subwindows = true
	view.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(view)
	game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	await frames(5)
	game.start_scenario(1,{"environment":"sector07","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	for worker in game.players:
		worker.set_physics_process(false)
	game.elapsed = 8.0
	seed_research()
	game.hud._layout_viewport()
	game.hud._toggle_upgrades()
	await frames(5)

func retire() -> void:
	paused = false
	await Cleanup.free_scene(game,self)
	game = null
	view.queue_free()
	await frames()

func _text_fit(panel: Control,label: String) -> void:
	for control: Control in focusable(panel):
		if not control is Button or control.text.is_empty():
			continue
		var font := control.get_theme_font("font")
		var style := control.get_theme_stylebox("normal")
		var width := control.size.x-style.get_content_margin(SIDE_LEFT)-style.get_content_margin(SIDE_RIGHT)
		check(font.get_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,-1,control.get_theme_font_size("font_size")).x<=width+1.0,label+": localized native action fits "+str(control.name))
	for entry: Dictionary in panel._visible_entries:
		var lines: Array = panel.node_title_lines(entry)
		var size: int = panel._node_title_size(str(entry.title))
		check(lines.size()<=2 and size>=16,label+": real row title is readable: "+str(entry.id))
		for line: String in lines:
			check(UiArt.FONT.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=panel._node_title_width(str(entry.id))+1,label+": translated title fits its actual row: "+str(entry.id))
		var button: Button = panel._button_for(str(entry.id))
		var row_status := L.text("Freigeschaltet") if game.upgrades.has_upgrade(str(entry.id)) else L.format("%d TP",entry.cost)
		var status_start := button.size.x-UiArt.FONT.get_string_size(row_status,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x-23
		var title_end: float = panel.ROW_TITLE_INSET+UiArt.FONT.get_string_size(str(lines[0]),HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
		check(title_end<status_start,label+": actual first title line clears its price/owned glyphs: "+str(entry.id))
		var detail_lines: Array = panel._detail_lines(str(entry.detail))
		var last_detail_bottom := 354+(detail_lines.size()-1)*23+UiArt.FONT.get_descent(panel.BODY_SIZE)
		var prerequisite_heading_top := 557-UiArt.FONT.get_ascent(12)
		check(last_detail_bottom<prerequisite_heading_top,label+": actual description glyphs clear the prerequisite heading: "+str(entry.id))
		var requirements: Array = UiArt.wrap_text(panel._row_requirement(entry),button.size.x-panel.ROW_TITLE_INSET-6,14)
		check(69+(requirements.size()-1)*19+UiArt.FONT.get_descent(14)<button.size.y-1,label+": actual row subtitle glyphs clear its divider: "+str(entry.id))
	var selected_entry: Dictionary = game.upgrades.node_data(panel.selected_id)
	var reason: String = game.upgrades.requirement(panel.selected_id)
	var status: String = panel._selection_status(selected_entry,reason)
	check(UiArt.wrap_text(status,panel.DETAIL_RECT.size.x,15).size()<=2,label+": active requirement fits above confirmation")

func _category_input(panel: Control,category: int,label: String) -> void:
	var before: int = game.upgrades.points
	var owned: Dictionary = game.upgrades.owned.duplicate()
	await mouse_move(mouse_point(panel.tab_buttons[category]))
	await mouse_button(mouse_point(panel.tab_buttons[category]))
	check(panel.selected_category==category and panel.tab_buttons[category].button_pressed,label+": native click opens category "+str(category))
	check(focused_inside(panel),label+": category change keeps a real visible focus")
	check(game.upgrades.points==before and game.upgrades.owned==owned,label+": choosing a category never purchases research")

func _browse(panel: Control,label: String) -> void:
	var before: int = game.upgrades.points
	var owned: Dictionary = game.upgrades.owned.duplicate()
	var expected: Array = panel._visible_entries.duplicate()
	var first: Button = panel._button_for(str(expected[0].id))
	first.grab_focus()
	await frames()
	for index in expected.size():
		if index>0:
			await joy(JOY_BUTTON_DPAD_DOWN)
		var id := str(expected[index].id)
		var button: Button = panel._button_for(id)
		check(button.has_focus() and panel.selected_id==id,label+": real D-pad inspects research "+id)
		check(canvas_bounds(panel.tree_scroll).grow(1.0).encloses(canvas_bounds(button)),label+": selected research row is fully revealed: "+id)
		check(game.upgrades.points==before and game.upgrades.owned==owned,label+": inspection preserves shared points and entitlements: "+id)
		check(button.tooltip_text.is_empty(),label+": inspected row has no duplicate tooltip: "+id)
	check(panel._visible_entries.size()==game.upgrades.nodes_for_category(panel.selected_category).size(),label+": no catalog research disappears in the actual list")
	for button: Button in panel.node_buttons:
		var index: int = panel.node_buttons.find(button)
		check(button.visible==(int(UpgradeSystem.NODES[index].branch)==panel.selected_category),label+": hidden categories expose no interactive rows "+str(index))
	check(panel.tree_scroll.scroll_horizontal==0 and panel.tree_scroll.horizontal_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,label+": no horizontal scroll hides research")
	await joy(JOY_BUTTON_DPAD_LEFT)
	check(panel.tab_buttons[panel.selected_category].has_focus(),label+": D-pad left returns to the active category")
	await joy(JOY_BUTTON_DPAD_RIGHT)
	check(focused_inside(panel) and panel.is_ancestor_of(view.gui_get_focus_owner()),label+": D-pad right reenters an actual research control")

func _tab_cycle(panel: Control,label: String) -> void:
	panel.tab_buttons[panel.selected_category].grab_focus()
	await frames()
	var expected: Array[Control] = []
	expected.append_array(panel.tab_buttons)
	for entry: Dictionary in panel._visible_entries:
		expected.append(panel._button_for(str(entry.id)))
	expected.append(panel.close_button)
	var scrollbar: VScrollBar = panel.tree_scroll.get_v_scroll_bar()
	if scrollbar.is_visible_in_tree() and scrollbar.focus_mode!=Control.FOCUS_NONE:
		expected.append(scrollbar)
	var visited: Dictionary = {}
	var sequence: Array[String] = []
	var all_valid := true
	for unused in (expected.size()+4)*2:
		var focused := view.gui_get_focus_owner()
		all_valid = all_valid and focused_inside(panel)
		if is_instance_valid(focused):
			visited[focused.get_instance_id()] = true
			sequence.append(str(focused.name))
		await key(KEY_TAB)
	var reaches_all := expected.all(func(control: Control): return visited.has(control.get_instance_id()))
	if not all_valid or not reaches_all:
		print("TECHNOLOGY TAB ",label," expected=",expected.map(func(control: Control): return str(control.name))," sequence=",sequence)
	check(all_valid,label+": native Tab always stays on a usable control in this panel")
	check(reaches_all,label+": native Tab reaches categories, every research row, scrollbar and Back")
	var forward := view.gui_get_focus_owner()
	await key(KEY_TAB,true)
	check(focused_inside(panel) and view.gui_get_focus_owner()!=forward,label+": Shift-Tab traverses the real reverse focus chain")
	await key(KEY_TAB)
	check(view.gui_get_focus_owner()==forward,label+": reverse navigation returns to the same control")

func _layouts() -> void:
	for resolution: Vector2i in [Vector2i(960,600),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		view.size = resolution
		game.hud._layout_viewport()
		await frames()
		for locale: String in ["de","en"]:
			L.set_locale(locale,false)
			var panel: Control = game.hud.upgrade_panel
			panel.refresh_locale()
			var label := "%s %dx%d"%[locale,resolution.x,resolution.y]
			for category in UpgradeSystem.CATEGORIES.size():
				await _category_input(panel,category,label)
				await _browse(panel,label+" category"+str(category))
				_text_fit(panel,label+" category"+str(category))
				for control: Control in focusable(panel):
					if panel.tree_content.is_ancestor_of(control): continue
					check(view.get_visible_rect().grow(1.0).encloses(canvas_bounds(control)),label+": native screen contains control "+str(control.name))
				check(panel.tab_buttons.all(func(button: Button): return button.get_theme_stylebox("normal").bg_color.a==0.0),label+": category actions use the shared transparent options/lobby style")
				check(panel.tab_buttons[0].position.x==80 and panel.tab_buttons[1].position.y>panel.tab_buttons[0].position.y,label+": category navigation follows the actual vertical options layout")
				observations.append({"locale":locale,"resolution":[resolution.x,resolution.y],"category":category,"selected":panel.selected_id,"scroll":panel.tree_scroll.scroll_vertical,"rows":panel._visible_entries.size(),"focus":str(view.get_path_to(view.gui_get_focus_owner()))})
		view.size = resolution
		game.hud._layout_viewport()
		for category in UpgradeSystem.CATEGORIES.size():
			await _category_input(game.hud.upgrade_panel,category,str(resolution.x))
			await _tab_cycle(game.hud.upgrade_panel,"category%d width%d"%[category,resolution.x])

func _purchase_selected(panel: Control,id: String,use_mouse: bool = false) -> void:
	panel._select(id)
	await frames()
	var before: int = game.upgrades.points
	var changes := transactions
	check(not panel.purchase_button.disabled,"Actual confirmation is enabled for affordable research "+id)
	if use_mouse:
		await mouse_move(mouse_point(panel.purchase_button))
		await mouse_button(mouse_point(panel.purchase_button))
	else:
		panel.purchase_button.grab_focus()
		await joy(JOY_BUTTON_A)
	var entry: Dictionary = game.upgrades.node_data(id)
	check(game.upgrades.has_upgrade(id) and game.upgrades.points==before-int(entry.cost),"Native explicit confirmation pays the real research cost exactly once: "+id)
	check(transactions==changes+1,"Native explicit confirmation emits exactly one authoritative transaction: "+id)
	check(panel.purchase_button.disabled and focused_inside(panel),"Purchase leaves a visible usable focus after the confirm action becomes disabled: "+id)
	await key(KEY_ENTER)
	check(game.upgrades.points==before-int(entry.cost) and transactions==changes+1,"Immediate second native accept cannot double-purchase "+id)

func _focus_role(panel: Control,control: Control) -> String:
	if not is_instance_valid(control): return "none"
	if control is Button:
		for index in panel.tab_buttons.size():
			if control==panel.tab_buttons[index]: return "category"+str(index)
		for index in panel.node_buttons.size():
			if control==panel.node_buttons[index]: return str(UpgradeSystem.NODES[index].id)
	if control==panel.purchase_button: return "purchase"
	if control==panel.prerequisite_button: return "prerequisite"
	if control==panel.close_button: return "back"
	if control==panel.tree_scroll.get_v_scroll_bar(): return "scrollbar"
	return control.get_class()+":"+str(control.name)

func _friends_roundtrip(panel: Control,label: String) -> Control:
	var state := {"category":panel.selected_category,"selected":panel.selected_id,"scroll":panel.tree_scroll.scroll_vertical,"focus":_focus_role(panel,view.gui_get_focus_owner())}
	var points: int = game.upgrades.points
	var owned: Dictionary = game.upgrades.owned.duplicate()
	await key(KEY_F7)
	check(game.hud.overlay=="friends" and paused,label+": actual F7 opens friends over the paused research match")
	await joy(JOY_BUTTON_B)
	var restored: Control = game.hud.upgrade_panel
	check(game.hud.overlay=="upgrades" and is_instance_valid(restored) and paused,label+": actual B returns to the same research screen")
	if restored.selected_category!=state.category or restored.selected_id!=state.selected or restored.tree_scroll.scroll_vertical!=state.scroll or _focus_role(restored,view.gui_get_focus_owner())!=state.focus:
		print("TECHNOLOGY FRIENDS ",label," before=",state," after=",[restored.selected_category,restored.selected_id,restored.tree_scroll.scroll_vertical,_focus_role(restored,view.gui_get_focus_owner())])
	check(restored.selected_category==state.category and restored.selected_id==state.selected and restored.tree_scroll.scroll_vertical==state.scroll,label+": friend roundtrip preserves category, selected software stage and exact native scroll")
	check(focused_inside(restored) and _focus_role(restored,view.gui_get_focus_owner())==state.focus,label+": friend roundtrip restores the actual control role")
	check(game.upgrades.points==points and game.upgrades.owned==owned,label+": friend roundtrip changes neither points nor researched technologies")
	return restored

func _friends_navigation() -> void:
	seed_research()
	var panel: Control = game.hud.upgrade_panel
	panel._select("bunker_dance_5")
	await frames(5)
	check(panel.tree_scroll.scroll_vertical>0 and panel._button_for("bunker_dance_5").has_focus(),"Actual last SAN software stage owns a scrolled, focused native row")
	panel = await _friends_roundtrip(panel,"last SAN software row")
	var scrollbar: VScrollBar = panel.tree_scroll.get_v_scroll_bar()
	check(scrollbar.is_visible_in_tree() and scrollbar.focus_mode!=Control.FOCUS_NONE,"Long SAN software category has a usable native scrollbar")
	if scrollbar.is_visible_in_tree() and scrollbar.focus_mode!=Control.FOCUS_NONE:
		scrollbar.grab_focus()
		await frames()
		panel = await _friends_roundtrip(panel,"native scrollbar")
	panel._select("precision_lines")
	await frames()
	panel.purchase_button.grab_focus()
	await frames()
	panel = await _friends_roundtrip(panel,"available explicit confirmation")
	panel.tab_buttons[0].grab_focus()
	await key(KEY_ENTER)
	await joy(JOY_BUTTON_DPAD_DOWN)
	await joy(JOY_BUTTON_A)
	check(panel.selected_category==1 and panel.tab_buttons[1].has_focus(),"Native D-pad plus A chooses the next vertical research category")
	panel = await _friends_roundtrip(panel,"focused weapon category")

func _same_frame_input() -> void:
	for controller in [false,true]:
		seed_research(16,19,PREPARED_OWNED)
		var panel: Control = game.hud.upgrade_panel
		panel._select("weapon_magazines")
		await frames()
		panel.purchase_button.grab_focus()
		await frames()
		check(not panel.purchase_button.disabled and panel.purchase_button.has_focus(),"Same-frame fixture owns an actual affordable research confirmation")
		var points: int = game.upgrades.points
		raw_key(KEY_F7)
		check(game.hud.overlay=="friends","Actual F7 transfers input ownership before the next frame")
		if controller: raw_joy(JOY_BUTTON_A)
		else: raw_key(KEY_ENTER)
		check(game.upgrades.points==points and not game.upgrades.has_upgrade("weapon_magazines"),"Immediate same-frame "+("controller A" if controller else "Enter")+" cannot buy through the replaced research screen")
		await frames()
		check(game.hud.overlay=="friends" and game.upgrades.points==points and not game.upgrades.has_upgrade("weapon_magazines"),"Deferred rebuild preserves the same-frame no-purchase result")
		await joy(JOY_BUTTON_B)
		check(game.hud.overlay=="upgrades" and focused_inside(game.hud.upgrade_panel),"Actual B returns to research after rapid input without losing its usable focus")
	for controller in [false,true]:
		var back_panel: Control = game.hud.upgrade_panel
		back_panel.close_button.grab_focus()
		await frames()
		raw_key(KEY_F7)
		if controller: raw_joy(JOY_BUTTON_A)
		else: raw_key(KEY_ENTER)
		check(game.hud.overlay=="friends","Immediate same-frame "+("controller A" if controller else "Enter")+" on obsolete Back cannot close the new friends screen")
		await frames()
		check(game.hud.overlay=="friends" and paused,"The real friends screen still owns input after rapid obsolete Back activation")
		await joy(JOY_BUTTON_B)
		check(game.hud.overlay=="upgrades" and game.hud.upgrade_panel.close_button.has_focus(),"Returning from friends retains the precise Back focus after the rapid transition")
	for route: Dictionary in [{"key":KEY_DOWN},{"key":KEY_TAB},{"joy":JOY_BUTTON_DPAD_DOWN},{"joy":JOY_BUTTON_DPAD_RIGHT}]:
		var navigation_panel: Control = game.hud.upgrade_panel
		navigation_panel._select("weapon_magazines")
		await frames()
		var held_id: String = navigation_panel.selected_id
		var held_category: int = navigation_panel.selected_category
		var held_scroll: int = navigation_panel.tree_scroll.scroll_vertical
		var held_focus := _focus_role(navigation_panel,view.gui_get_focus_owner())
		raw_key(KEY_F7)
		if route.has("key"): raw_key(route.key)
		else: raw_joy(route.joy)
		await frames()
		check(game.hud.overlay=="friends","Actual friends screen owns same-frame native navigation: "+str(route))
		await joy(JOY_BUTTON_B)
		navigation_panel = game.hud.upgrade_panel
		check(navigation_panel.selected_category==held_category and navigation_panel.selected_id==held_id and navigation_panel.tree_scroll.scroll_vertical==held_scroll and _focus_role(navigation_panel,view.gui_get_focus_owner())==held_focus,"Same-frame F7 navigation cannot modify the obsolete research selection/focus before its native rebuild: "+str(route))
	for code: Key in [KEY_T,KEY_ESCAPE]:
		seed_research()
		var closing_panel: Control = game.hud.upgrade_panel
		closing_panel._select("precision_lines")
		await frames()
		closing_panel.purchase_button.grab_focus()
		var points_before: int = game.upgrades.points
		raw_key(code)
		raw_key(KEY_ENTER)
		check(game.hud.overlay.is_empty() and game.upgrades.points==points_before and not game.upgrades.has_upgrade("precision_lines"),"Same-frame close followed by Accept cannot purchase from the obsolete control: "+str(code))
		await frames()
		await key(KEY_T)
		check(game.hud.overlay=="upgrades" and focused_inside(game.hud.upgrade_panel),"Actual T safely reopens research after same-frame close")

func _online_command() -> void:
	# Prepared session contract with actual loopback ENet byte delivery; the
	# existing multiplayer integration suite covers the authenticated handshake.
	var Transport := preload("res://scripts/network_transport.gd")
	var Protocol := preload("res://scripts/network_protocol.gd")
	var receiver := Transport.new()
	var sender := Transport.new()
	root.add_child(receiver)
	root.add_child(sender)
	var port := 27000+OS.get_process_id()%20000
	var opened: Error = ERR_CANT_CREATE
	for offset in 8:
		opened = receiver.host(port+offset,false)
		if opened==OK:
			port += offset
			break
	check(opened==OK,"Native UI command probe opens an actual isolated ENet listener without UPnP")
	if opened!=OK:
		receiver.queue_free()
		sender.queue_free()
		await frames()
		return
	var inbox: Array[Dictionary] = []
	var packets: Array[Dictionary] = []
	receiver.packet.connect(func(bytes: PackedByteArray):
		var decoded: Dictionary = Protocol.decode(bytes)
		packets.append(decoded)
		if decoded.get("kind")=="command" and decoded.get("command")=="upgrade":
			inbox.append(decoded))
	check(sender.join("127.0.0.1",port)==OK,"Native UI command probe connects its actual local ENet guest")
	var deadline := Time.get_ticks_msec()+5000
	while (sender.connected_peer==0 or receiver.connected_peer==0) and Time.get_ticks_msec()<deadline:
		await process_frame
	check(sender.connected_peer>0 and receiver.connected_peer>0,"Actual local ENet peers complete transport connection")
	var session: Node = game.network
	session.set_process(false)
	session.active = true
	session.is_host = false
	session.local_player_id = 2
	session.state = "playing"
	session.match_paused = true
	session.peer_connected = true
	session._authenticated = true
	session._loading = false
	session._closing = false
	session.transport = sender
	seed_research(1,4,["weapon_handling"])
	var panel: Control = game.hud.upgrade_panel
	panel._select("weapon_magazines")
	await frames()
	check(panel.purchase_button.disabled,"Actual online guest sees the wave1 magazine gate")
	game.rounds.wave = 2
	deadline = Time.get_ticks_msec()+1000
	while panel.purchase_button.disabled and Time.get_ticks_msec()<deadline:
		await process_frame
	check(not panel.purchase_button.disabled and game.upgrades.points==4 and not game.upgrades.has_upgrade("weapon_magazines"),"Actual online wave1-to2 update refreshes the inspector without buying or rebuilding the panel")
	session._authenticated = false
	await frames()
	check(panel.purchase_button.disabled,"An unauthenticated actual online guest cannot authorize research")
	session._authenticated = true
	session._loading = true
	await frames()
	check(panel.purchase_button.disabled,"An actual online guest cannot authorize research during a world transition")
	session._loading = false
	await frames()
	check(not panel.purchase_button.disabled,"Authenticated active guest research resumes after the transition gate clears")
	var unchanged_panel := panel.get_instance_id()
	var changes := transactions
	panel.purchase_button.grab_focus()
	await joy(JOY_BUTTON_A)
	deadline = Time.get_ticks_msec()+3000
	while inbox.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame
	check(inbox.size()==1 and inbox[0].get("kind")=="command" and inbox[0].get("command")=="upgrade" and inbox[0].get("args",{}).get("id")=="weapon_magazines","One native guest confirmation produces one original encoded upgrade command over actual ENet")
	check(game.upgrades.points==4 and not game.upgrades.has_upgrade("weapon_magazines") and transactions==changes,"Guest UI sends its command without spending or inventing local research")
	await key(KEY_ENTER)
	check(inbox.size()==1 and panel.purchase_button.disabled,"Pending guest confirmation prevents an accidental repeated native research request")
	var waiting_state: Dictionary = panel.navigation_state()
	panel = await _friends_roundtrip(panel,"pending online research request")
	check(panel.navigation_state().pending_id==waiting_state.pending_id and panel.navigation_state().pending_deadline==waiting_state.pending_deadline and inbox.size()==1,"F7 keeps the actual pending request and its original deadline without retransmitting")
	unchanged_panel = panel.get_instance_id()
	if not inbox.is_empty():
		session.is_host = true
		session._handle_command(str(inbox[0].command),inbox[0].args,2)
		await frames()
		check(game.upgrades.points==1 and game.upgrades.has_upgrade("weapon_magazines") and transactions==changes+1,"Original authority command handler applies the actual received guest purchase exactly once")
		session._handle_command(str(inbox[0].command),inbox[0].args,2)
		await frames()
		check(game.upgrades.points==1 and transactions==changes+1,"Repeated received research command cannot spend shared points twice")
		check(game.hud.upgrade_panel.get_instance_id()==unchanged_panel and panel.purchase_button.disabled and focused_inside(panel),"Actual authoritative update retains the inspector and repairs its disabled confirmation focus")
	# Advance the real finite request deadline without waiting eight seconds;
	# the original panel process owns timeout handling and all displayed text.
	session.is_host = false
	seed_research(2,4,["weapon_handling"])
	panel._select("weapon_magazines")
	await frames()
	inbox.clear()
	await mouse_move(mouse_point(panel.purchase_button))
	await mouse_button(mouse_point(panel.purchase_button))
	deadline = Time.get_ticks_msec()+3000
	while inbox.is_empty() and Time.get_ticks_msec()<deadline:
		await process_frame
	check(inbox.size()==1 and panel.purchase_button.disabled and not str(panel._pending_id).is_empty(),"Actual unconfirmed guest request exposes pending feedback instead of a duplicate action")
	panel._pending_deadline = Time.get_ticks_msec()-1
	await frames()
	var timeout_notice: String = panel._request_notice
	check(str(panel._pending_id).is_empty() and not timeout_notice.is_empty() and not panel.purchase_button.disabled and not game.upgrades.has_upgrade("weapon_magazines") and game.upgrades.points==4,"Actual request deadline enables retry with a truthful timeout notice and no invented unlock")
	var timeout_status: String = panel._selection_status(game.upgrades.node_data(panel.selected_id),game.upgrades.requirement(panel.selected_id))
	panel = await _friends_roundtrip(panel,"timed-out research request")
	check(panel._request_notice==timeout_notice and panel._selection_status(game.upgrades.node_data(panel.selected_id),game.upgrades.requirement(panel.selected_id))==timeout_status,"F7 restores the actual timeout explanation without erasing it on deferred row focus")
	await mouse_move(mouse_point(panel.purchase_button))
	await mouse_button(mouse_point(panel.purchase_button))
	deadline = Time.get_ticks_msec()+3000
	while inbox.size()<2 and Time.get_ticks_msec()<deadline:
		await process_frame
	check(inbox.size()==2 and panel.purchase_button.disabled and str(panel._request_notice).is_empty() and game.upgrades.points==4,"Native explicit retry sends one new real ENet command and replaces the old timeout feedback")
	# Complete the outstanding real request before changing this prepared session
	# to offline. A seeded points/owned state cannot acknowledge pending UI work.
	if inbox.size()==2:
		session.is_host = true
		session._handle_command(str(inbox[1].command),inbox[1].args,2)
		await frames()
		check(game.upgrades.points==1 and game.upgrades.has_upgrade("weapon_magazines") and str(panel._pending_id).is_empty(),"Original authority confirms the actual retry and clears pending research before socket cleanup")
		session._handle_command(str(inbox[0].command),inbox[0].args,2)
		await frames()
		check(game.upgrades.points==1,"An earlier delayed research request cannot debit a successfully retried unlock twice")
	var packet_kinds: Array[String] = []
	for packet: Dictionary in packets:
		packet_kinds.append(str(packet.get("kind","")))
	observations.append({"wire_packet_kinds":packet_kinds,"research_commands_in_retry_phase":inbox.size(),"original_request_timeout_ms":panel.REQUEST_TIMEOUT_MS})
	session.active = false
	session.is_host = false
	session.local_player_id = 1
	session.state = "offline"
	session.match_paused = false
	session.peer_connected = false
	session._authenticated = false
	session.transport = null
	receiver.close()
	sender.close()
	receiver.queue_free()
	sender.queue_free()
	session.set_process(true)
	await frames()
	check(not session.active and not game.microphone.capturing,"Actual command probe releases both sockets and retains a stopped microphone")

func _transactions() -> void:
	view.size = Vector2i(1280,720)
	game.hud._layout_viewport()
	L.set_locale("de",false)
	var panel: Control = game.hud.upgrade_panel
	game.upgrades.changed.connect(func(): transactions+=1)
	seed_research()
	panel._select("precision_lines")
	await frames()
	var before: int = game.upgrades.points
	await key(KEY_ENTER)
	check(game.upgrades.points==before and not game.upgrades.has_upgrade("precision_lines"),"Native Enter on a selected research row only inspects it")
	await mouse_move(mouse_point(panel._button_for("medic_collection")))
	check(game.upgrades.points==before,"Hover never purchases SAN-1 collection")
	panel._select("medic_collection")
	await frames()
	await mouse_button(mouse_point(panel._button_for("medic_collection")))
	check(game.upgrades.points==before and panel.selected_id=="medic_collection","Native mouse research-row click inspects SAN-1 collection without spending")
	await _purchase_selected(panel,"medic_collection",true)
	check(bool(game.get_meta(preload("res://scripts/medic_storage.gd").PROVISIONED,false)),"Actual SAN-1 collection research retains real storage provisioning")
	seed_research()
	await _purchase_selected(panel,"precision_lines")
	var budget: int = game.upgrades.points
	for id: String in CampaignCatalog.MEDIC_UPGRADES:
		await _purchase_selected(panel,id)
	check(game.upgrades.points==budget-14 and game.upgrades.medic_dance_level()==5,"All five native SAN software confirmations conserve the total14 points and unlock five dance stages")
	seed_research(1,4,[])
	panel._select("weapon_capacitor")
	await frames()
	check(panel.purchase_button.disabled and not game.upgrades.has_upgrade("weapon_capacitor"),"Native inspector explains a locked later-wave dependency")
	var locked_points: int = game.upgrades.points
	await mouse_button(mouse_point(panel.purchase_button))
	await key(KEY_ENTER)
	check(game.upgrades.points==locked_points and not game.upgrades.has_upgrade("weapon_capacitor"),"Disabled confirmation blocks native clicks and accepts without spending")
	panel._select("weapon_bolt")
	await frames()
	await mouse_button(mouse_point(panel.prerequisite_button))
	check(panel.selected_id=="weapon_magazines" and panel._button_for("weapon_magazines").has_focus(),"Native prerequisite click selects and reveals the actual required technology")
	seed_research(16,0)
	panel._select("precision_lines")
	await frames()
	check(panel.purchase_button.disabled and panel._selection_status(game.upgrades.node_data("precision_lines"),game.upgrades.requirement("precision_lines")).contains("5"),"Insufficient-points inspector gives the actual missing amount")
	seed_research()
	panel._select("convoy_mg")
	await frames()
	check(panel.purchase_button.disabled,"Vehicle technology remains locked before the first victory")
	game.campaign.active = true
	game.campaign.expedition.vehicle.unlocked = true
	game.campaign.expedition.stage = "preparation"
	panel._refresh()
	await _purchase_selected(panel,"convoy_mg",true)
	game.campaign.expedition.stage = "travel"
	panel._select("convoy_reload")
	await frames()
	check(panel.purchase_button.disabled,"Actual vehicle-management gate disables research while travelling")
	game.campaign.expedition.stage = "preparation"
	panel._refresh()
	await _purchase_selected(panel,"convoy_reload")
	game.campaign.active = false

func _modal_and_shortcuts() -> void:
	var panel: Control = game.hud.upgrade_panel
	seed_research()
	panel._select("precision_lines")
	await frames()
	panel.purchase_button.grab_focus()
	await frames()
	check(str(panel._pending_id).is_empty() and not panel.purchase_button.disabled and panel.purchase_button.has_focus(),"Modal fixture begins without an outstanding network request and with an actual enabled confirmation focus")
	var before: int = game.upgrades.points
	var pointer := mouse_point(panel.purchase_button)
	await key(KEY_F5)
	check(game.hud.has_session_action() and game.hud.restart_dialog.visible,"Native F5 opens the real restart question above research")
	check(not panel.visible and not panel.purchase_button.is_visible_in_tree(),"The real question hides underlying research controls from rendering and focus")
	for code: Key in [KEY_T,KEY_P,KEY_F4,KEY_F1,KEY_SPACE]:
		await key(code)
	check(game.hud.has_session_action() and game.hud.overlay=="upgrades" and game.upgrades.points==before,"Modal question captures shortcut input without replacing research or spending")
	await mouse_button(pointer)
	check(game.upgrades.points==before and not game.upgrades.has_upgrade("precision_lines"),"Native pointer through the question cannot buy research underneath")
	await joy(JOY_BUTTON_B)
	check(not game.hud.has_session_action() and panel.visible and panel.purchase_button.has_focus(),"Native B dismisses the question and restores the precise research focus")
	await key(KEY_F5)
	check(game.hud.has_session_action() and not panel.visible,"A second native restart question preserves the available purchase as its actual opener")
	var price: int = int(game.upgrades.node_data("precision_lines").cost)
	check(game.upgrades.purchase("precision_lines"),"Original authority can complete available research while its restart question is open")
	await frames()
	check(panel.purchase_button.disabled and game.upgrades.points==before-price and game.upgrades.has_upgrade("precision_lines"),"An actual research update disables the saved confirmation and spends its real cost exactly once during the question")
	await joy(JOY_BUTTON_B)
	check(not game.hud.has_session_action() and panel.visible and panel._button_for("precision_lines").has_focus() and focused_inside(panel),"Native B after an authoritative research update returns focus to the selected visible research row when its old confirmation is disabled")
	await key(KEY_T)
	check(game.hud.overlay.is_empty() and not paused,"Native T closes research back to the running offline match")
	await key(KEY_ESCAPE)
	check(game.hud.overlay=="pause" and paused,"Native Escape opens the real paused match")
	await key(KEY_T)
	await frames()
	check(game.hud.overlay=="upgrades" and paused,"Research opened from pause retains the paused match")
	await joy(JOY_BUTTON_B)
	check(game.hud.overlay=="pause" and paused,"Native B returns from research to its actual pause origin")
	await key(KEY_T)
	await key(KEY_ESCAPE)
	check(game.hud.overlay=="pause" and paused,"Native Escape likewise returns research to its pause origin")
	await key(KEY_T)
	await frames()
	panel = game.hud.upgrade_panel
	await mouse_button(mouse_point(panel.close_button))
	check(game.hud.overlay=="pause" and paused,"Native Back click respects the original paused state")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	AudioServer.set_bus_mute(0,true)
	await fixture()
	check(game.hud.overlay=="upgrades" and paused and game.hud.upgrade_panel._button_for("bunker_workshop").has_focus(),"Actual T-panel starts paused with a usable research-row focus")
	await _layouts()
	await _friends_navigation()
	await _same_frame_input()
	await _transactions()
	await _online_command()
	await _modal_and_shortcuts()
	check(not game.audio.persistence_enabled and not game.combat_events.persistence_enabled and not game.campaign.persistence_enabled and not game.network.active and not game.microphone.capturing,"Actual UI checks preserve isolated settings/progress and start no network or microphone")
	await retire()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT+"report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"native_input":true,"rendering":DisplayServer.get_name()!="headless","prepared":"Actual sector07 solo, wave16 TP19 and five existing researches. Real native keyboard, controller, mouse and scrollbar; resolutions960x600/1280x720/1920x1080/2560x1440, DE/EN. Original authoritative UpgradeSystem purchases, staged original vehicle gates, actual restart modal and return origins. Prepared authenticated playing session routes native guest confirmations over actual loopback ENet to the original authority handler; authenticated Internet matchmaking is covered separately by existing multiplayer integrations. Original finite request deadline is advanced to test truthful timeout, F7 persistence and explicit retry. Persistence off, muted isolated profile, no microphone.","layouts":observations},"  "))
	file.close()
	print("TECHNOLOGY PRESENTATION: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
