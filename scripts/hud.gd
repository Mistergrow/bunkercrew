extends CanvasLayer
const L := preload("res://scripts/locale_text.gd")
const InputLabels := preload("res://scripts/input_labels.gd")

var _character_return_overlay := "menu"
var _character_navigation: Dictionary = {}
var _help_return_overlay := "menu"
var help_navigation: Dictionary = {}
var help_panel: Control
var solo_tutorial_panel: Control
var solo_story_navigation: Dictionary = {}
var solo_story_panel: Control
var _solo_story_return_overlay := ""
var _main_menu_navigation: Dictionary = {}
var _context_geometry: Dictionary = {}
var game
var overlay = "menu"
var canvas: Control
var version_badge: Label
var buttons: Array[Button] = []
var sliders: Array[HSlider] = []
var language_buttons: Array[Button] = []
var audio_return_overlay := "menu"
var options_panel: Control
var crafting_panel: Control
var options_tab := 0
var microphone_panel: Control
var upgrades_return_overlay := ""
var _upgrade_navigation: Dictionary = {}
var network_panel: Control
var main_menu_panel: Control
var expedition_panel: Control
var upgrade_panel: Control
var character_panel: CharacterSelectPanel
var scenario_panel: ScenarioSelectPanel
var scenario_options: Dictionary = {}
var scenario_selected := false
var story_selected := false
var personal_panel: PersonalPanel
var combat_overlay: CombatOverlay
var air_raid_panel: Control
var travel_cinematic_panel: Control
var selection_count := 1
var personnel_return_overlay := ""
var personnel_tab := "skills"
var last_overlay = "!"
var _label_refresh := 0.0
const DESIGN_SIZE := Vector2(1440,900)
var display_settings: Node
var support_diagnostics: Node
var restart_dialog: Control
var _restart_was_paused := false
var _session_action := ""
var _session_action_focus: WeakRef
var _session_action_visibility: Dictionary = {}
var pause_buttons: Dictionary = {}
var _pause_return_focus := ""
var chat_panel: Control
var social_panel: Control
var social_return_overlay := "menu"
var friends_dock: Button
var _network_ui_draft: Dictionary = {}
const PHASES = {"build": "BAUPAUSE", "warning": "KONTAKT", "attack": "ANGRIFF", "salvage": "BERGUNG", "victory": "SCHICHT GESICHERT", "defeat": "SIGNAL VERLOREN", "convoy":"KONVOI", "occupation":"BUNKER SICHERN"}

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	canvas = Control.new()
	canvas.size = DESIGN_SIZE
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw)
	add_child(canvas)
	get_viewport().size_changed.connect(_layout_viewport)
	_layout_viewport()
	display_settings = preload("res://scripts/display_settings.gd").new()
	add_child(display_settings)
	support_diagnostics = preload("res://scripts/support_diagnostics.gd").new()
	support_diagnostics.game = game
	add_child(support_diagnostics)
	combat_overlay = preload("res://scripts/combat_overlay.gd").new()
	combat_overlay.game = game
	combat_overlay.hud = self
	canvas.add_child(combat_overlay)
	solo_tutorial_panel = preload("res://scripts/solo_tutorial_panel.gd").new()
	solo_tutorial_panel.game = game
	solo_tutorial_panel.hud = self
	canvas.add_child(solo_tutorial_panel)
	air_raid_panel = preload("res://scripts/air_raid_intro_panel.gd").new()
	air_raid_panel.game = game
	air_raid_panel.hud = self
	canvas.add_child(air_raid_panel)
	travel_cinematic_panel = preload("res://scripts/travel_cinematic_panel.gd").new()
	travel_cinematic_panel.game = game
	travel_cinematic_panel.hud = self
	canvas.add_child(travel_cinematic_panel)
	chat_panel = preload("res://scripts/chat_panel.gd").new()
	chat_panel.game = game
	chat_panel.hud = self
	canvas.add_child(chat_panel)
	friends_dock=Button.new()
	friends_dock.size=Vector2(132,30)
	UiArt.button(friends_dock,12)
	friends_dock.pressed.connect(_open_social)
	canvas.add_child(friends_dock)
	version_badge=preload("res://scripts/version_badge.gd").new()
	version_badge.hud=self
	canvas.add_child(version_badge)
	var localization := get_node_or_null("/root/Localization")
	if localization != null:
		localization.locale_changed.connect(_locale_changed)

func _layout_viewport() -> void:
	# Keep the authored controls together while the world fills wider displays.
	# Canvas-item stretching renders text at the actual output resolution.
	var viewport_size := get_viewport().get_visible_rect().size
	var fit := minf(1.0,minf(viewport_size.x/DESIGN_SIZE.x,viewport_size.y/DESIGN_SIZE.y))
	canvas.scale = Vector2.ONE*fit
	canvas.position = ((viewport_size-DESIGN_SIZE*fit)*0.5).floor()
	canvas.queue_redraw()
	if is_instance_valid(main_menu_panel): main_menu_panel.queue_redraw()

func screen_rect() -> Rect2:
	return Rect2(-canvas.position/canvas.scale,get_viewport().get_visible_rect().size/canvas.scale)

func world_to_ui(world_position: Vector2) -> Vector2:
	return canvas.get_global_transform_with_canvas().affine_inverse()*(get_viewport().get_canvas_transform()*world_position)

func _process(delta: float) -> void:
	_refresh_world_labels(delta)
	_sync_network_overlay()
	if last_overlay != overlay:
		_rebuild_buttons()
		last_overlay = overlay
	_sync_session_action_content()
	var bounds := screen_rect()
	friends_dock.position=Vector2(bounds.end.x-(280 if is_instance_valid(chat_panel) and chat_panel.available() else 150),bounds.position.y+13)
	friends_dock.visible=game.started and overlay.is_empty() and not has_session_action() and not game.travel_cinematic.is_presented()
	friends_dock.focus_mode=Control.FOCUS_NONE if overlay.is_empty() else Control.FOCUS_ALL
	var social_unread := social_pending_count()
	friends_dock.text=L.format("Freunde · %d",social_unread) if social_unread>0 else L.text("Freunde · F7")
	canvas.queue_redraw()

func _input(event: InputEvent) -> void:
	if is_instance_valid(crafting_panel): return
	if is_instance_valid(main_menu_panel) and main_menu_panel.has_modal_subpanel():
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			main_menu_panel.close_modal_subpanel()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed:
			for action: String in ["start","join","audio_settings","restart","help","personnel","achievements","upgrades","friends","weather_toggle"]:
				if InputMap.has_action(action) and event.is_action_pressed(action): get_viewport().set_input_as_handled()
		return
	if is_instance_valid(game.travel_cinematic) and game.travel_cinematic.is_presented(): return
	if bool(game.get_meta("quit_requested", false)):
		get_viewport().set_input_as_handled()
		return
	# The old research controls survive until the next overlay rebuild. Consume
	# intervening input before native buttons or focus navigation can use them.
	if is_instance_valid(upgrade_panel) and overlay != "upgrades":
		get_viewport().set_input_as_handled()
		return
	if has_text_entry(): return
	if is_instance_valid(game.air_raid_intro) and game.air_raid_intro.active: return
	if has_session_action(): return
	if overlay.is_empty() and game.started and not event.is_echo() and not has_text_entry() and _crafting_interaction(event):
		get_viewport().set_input_as_handled()
		return
	if InputMap.has_action("chat") and event.is_action_pressed("chat") and not event.is_echo() and is_instance_valid(chat_panel) and chat_panel.available():
		var focus := get_viewport().gui_get_focus_owner()
		# Enter keeps its native accept/submit meaning inside the lobby.
		if not is_instance_valid(focus) or not focus.is_visible_in_tree():
			chat_panel.open()
			get_viewport().set_input_as_handled()
			return
	# Space is the advertised solo shortcut. Enter / A activates the focused
	# native button; capture Space before a focused Button treats it as accept.
	if overlay=="menu" and event.is_action_pressed("start") and not event.is_echo():
		_open_new_game()
		get_viewport().set_input_as_handled()
	elif overlay=="menu" and event.is_action_pressed("weather_toggle") and not event.is_echo():
		game.weather.set_reduced_effects(not game.weather.reduced_effects)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(crafting_panel): return
	if is_instance_valid(main_menu_panel) and main_menu_panel.has_modal_subpanel(): return
	if is_instance_valid(game.travel_cinematic) and game.travel_cinematic.is_presented(): return
	if bool(game.get_meta("quit_requested", false)):
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(game.air_raid_intro) and game.air_raid_intro.active: return
	if has_session_action(): return
	if event.is_echo(): return
	if is_instance_valid(chat_panel) and chat_panel.composing: return
	if overlay in ["story_journal","story_encounter"]:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("story_journal"):
			_close_solo_story()
		elif event.is_action_pressed("audio_settings"):
			_toggle_audio()
		elif event.is_action_pressed("restart"):
			_restart_match()
		get_viewport().set_input_as_handled()
		return
	if overlay=="friends":
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or (InputMap.has_action("friends") and event.is_action_pressed("friends")):
			_close_social()
		get_viewport().set_input_as_handled()
		return
	if has_text_entry():
		# Escape can still close a panel; every gameplay/menu shortcut waits.
		if not event.is_action_pressed("pause") and not event.is_action_pressed("ui_cancel"): return
	if InputMap.has_action("friends") and event.is_action_pressed("friends"):
		_open_social()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(options_panel) and options_panel.has_method("has_modal_subpanel") and options_panel.has_modal_subpanel():
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("audio_settings"):
			options_panel.close_modal_subpanel()
			get_viewport().set_input_as_handled()
		else:
			for action: String in ["restart","upgrades","personnel","achievements","help","join","skip_build"]:
				if event.is_action_pressed(action):
					get_viewport().set_input_as_handled()
		return
	var viewport = get_viewport()
	if event.is_action_pressed("story_journal") and overlay in ["","pause","victory","defeat","campaign_victory"]:
		_open_solo_story()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_M and game.started and game.expedition.vehicle_unlocked():
		if overlay=="expedition": game.expedition.request("back")
		elif overlay.is_empty(): game.expedition.request("map")
	elif event.is_action_pressed("restart"):
		_restart_match()
	elif event.is_action_pressed("audio_settings"):
		if overlay not in ["upgrades","personal","characters","scenario"]:
			_toggle_audio()
	elif event.is_action_pressed("upgrades"):
		if overlay not in ["audio","microphone","personal","characters","scenario","network"]:
			_toggle_upgrades()
	elif (InputMap.has_action("personnel") and event.is_action_pressed("personnel")) or (InputMap.has_action("achievements") and event.is_action_pressed("achievements")):
		if overlay not in ["audio","microphone","upgrades","characters","scenario","network"]:
			_toggle_personnel(InputMap.has_action("achievements") and event.is_action_pressed("achievements"))
	elif event.is_action_pressed("help"):
		if overlay in ["victory","defeat","audio","microphone","upgrades","personal","characters","scenario","network"]:
			return
		_toggle_help()
	elif event.is_action_pressed("pause") or (event.is_action_pressed("ui_cancel") and overlay in ["pause","audio","microphone","upgrades","help","characters","personal","scenario","network"]):
		if overlay == "expedition":
			game.expedition.request("back")
		elif overlay == "microphone":
			_close_microphone()
		elif overlay == "audio":
			_close_audio()
		elif overlay == "upgrades":
			_close_upgrades()
		elif overlay == "personal":
			_close_personnel()
		elif overlay == "characters":
			_close_character_selection()
		elif overlay == "scenario":
			_close_scenario_selection()
		elif overlay == "network":
			if is_instance_valid(network_panel): network_panel._leave()
		elif overlay == "help":
			_close_help()
		elif game.started and not overlay in ["victory","defeat","campaign_victory"]:
			_toggle_match_pause()
	elif event.is_action_pressed("join"):
		if overlay == "menu":
			_open_scenario_selection(2)
		elif overlay.is_empty() and not _online():
			game.join_coop()
	elif event.is_action_pressed("start") and overlay == "menu":
		_open_new_game()
	elif event.is_action_pressed("skip_build") and overlay.is_empty():
		if _online():
			if game.network.is_host:
				game.network.send_command("skip_build",{})
		else:
			game.rounds.begin_warning()
	else:
		return
	if is_instance_valid(viewport):
		viewport.set_input_as_handled()

func _open_character_selection(count: int) -> void:
	_character_return_overlay="scenario" if overlay=="scenario" else "menu"
	_character_navigation.clear()
	selection_count = clampi(count,1,PartyConfig.MAX_PLAYERS)
	overlay = "characters"
	_apply_overlay_pause()

func _close_character_selection() -> void:
	overlay = "network" if _online() else _character_return_overlay
	_apply_overlay_pause()

func _open_new_game() -> void:
	# The checkpoint is only replaced after the player confirms the crew.
	story_selected=false
	_open_scenario_selection(1)

func _open_scenario_selection(count: int) -> void:
	selection_count=clampi(count,1,PartyConfig.MAX_PLAYERS)
	scenario_selected=true
	overlay="scenario"
	_apply_overlay_pause()

func _open_story_selection(count: int=1) -> void:
	story_selected=true
	if count==1:
		ScenarioCatalog.last_selection.environment="ash_foundry"
	_open_scenario_selection(count)

func _close_scenario_selection() -> void:
	overlay="network" if _online() else "menu"
	scenario_selected=false
	if overlay == "menu":
		story_selected = false
	_apply_overlay_pause()

func _toggle_personnel(show_achievements: bool = false) -> void:
	if overlay == "personal":
		if show_achievements and is_instance_valid(personal_panel):
			personal_panel.select_tab("achievements")
		else:
			_close_personnel()
		return
	personnel_return_overlay = overlay
	personnel_tab = "achievements" if show_achievements else "skills"
	overlay = "personal"
	_apply_overlay_pause()

func _close_personnel() -> void:
	overlay = personnel_return_overlay
	_apply_overlay_pause()

func _toggle_audio() -> void:
	if overlay == "microphone":
		_close_microphone()
	elif overlay == "audio":
		_close_audio()
	else:
		audio_return_overlay = overlay
		overlay = "audio"
		_apply_overlay_pause()

func _open_microphone() -> void:
	overlay = "microphone"
	_apply_overlay_pause()

func _close_microphone() -> void:
	if is_instance_valid(microphone_panel): microphone_panel.close()
	overlay = "audio"
	_apply_overlay_pause()

func _close_audio() -> void:
	overlay = audio_return_overlay
	_apply_overlay_pause()

func _toggle_upgrades() -> void:
	if overlay == "upgrades":
		_close_upgrades()
	else:
		upgrades_return_overlay = overlay
		_upgrade_navigation.clear()
		overlay = "upgrades"
		_apply_overlay_pause()

func _close_upgrades() -> void:
	_upgrade_navigation.clear()
	overlay = upgrades_return_overlay
	_apply_overlay_pause()

func _toggle_help() -> void:
	if overlay=="help":
		_close_help()
		return
	_help_return_overlay = overlay
	overlay = "help"
	_apply_overlay_pause()

func _close_help() -> void:
	overlay = _help_return_overlay
	_apply_overlay_pause()

func _open_solo_story(mode: String = "journal") -> void:
	if not is_instance_valid(game.solo_story) or not game.solo_story.enabled or not game.solo_story.offline_solo(): return
	if mode not in ["journal","encounter"]: return
	if overlay in ["story_journal","story_encounter"]: return
	_solo_story_return_overlay = overlay
	overlay = "story_encounter" if mode=="encounter" else "story_journal"
	_apply_overlay_pause()

func _close_solo_story() -> void:
	overlay = _solo_story_return_overlay
	_apply_overlay_pause()

func _draw() -> void:
	if is_instance_valid(restart_dialog) and restart_dialog.visible: return
	if not overlay.is_empty():
		_overlay()
		return
	_header()
	_draw_aux_status()
	if game.started:
		_inventory()
		_context()
	if game.notice_time > 0 and not game.notice.is_empty():
		# Short lived feedback stays in the left margin, below progress events.
		var lines := UiArt.wrap_text(game.notice,318,14)
		var rect := notice_bounds()
		UiArt.hud_strip(canvas,rect)
		for index in lines.size():
			UiArt.text(canvas,rect.position+Vector2(12,23+index*19),lines[index],14,UiArt.AMBER)

func _panel(rect: Rect2, _color: Color = Color("152129")) -> void:
	UiArt.panel(canvas,rect)

func status_bounds() -> Rect2:
	var screen := screen_rect()
	var height := 48.0
	if _convoy_status_active(): height=70+UiArt.wrap_text(game.expedition.status_text(),484,14).size()*18
	if _convoy_repair_active(): height+=34
	return Rect2(Vector2(screen.get_center().x-254,screen.position.y+12),Vector2(508,height))

func player_bounds(index: int) -> Rect2:
	var screen := screen_rect().grow(-18)
	if _online():
		var local_index: int=game.network.local_player_id-1
		if index==local_index: return Rect2(screen.position.x,screen.end.y-58,326,58)
		var rank: int=index if index<local_index else index-1
		return Rect2(screen.end.x-244,screen.end.y-26-rank*30,244,26)
	var count: int=maxi(1,game.players.size())
	var width := minf(326,(screen.size.x-12*(count-1))/count)
	var left := screen.position.x+(screen.size.x-width)*float(index)/maxi(1,count-1)
	return Rect2(left,screen.end.y-58,width,58)

func _player_aux_top(index: int) -> float:
	var worker = game.players[index]
	var rect := player_bounds(index)
	var top := rect.position.y
	if not worker.inventory.is_empty(): top-=33
	var medical_message := MedicalHud.brief_status(worker)
	if not medical_message.is_empty(): top-=UiArt.wrap_text(medical_message,rect.size.x-20,13).size()*18+10
	return top

func context_bounds(index: int,detail: Dictionary) -> Rect2:
	var height: float=38+(detail.lines.size()+detail.action_lines.size())*19
	if not detail.cycle_hint.is_empty(): height+=19
	return _context_rect(index,height)

func _context_rect(index: int,height: float) -> Rect2:
	var screen := screen_rect().grow(-18)
	var player := player_bounds(index)
	var solo: bool = _online() or game.players.size()==1
	var width := minf(520,screen.size.x-356) if solo else (440.0 if game.players.size()==2 else player.size.x)
	if solo:
		return Rect2(player.end.x+12,screen.end.y-height,width,height)
	var left := minf(player.position.x,screen.end.x-width)
	return Rect2(left,_player_aux_top(index)-height-6,width,height)

func _remember_context_height(index: int,worker: Node,width: float,height: float) -> void:
	_context_geometry[index]={"worker":worker.get_instance_id(),"focus":worker.focus.get_instance_id(),"width":width,"locale":L.current_locale(),"height":height}

func _occupied_context_rect(index: int,worker: Node,width: float) -> Rect2:
	var cached: Dictionary=_context_geometry.get(index,{})
	if cached.get("worker")!=worker.get_instance_id() or cached.get("focus")!=worker.focus.get_instance_id() or cached.get("width")!=width or cached.get("locale")!=L.current_locale():
		var rect:=context_bounds(index,compact_context_details(worker,width-24,14))
		_remember_context_height(index,worker,width,rect.size.y)
		return rect
	# Rendering refreshes the height. Camera queries only place that measured box.
	return _context_rect(index,float(cached.height))

func notice_bounds() -> Rect2:
	var top := screen_rect().position.y+74
	if is_instance_valid(combat_overlay) and (not combat_overlay.boss.is_empty() or not combat_overlay.banners.is_empty()):
		top=combat_overlay.notification_bounds(not combat_overlay.boss.is_empty()).end.y+12
	return Rect2(Vector2(screen_rect().position.x+18,top),Vector2(342,20+UiArt.wrap_text(game.notice,318,14).size()*19))

func occupied_gameplay_bounds(include_tutorial: bool = true) -> Array[Rect2]:
	var result: Array[Rect2]=[status_bounds()]
	var auxiliary:=auxiliary_status_bounds()
	if auxiliary.has_area(): result.append(auxiliary)
	for index in game.players.size():
		var worker=game.players[index]
		var rect:=player_bounds(index)
		if _online() and worker.player_id!=game.network.local_player_id:
			result.append(rect)
			continue
		var top:=_player_aux_top(index)
		result.append(Rect2(rect.position.x,top,rect.size.x,rect.end.y-top))
		if not is_instance_valid(worker.focus) or worker.focus.is_queued_for_deletion(): continue
		if is_instance_valid(worker.mounted_turret) and "vehicle" in worker.mounted_turret: continue
		var solo: bool=_online() or game.players.size()==1
		var width:=minf(520,screen_rect().size.x-392) if solo else (440.0 if game.players.size()==2 else rect.size.x)
		result.append(_occupied_context_rect(index,worker,width))
	if game.notice_time>0 and not game.notice.is_empty(): result.append(notice_bounds())
	for objective in get_tree().get_nodes_in_group("story_objective_panels"):
		if is_instance_valid(objective.director) and objective.director.game==game:
			var bounds: Rect2=objective.objective_bounds()
			if bounds.has_area(): result.append(bounds)
	if include_tutorial and is_instance_valid(solo_tutorial_panel):
		var tutorial_bounds: Rect2 = solo_tutorial_panel.card_bounds()
		if tutorial_bounds.has_area(): result.append(tutorial_bounds)
	return result

func medic_status_visible() -> bool:
	if not is_instance_valid(game.medic): return false
	return game.medic.treating or (is_instance_valid(game.medic.target) and not bool(game.medic.target.get_meta("network_departed",false))) or game.players.any(func(worker): return not bool(worker.get_meta("network_departed",false)) and worker.is_downed())

func _speaking_message() -> String:
	if _online() and "voice" in game and is_instance_valid(game.voice) and game.voice.enabled:
		if game.voice.speaking: return L.text("Du sprichst")
		if game.voice.remote_speaking: return L.text("Partner spricht")
	return ""

func auxiliary_status_bounds() -> Rect2:
	var status:=status_bounds()
	var top:=status.end.y+7
	if is_instance_valid(combat_overlay) and is_instance_valid(combat_overlay.dispatcher) and not combat_overlay.dispatcher.boss_status().is_empty():
		top=combat_overlay.boss_status_bounds().end.y+7
	var rows: int=int(not _speaking_message().is_empty())+int(medic_status_visible())
	return Rect2(status.position.x,top,status.size.x,rows*25)

func _draw_aux_status() -> void:
	var rect:=auxiliary_status_bounds()
	if not rect.has_area(): return
	UiArt.hud_strip(canvas,rect)
	var y:=rect.position.y+18
	var voice_message:=_speaking_message()
	if not voice_message.is_empty():
		UiArt.centered(canvas,Vector2(rect.get_center().x,y),voice_message,13,UiArt.GREEN)
		y+=25
	if medic_status_visible():
		UiArt.centered(canvas,Vector2(rect.get_center().x,y),_short_text(L.text(game.medic.status_label),480,13),13,UiArt.AMBER)

func _header() -> void:
	if _convoy_status_active():
		_convoy_header()
		return
	var rect := status_bounds()
	UiArt.hud_strip(canvas,rect)
	var phase: String = game.rounds.phase if game.started else "build"
	var wave: int = game.rounds.wave if game.started else 1
	var urgent := phase in ["attack","warning"]
	UiArt.text(canvas,rect.position+Vector2(12,20),L.format("WELLE %02d /%02d",[wave,Balance.TOTAL_WAVES]),15)
	UiArt.text(canvas,rect.position+Vector2(12,38),PHASES.get(phase,phase),12,UiArt.RED if urgent else UiArt.MUTED)
	if phase in ["build","warning","salvage"]:
		var remaining: float = game.rounds.time_left if game.started else Balance.BUILD_TIMES[0]
		UiArt.text(canvas,rect.position+Vector2(183,29),L.format("%02d:%02d",[floori(remaining/60.0),int(remaining)%60]),16,UiArt.AMBER)
	else:
		UiArt.text(canvas,rect.position+Vector2(166,29),L.format("%02d FEINDE",get_tree().get_nodes_in_group("enemies").size()),12,UiArt.RED)
	UiArt.divider(canvas,rect.position+Vector2(252,10),rect.position+Vector2(252,38))
	var ratio: float = game.core.hp/game.core.max_hp
	UiArt.text(canvas,rect.position+Vector2(267,20),"BUNKER",12,UiArt.MUTED)
	UiArt.bar(canvas,Rect2(rect.position+Vector2(267,29),Vector2(176,5)),ratio,UiArt.GREEN if ratio>.4 else UiArt.RED)
	UiArt.text(canvas,rect.position+Vector2(452,34),L.format("%d%%",roundi(ratio*100)),13,UiArt.IVORY if ratio>.4 else UiArt.RED)

func _inventory() -> void:
	for index in game.players.size():
		var worker = game.players[index]
		var rect := player_bounds(index)
		var tint: Color = PartyConfig.player_color(worker.player_id)
		if _online() and worker.player_id!=game.network.local_player_id:
			UiArt.hud_strip(canvas,rect)
			UiArt.text(canvas,rect.position+Vector2(7,18),L.format("P%d",worker.player_id),12,tint)
			UiArt.text(canvas,rect.position+Vector2(36,18),_short_text(CharacterCatalog.data(worker.character_id).title,90,12),12,UiArt.MUTED)
			UiArt.bar(canvas,Rect2(rect.position+Vector2(128,9),Vector2(55,4)),worker.hp/worker.max_hp,UiArt.RED if worker.is_downed() else UiArt.GREEN)
			UiArt.text(canvas,rect.position+Vector2(193,18),L.text("FORT") if bool(worker.get_meta("network_departed",false)) else ("KO" if worker.is_downed() else str(ceili(worker.hp))),11,UiArt.RED if worker.is_downed() else UiArt.IVORY)
			continue
		UiArt.hud_strip(canvas,rect)
		UiArt.text(canvas,rect.position+Vector2(10,23),L.format("P%d",worker.player_id),14,tint)
		var health_color: Color = UiArt.RED if worker.hp<35 or worker.is_downed() else UiArt.GREEN
		UiArt.bar(canvas,Rect2(rect.position+Vector2(41,16),Vector2(58,5)),worker.hp/worker.max_hp,health_color)
		var health_text := L.format("%d",ceili(worker.hp))
		if bool(worker.get_meta("network_departed",false)): health_text=L.text("AUSGESCHIEDEN")
		elif worker.is_downed(): health_text="KRITISCH" if worker.medical.state=="critical" else L.format("KO · %ds",ceili(worker.medical.critical_remaining))
		UiArt.text(canvas,rect.position+Vector2(108,23),_short_text(health_text,87,13),13,health_color)
		var weapon = worker.get_node_or_null("WorkerWeapon")
		var gun = worker.mounted_turret
		var name_text: String=weapon.weapon_name() if is_instance_valid(weapon) else ""
		var ammunition := ""
		var reloading := false
		var loose_rounds: int=weapon.open_pack if is_instance_valid(weapon) else 0
		if is_instance_valid(gun):
			name_text=gun.display_name() if gun.has_method("display_name") else ("Flakgeschütz" if gun is FlakTurret else "Feldgeschütz" if gun.get_parent() is FieldDefense else "Dachgeschütz")
			ammunition=L.format("%d / %d +%d",[gun.ammo,gun.ammo_capacity() if gun.has_method("ammo_capacity") else Balance.MAGAZINE,gun.reserve])
			reloading=gun.reload_timer>0
			if "vehicle" in gun and is_instance_valid(gun.vehicle) and not gun.allows_personal_weapon():
				loose_rounds=gun.vehicle.open_pack
				if not gun.vehicle.has_mg:
					ammunition=""
					loose_rounds=0
		elif is_instance_valid(weapon):
			ammunition=L.format("%d / %d +%d",[weapon.current_ammo(),weapon.magazine_size(),weapon.reserve])
			reloading=weapon.reload_timer>0
		var ammo_width := UiArt.FONT.get_string_size(ammunition,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		UiArt.text(canvas,Vector2(rect.end.x-12-ammo_width,rect.position.y+23),ammunition,14,UiArt.AMBER if reloading else UiArt.IVORY)
		UiArt.text(canvas,rect.position+Vector2(10,46),_short_text(name_text,188.0 if reloading or loose_rounds>0 else rect.size.x-20,13),13,UiArt.MUTED)
		if reloading: UiArt.text(canvas,rect.position+Vector2(219,46),"NACHLADEN",11,UiArt.AMBER)
		elif loose_rounds>0: UiArt.text(canvas,rect.position+Vector2(219,46),L.format("+%d Rest",loose_rounds),11,UiArt.MUTED)
		var above := rect.position.y-3
		if not worker.inventory.is_empty():
			UiArt.hud_strip(canvas,Rect2(rect.position.x,above-30,rect.size.x,30))
			UiArt.text(canvas,Vector2(rect.position.x+10,above-10),L.format("%d/%d",[worker.carried_count(),worker.capacity()]),12,UiArt.MUTED)
			var materials: Array=worker.material_kinds()
			var spacing:=minf(39.0,(rect.size.x-58)/maxi(1,materials.size()))
			for slot in materials.size():
				var kind: String=materials[slot]
				var x: float=rect.position.x+49+slot*spacing
				var selected: bool=kind==worker.selected_material()
				UiArt.material(canvas,kind,Vector2(x,above-27),19)
				UiArt.text(canvas,Vector2(x+19,above-9),str(worker.inventory[kind]),12,tint if selected else UiArt.MUTED)
				if selected: canvas.draw_line(Vector2(x,above-3),Vector2(x+29,above-3),tint,1)
			above-=33
		var medical_message := MedicalHud.brief_status(worker)
		if not medical_message.is_empty():
			var lines := UiArt.wrap_text(medical_message,rect.size.x-20,13)
			var height := lines.size()*18+7
			UiArt.hud_strip(canvas,Rect2(rect.position.x,above-height,rect.size.x,height))
			for row in lines.size(): UiArt.text(canvas,Vector2(rect.position.x+10,above-height+19+row*18),lines[row],13,health_color)

func _context() -> void:
	for index in game.players.size():
		var worker = game.players[index]
		if _online() and worker.player_id!=game.network.local_player_id: continue
		var focus = worker.focus
		if is_instance_valid(worker.mounted_turret) and "vehicle" in worker.mounted_turret: continue
		if not is_instance_valid(focus) or focus.is_queued_for_deletion(): continue
		var solo: bool = _online() or game.players.size()==1
		var width := minf(520,screen_rect().size.x-392) if solo else (440.0 if game.players.size()==2 else player_bounds(index).size.x)
		var detail := compact_context_details(worker,width-24,14)
		var rect := context_bounds(index,detail)
		_remember_context_height(index,worker,width,rect.size.y)
		var tint: Color=PartyConfig.player_color(worker.player_id)
		UiArt.hud_strip(canvas,rect)
		canvas.draw_rect(Rect2(rect.position,Vector2(3,rect.size.y)),tint)
		UiArt.text(canvas,rect.position+Vector2(12,23),detail.title,16,tint)
		var y := rect.position.y+45
		for line in detail.lines:
			UiArt.text(canvas,Vector2(rect.position.x+12,y),line,14)
			y+=19
		for line in detail.action_lines:
			UiArt.text(canvas,Vector2(rect.position.x+12,y),line,14,UiArt.AMBER if detail.show_key else UiArt.MUTED)
			y+=19
		if not detail.cycle_hint.is_empty():
			UiArt.text(canvas,Vector2(rect.position.x+12,y),detail.cycle_hint,12,UiArt.MUTED)
		var point: Vector2=focus.interaction_point() if focus.has_method("interaction_point") else focus.global_position
		var at := world_to_ui(point)
		# Only a small open bracket identifies the object in the world.
		if screen_rect().grow(-24).has_point(at):
			for side in [-1,1]:
				canvas.draw_line(at+Vector2(side*12,-7),at+Vector2(side*12,7),tint,1)
				canvas.draw_line(at+Vector2(side*12,-7),at+Vector2(side*8,-7),tint,1)
		if focus.has_method("interaction_progress"):
			UiArt.bar(canvas,Rect2(rect.position+Vector2(12,rect.size.y-3),Vector2(rect.size.x-24,2)),focus.interaction_progress(worker),tint)

func compact_context_details(worker: Node,width: float=348,font_size: int=12) -> Dictionary:
	var detail := context_details(worker)
	var body: String=detail.body
	var paragraphs: PackedStringArray=body.split("\n",false)
	if worker.focus.is_in_group("perimeter_sites"):
		body=" · ".join(paragraphs)
	elif paragraphs.size()>1:
		body=" · ".join(paragraphs.slice(0,2))
	var action: String=L.text(detail.action)
	# The same blocked state must not be repeated as a second instruction.
	if not action.is_empty() and body.contains(action): action=""
	var lines: Array[String]=[]
	if not body.is_empty(): lines=UiArt.wrap_text(body,width,font_size)
	var actions: Array[String]=[]
	if not action.is_empty(): actions=UiArt.wrap_text(action,width,font_size)
	var title: String=L.format("P%d · %s",[worker.player_id,detail.title]) if game.players.size()>1 and not _online() else detail.title
	return {"title":_short_text(title,width,16 if font_size>=14 else font_size),"lines":lines,"action_lines":actions,
		"show_key":detail.show_key,"cycle_hint":_short_text(L.text(detail.cycle_hint),width,12) if detail.multiple else ""}

func _short_text(value: String,width: float,size: int) -> String:
	value=L.text(value)
	if UiArt.FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=width: return value
	while value.length()>1 and UiArt.FONT.get_string_size(value+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,size).x>width: value=value.left(-1)
	return value+"…"

func _refresh_world_labels(delta: float) -> void:
	_label_refresh-=delta
	if _label_refresh>0 or not is_instance_valid(game) or not game.started: return
	_label_refresh=.10
	for node in get_tree().get_nodes_in_group("interactables"):
		if not node is Node2D or not "game" in node or node.game!=game: continue
		if not (node.is_in_group("supplies") or node.is_in_group("stations") or node.is_in_group("field_workshops") or node.is_in_group("core") or node.is_in_group("flak_stations")): continue
		var shown:=UiArt.world_label_visible(node)
		if not node.has_meta("hud_label_visible") or bool(node.get_meta("hud_label_visible"))!=shown:
			node.set_meta("hud_label_visible",shown)
			node.queue_redraw()

func context_details(player: Node) -> Dictionary:
	var focus = player.focus
	var primary_controls: bool = player.player_id==1 or _online()
	var key: String = InputLabels.action(player,"interact")
	var title := "Interaktion"
	if focus.has_method("interaction_title"):
		title = focus.interaction_title()
	elif focus.has_method("display_name") and (focus.is_in_group("convoy_vehicles") or "vehicle" in focus):
		title = focus.display_name()
	elif focus.is_in_group("field_workshops"):
		title = "Feldwerkbank"
	elif focus.is_in_group("turrets"):
		title = "Flakgeschütz" if focus is FlakTurret else "Feldgeschütz" if focus.get_parent() is FieldDefense else "Dachgeschütz"
	elif focus.is_in_group("pickups"):
		title = "Fundstück"
	elif focus.is_in_group("mine_blocks"):
		title = "Rohstoffader"
	elif focus.is_in_group("walls"):
		title = "Bunkerwand"
	elif focus.is_in_group("medical_targets"):
		title = "Erste Hilfe"
	elif focus.is_in_group("scenario_room_sites") or focus.is_in_group("expansion_sites"):
		title = "Raumausbau"
	elif focus.is_in_group("room_linings"):
		title = "Raumverstärkung"
	elif focus.is_in_group("excavation_sites"):
		title = "Tiefenschacht"
	elif focus.is_in_group("dome_sites"):
		title = "Schutzkuppel"
	title = L.text(title)
	var body: String = L.text(focus.prompt(player))
	if body.begins_with(title+"\n"):
		body = body.substr(title.length()+1)
	var action := L.format("%s halten · arbeiten", key)
	var show_key := true
	if focus.has_method("action_hint"):
		action = L.format("%s halten · %s", [key,focus.action_hint(player)])
		if focus is ProductionStation:
			show_key = not focus.working and ((focus.output_amount>0 and player.carried_count()<Balance.capacity_for(player)) or (focus.output_amount==0 and focus.binder>=int(focus.recipe().get("binder",0)) and focus._has_usable_input(player)))
			if not show_key:
				action = "Automatische Herstellung" if focus.working else focus.action_hint(player)
	if focus.is_in_group("perimeter_sites") and focus.action_for(player).is_empty():
		action = ""
		show_key = false
	if focus.has_method("controls_hint"):
		action = focus.controls_hint(player)
		# Storage has two separate actions. Its full controls live in the panel;
		# a single world key would obscure neighbouring labels and imply one action.
		show_key = false
	elif focus.has_method("display_name") and (focus.is_in_group("convoy_vehicles") or "vehicle" in focus):
		if not focus.is_in_group("convoy_vehicles") or focus.journey_state.phase!="repair":
			action=L.format("%s antippen · %s",[key,"verlassen"]) if is_instance_valid(player.mounted_turret) else L.format("%s antippen · einsteigen",key)
	elif focus.is_in_group("pickups"):
		action = L.format("%s antippen · aufnehmen", key)
	elif focus.is_in_group("turrets"):
		action = L.format("%s antippen · %s", [key,"verlassen" if is_instance_valid(player.mounted_turret) else "bedienen"])
	elif focus.is_in_group("medical_targets"):
		action = L.format("%s halten · Erste Hilfe leisten", key)
	elif focus.is_in_group("solo_story_npcs"):
		action = L.format("%s antippen · sprechen",key)
	elif focus.is_in_group("solo_story_finds"):
		action = L.format("%s antippen · lesen",key)
	elif focus is FieldWorkshop:
		action = L.format("%s antippen · Baupläne öffnen",key)
	if focus is ProductionStation:
		if focus.output_amount>0:
			body=L.format("%s abholbereit",Balance.resource_quantity(focus.output_kind(),focus.output_amount))
			if not show_key: action="Inventar voll · Material einlagern"
		elif focus.working:
			body=L.format("Herstellung · noch %.1f s",maxf(0,focus.duration()-focus.production_time))
			action=""
		else:
			body=focus.input_status()+"\n"+focus.recipe_text()
	elif focus is BunkerCore and not focus._outpost():
		show_key=focus.hp>0 and focus.hp<focus.max_hp and (int(player.inventory.get("steel",0))>0 or int(player.inventory.get("scrap",0))>0)
		action=L.format("%s halten · reparieren",key) if show_key else (L.text("1 Stahl oder 1 Schrott mitbringen") if focus.hp>0 and focus.hp<focus.max_hp else "")
		if focus.hp>0 and focus.hp<focus.max_hp:
			body=L.format("%d/%d LP · Reparatur: +%d LP",[ceili(focus.hp),int(focus.max_hp),int(focus.repair_amount())])
	elif focus is ScenarioRoomSite:
		title=L.text(focus.spec().title)
		show_key=false
		action=""
		if focus.built:
			body=L.text("Raum fertig")
		elif not focus.wave_ready():
			body=L.format("Bauplan ab Welle %d",int(focus.spec().wave))
		elif not focus.excavated():
			body=L.text("Erst Erde und Fels abtragen. Dabei erhältst du Rohstoffe.")
		elif focus.curing:
			body=L.format("Beton härtet · noch %.1f s",focus.curing_remaining)
		else:
			var costs: Dictionary=focus.room_cost() if focus.supported else focus.support_cost()
			var supplied: Dictionary=focus.materials if focus.supported else focus.support_materials
			var complete: bool=focus.complete_materials() if focus.supported else focus.support_complete_materials()
			body=L.format("Raumausbau · %s" if focus.supported else "Stützen · %s",focus._material_amounts(supplied,costs))
			var usable := false
			for resource: String in costs:
				if int(supplied.get(resource,0))<int(costs[resource]) and int(player.inventory.get(resource,0))>0: usable=true
			show_key=complete or usable
			if show_key:
				var task: String=("Raum ausbauen" if focus.supported else "Stützen montieren") if complete else "Material einbauen"
				action=L.format("%s halten · %s",[key,task])
			else: action="Benötigtes Material mitbringen"
	elif focus is Supply:
		body=L.format("%s gelagert",Balance.resource_quantity(focus.kind,focus.amount))
		if focus.amount<=0: body=L.text("Kiste leer · kann wieder befüllt werden")
	elif focus.is_in_group("turrets"):
		# Ammunition already has a dedicated, continuously updated HUD readout.
		if is_instance_valid(player.mounted_turret):
			body=""
			action=L.text("Maus zielen · LMB feuern · R laden · E verlassen") if primary_controls else L.text("Pos1/Ende oder Stick zielen · RStrg/RT feuern · Entf/Y laden · Enter/X verlassen") if player.player_id==2 else L.text("Stick zielen · RT feuern · Y laden · X verlassen")
		else:
			body=L.format("%d / %d · Reserve %d",[focus.ammo,focus.ammo_capacity() if focus.has_method("ammo_capacity") else Balance.MAGAZINE,focus.reserve])
			if is_instance_valid(focus.occupant):
				action="Geschütz besetzt"
				show_key=false
		if focus is FlakTurret:
			body=(body+" · " if not body.is_empty() else "")+L.text("WACHE AN" if focus.autonomous else "WACHE AUS")
			action=L.text(action)+" · "+L.format("%s: Wache", "G" if primary_controls else "L3")
	var action_lines: Array[String]=[]
	if not action.is_empty(): action_lines=UiArt.wrap_text(L.text(action),366,10)
	return {"title":title,"body":body,"lines":UiArt.wrap_text(body,366,12),"key":key,"action":action,"action_lines":action_lines,"show_key":show_key,
		"multiple":not is_instance_valid(player.mounted_turret) and game.focus_candidates(player).size()>1,
		"cycle_hint":"F · anderes Ziel" if primary_controls else "Bild ab / RB · anderes Ziel" if player.player_id==2 else "RB · anderes Ziel"}

func _wrap(value: String, limit: int) -> Array[String]:
	return UiArt.wrap_text(L.text(value),limit*UiArt.FONT.get_string_size("M",HORIZONTAL_ALIGNMENT_LEFT,-1,12).x,12)

func _overlay() -> void:
	if overlay in ["menu", "air_raid_intro", "audio", "personal", "upgrades"]: return
	if overlay=="pause":
		_pause_overlay()
		return
	canvas.draw_rect(screen_rect(),Color(0.01,0.015,0.018,0.61))
	if overlay in ["upgrades","characters","personal","scenario","network","microphone","audio","expedition","friends","help","story_journal","story_encounter"]:
		return
	UiArt.panel(canvas,Rect2(288,142,864,632))
	var titles := {"victory":"Schicht geschafft","defeat":"Bunker verloren","campaign_victory":"Alle Orte gesichert"}
	if game.story_mode:
		titles.victory="Das Signal kommt an"
		titles.defeat="Das Signal ist verstummt"
	UiArt.text(canvas,Vector2(337,210),titles.get(overlay,"BUNKERCREW"),27,UiArt.RED if overlay=="defeat" else UiArt.IVORY,UiArt.TITLE_FONT)
	var won: bool = overlay in ["victory","campaign_victory"]
	var location_name: String=ScenarioCatalog.environment(str(game.scenario_options.get("environment","sector07"))).title
	UiArt.text(canvas,Vector2(337,284),L.format("ABSCHLUSSBERICHT / %s",L.text(location_name).to_upper()),12,UiArt.AMBER)
	UiArt.text(canvas,Vector2(337,333),("Strategischer Außenposten gesichert." if CampaignCatalog.site_kind(game.campaign.pending_node)=="outpost" else L.format("%d Wellen überstanden. Der Bunker lebt.", Balance.TOTAL_WAVES)) if won else "Der Bunkerkern wurde zerstört.",18)
	UiArt.divider(canvas,Vector2(337,358),Vector2(1103,358))
	UiArt.text(canvas,Vector2(337,408),"SCHICHTZEIT",13,UiArt.MUTED)
	UiArt.text(canvas,Vector2(771,408),L.format("%02d:%02d", [floori(game.elapsed/60.0),int(game.elapsed)%60]),24,UiArt.AMBER)
	UiArt.text(canvas,Vector2(337,457),"BUNKERKERN",13,UiArt.MUTED)
	UiArt.text(canvas,Vector2(771,457),L.format("%d%%", round(game.core.hp/game.core.max_hp*100)),24,UiArt.GREEN if won else UiArt.RED)
	UiArt.bar(canvas,Rect2(338,486,764,12),game.core.hp/game.core.max_hp,UiArt.GREEN if won else UiArt.RED)
	if overlay=="campaign_victory":
		UiArt.text(canvas,Vector2(337,554),"Das Warnnetz steht. Die Region ist gesichert.",16)
		UiArt.text(canvas,Vector2(337,582),"8 Bunker · 4 Außenposten · Eine gemeinsame Zukunft",13,UiArt.MUTED)
	elif game.campaign.active:
		UiArt.text(canvas,Vector2(337,554),L.format("Strategische Orte gesichert: %d / 12",game.campaign.completed.size()),16)
		UiArt.text(canvas,Vector2(337,582),"Transporter beladen und die nächste Route wählen.",13,UiArt.MUTED)
	elif game.story_mode:
		UiArt.text(canvas,Vector2(337,554),"Mehrere Bunker haben geantwortet." if won else "Die Verbindung ist abgebrochen.",16)
		UiArt.text(canvas,Vector2(337,582),"Das Warnnetz lebt. Die Crew bleibt auf Empfang." if won else "Eine neue Schicht beginnt wieder am Bauplatz.",13,UiArt.MUTED)
	else:
		UiArt.text(canvas,Vector2(337,554),"Verstärkte Wände kaufen Zeit.",16)
		UiArt.text(canvas,Vector2(337,582),"Frischer Beton braucht Schutz.",13,UiArt.MUTED)


func _pause_overlay() -> void:
	var bounds := screen_rect()
	canvas.draw_rect(bounds,Color(0.01,0.015,0.018,0.22))
	SocialUiArt.reading_shade(canvas,bounds,430,980)
	UiArt.text(canvas,Vector2(80,112),"Pause",36,UiArt.IVORY,UiArt.TITLE_FONT)
	UiArt.text(canvas,Vector2(80,146),"Pause für die gesamte Crew." if _online() else "Die Schicht wartet auf dich.",16,UiArt.MUTED)
	var selected := _pause_selected_key()
	if pause_buttons.has(selected):
		var button: Button = pause_buttons[selected]
		canvas.draw_line(Vector2(64,button.position.y+12),Vector2(64,button.position.y+button.size.y-12),UiArt.AMBER,2)
	UiArt.divider(canvas,Vector2(80,601),Vector2(466,601))
	UiArt.text(canvas,Vector2(1040,212),"AKTUELLE SCHICHT",12,UiArt.MUTED)
	var location := "Klassischer Bunker" if game.scenario_options.is_empty() else str(ScenarioCatalog.environment(str(game.scenario_options.get("environment","sector07"))).title)
	var title_lines := UiArt.wrap_text(location,320,26,UiArt.MENU_FONT)
	for index in title_lines.size():
		UiArt.text(canvas,Vector2(1040,253+index*34),title_lines[index],26,UiArt.IVORY,UiArt.MENU_FONT)
	UiArt.divider(canvas,Vector2(1040,322),Vector2(1360,322))
	var rows := [
		["WELLE",L.format("%02d / %02d",[game.rounds.wave,Balance.TOTAL_WAVES])],
		["SCHICHTZEIT",L.format("%02d:%02d",[floori(game.elapsed/60.0),int(game.elapsed)%60])],
		["CREW",str(game.players.size())],
		["BUNKERKERN",L.format("%d%%",round(game.core.hp/game.core.max_hp*100)) if is_instance_valid(game.core) else "—"]]
	for index in rows.size():
		var y := 365+index*54
		UiArt.text(canvas,Vector2(1040,y),rows[index][0],12,UiArt.MUTED)
		var value: String = rows[index][1]
		var width := UiArt.FONT.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
		UiArt.text(canvas,Vector2(1360-width,y),value,20,UiArt.IVORY)
	var lines := UiArt.wrap_text(_pause_action_hint(selected),320,16)
	for index in lines.size(): UiArt.text(canvas,Vector2(1040,651+index*24),lines[index],16,UiArt.MUTED)
	UiArt.text(canvas,Vector2(80,819),"Pfeile / Steuerkreuz: wählen · Enter / A: bestätigen",13,UiArt.MUTED)
	UiArt.text(canvas,Vector2(1040,819),"F3 Effekte · F11 Vollbild",13,UiArt.MUTED)

func _pause_selected_key() -> String:
	var focus := get_viewport().gui_get_focus_owner()
	var focused := "continue_match"
	for key: String in pause_buttons:
		var button: Button = pause_buttons[key]
		if button.disabled: continue
		if button.has_focus(): focused=key
		if button.get_global_rect().has_point(canvas.get_global_mouse_position()): return key
	return focused if is_instance_valid(focus) else "continue_match"

func _pause_action_hint(key: String) -> String:
	match key:
		"options": return "Bild, Kamera, Ton und Takt einstellen."
		"personnel": return "Fähigkeiten, Erfolge und gelernte Tänze."
		"research": return "Forschung und Aufgaben der Crew verwalten."
		"help": return "Steuerung, Herstellung, Ausbau, Rettung und Reisen nachschlagen."
		"story_journal": return "Ortsfunde, gerettete Crewmitglieder und die nächste Verbindung im Warnnetz nachlesen."
		"friends": return "Freunde, Einladungen und Nachrichten."
		"restart": return "Die laufende Mission beginnt erneut am letzten gesicherten Startpunkt." if game.campaign.active else "Der Fortschritt der laufenden Mission geht verloren."
		"main_menu":
			if _online(): return "Du beendest den Online-Raum für die gesamte Crew." if game.network.is_host else "Du verlässt den Online-Raum. Die übrige Crew spielt weiter."
			return "Die laufende Mission endet. Du kannst die Kampagne am letzten gesicherten Zwischenstand fortsetzen." if game.campaign.active else "Der Fortschritt dieser Schicht geht verloren."
	return "Zurück in die laufende Schicht."

func _rebuild_buttons() -> void:
	if last_overlay=="pause":
		_pause_return_focus=""
		if overlay in ["audio","personal","upgrades","help","friends","story_journal","story_encounter"]:
			for key: String in pause_buttons:
				if pause_buttons[key].has_focus(): _pause_return_focus=key
	if is_instance_valid(help_panel):
		help_navigation = help_panel.navigation_state()
		help_panel.queue_free()
		help_panel = null
	if is_instance_valid(solo_story_panel):
		solo_story_navigation = solo_story_panel.navigation_state()
		solo_story_panel.queue_free()
		solo_story_panel = null
	if is_instance_valid(social_panel):
		social_panel.queue_free()
		social_panel=null
	if is_instance_valid(expedition_panel):
		expedition_panel.queue_free()
		expedition_panel=null
	if is_instance_valid(options_panel):
		options_panel.close_modal_subpanel()
		options_panel.queue_free()
		options_panel = null
	if is_instance_valid(microphone_panel):
		microphone_panel.close()
		microphone_panel.queue_free()
		microphone_panel = null
	for button in buttons:
		button.queue_free()
	buttons.clear()
	pause_buttons.clear()
	language_buttons.clear()
	for slider in sliders:
		slider.queue_free()
	sliders.clear()
	if is_instance_valid(main_menu_panel):
		_main_menu_navigation = main_menu_panel.navigation_state()
		main_menu_panel.queue_free()
		main_menu_panel = null
	if is_instance_valid(network_panel):
		_network_ui_draft=network_panel.connection_preferences()
		_network_ui_draft.merge({"session":game.network.get_instance_id(),"generation":int(game.network.get("_generation")),"public_address":network_panel.public_address_field.text,"code":network_panel.code_field.text,"options":network_panel.show_server_options},true)
		network_panel.queue_free()
		network_panel = null
	if is_instance_valid(upgrade_panel):
		if overlay == "friends" and upgrade_panel.has_method("navigation_state"):
			_upgrade_navigation = upgrade_panel.navigation_state()
		upgrade_panel.queue_free()
		upgrade_panel = null
	if is_instance_valid(character_panel):
		_character_navigation = character_panel.navigation_state()
		character_panel.queue_free()
		character_panel = null
	if is_instance_valid(scenario_panel):
		scenario_panel.queue_free()
		scenario_panel=null
	if is_instance_valid(personal_panel):
		personal_panel.queue_free()
		personal_panel = null
	if overlay=="friends":
		social_panel = preload("res://scripts/social_panel.gd").new()
		social_panel.game = game
		social_panel.hud = self
		canvas.add_child(social_panel)
	elif overlay=="menu":
		main_menu_panel = preload("res://scripts/main_menu_panel.gd").new()
		main_menu_panel.game = game
		main_menu_panel.hud = self
		canvas.add_child(main_menu_panel)
		main_menu_panel.restore_navigation(_main_menu_navigation)
	elif overlay=="network":
		network_panel = preload("res://scripts/network_panel.gd").new()
		network_panel.game = game
		network_panel.hud = self
		canvas.add_child(network_panel)
		if _network_ui_draft.get("session")==game.network.get_instance_id() and int(_network_ui_draft.get("generation",-1))==int(game.network.get("_generation")):
			network_panel.restore_connection_preferences(_network_ui_draft)
			network_panel.public_address_field.text=str(_network_ui_draft.get("public_address",""))
			network_panel.code_field.text=str(_network_ui_draft.get("code",""))
			network_panel.show_server_options=bool(_network_ui_draft.get("options",false))
			network_panel._refresh()
	elif overlay=="scenario":
		scenario_panel=ScenarioSelectPanel.new()
		scenario_panel.game=game
		scenario_panel.hud=self
		canvas.add_child(scenario_panel)
	elif overlay=="characters":
		character_panel = preload("res://scripts/character_select_panel.gd").new()
		character_panel.game = game
		character_panel.hud = self
		character_panel.player_count = selection_count
		canvas.add_child(character_panel)
		character_panel.restore_navigation(_character_navigation)
	elif overlay=="personal":
		personal_panel = preload("res://scripts/personal_panel.gd").new()
		personal_panel.game = game
		personal_panel.hud = self
		personal_panel.tab = personnel_tab
		canvas.add_child(personal_panel)
	elif overlay=="microphone":
		microphone_panel = preload("res://scripts/microphone_panel.gd").new()
		microphone_panel.game = game
		microphone_panel.hud = self
		canvas.add_child(microphone_panel)
	elif overlay=="audio":
		options_panel = preload("res://scripts/options_panel.gd").new()
		options_panel.game = game
		options_panel.hud = self
		canvas.add_child(options_panel)
	elif overlay=="expedition":
		expedition_panel=preload("res://scripts/expedition_panel.gd").new()
		expedition_panel.game=game
		expedition_panel.hud=self
		canvas.add_child(expedition_panel)
	elif overlay=="upgrades":
		upgrade_panel = preload("res://scripts/upgrade_panel.gd").new()
		upgrade_panel.game = game
		upgrade_panel.hud = self
		canvas.add_child(upgrade_panel)
		if last_overlay == "friends" and upgrade_panel.has_method("restore_navigation"):
			upgrade_panel.restore_navigation(_upgrade_navigation)
		_upgrade_navigation.clear()
	elif overlay=="pause":
		_pause_button("continue_match","Weiter  ·  Esc",216,_resume_match,26)
		_pause_button("options","Optionen · F4",310,_toggle_audio,20)
		_pause_button("personnel","Personal · P",364,_toggle_personnel,20)
		_pause_button("research","Technik · T",418,_toggle_upgrades,20)
		_pause_button("help","Handbuch · F1",472,_toggle_help,20)
		if is_instance_valid(game.solo_story) and game.solo_story.enabled:
			_pause_button("story_journal","Logbuch · J",526,_open_solo_story,20)
		else:
			_pause_button("friends","Freunde · F7",526,_open_social,20)
		var restart_button := _pause_button("restart","Neu starten · F5",629,_restart_match,18)
		restart_button.disabled = _online() and not game.network.is_host
		restart_button.tooltip_text = L.text("Nur der Gastgeber kann die Schicht neu starten.") if restart_button.disabled else L.text("Neustart beginnt die aktuelle Mission erneut.")
		_pause_button("main_menu","Online-Raum verlassen" if _online() else "Zum Hauptmenü",687,_request_main_menu,18)
		_wire_overlay_focus(pause_buttons.get(_pause_return_focus))
	elif overlay=="help":
		help_panel = preload("res://scripts/help_manual_panel.gd").new()
		help_panel.game = game
		help_panel.hud = self
		canvas.add_child(help_panel)
	elif overlay in ["story_journal","story_encounter"]:
		solo_story_panel = preload("res://scripts/solo_story_panel.gd").new()
		solo_story_panel.game = game
		solo_story_panel.hud = self
		solo_story_panel.mode = "encounter" if overlay=="story_encounter" else "journal"
		canvas.add_child(solo_story_panel)
	elif overlay in ["victory","defeat","campaign_victory"]:
		if not _online() or game.network.is_host:
			var recoverable_crew: bool = overlay=="campaign_victory" and is_instance_valid(game.solo_story) and game.solo_story.has_pending_recruits()
			if (overlay=="victory" or recoverable_crew) and game.expedition.can_manage():
				_button("KONVOI VORBEREITEN",Rect2(337,650,766,61),func():game.expedition.request("prepare"))
			else:
				_button("NEU STARTEN  [F5]",Rect2(337,650,766,61),_restart_match)
		_button("ONLINE-RAUM VERLASSEN" if _online() else "ZUM HAUPTMENÜ",Rect2(337,720,766,36),_request_main_menu)
		if is_instance_valid(game.solo_story) and game.solo_story.enabled:
			_button("Logbuch · J",Rect2(337,600,766,32),_open_solo_story)
		_wire_overlay_focus()
	if is_instance_valid(chat_panel): canvas.move_child(chat_panel,-1)
	if is_instance_valid(restart_dialog): canvas.move_child(restart_dialog,-1)

func _pause_button(key: String, title: String, y: float, callback: Callable, font_size: int) -> Button:
	var button := _button(title,Rect2(80,y,386,49),callback)
	SocialUiArt.button(button,font_size,"",0)
	pause_buttons[key]=button
	return button

func _wire_overlay_focus(preferred: Button = null) -> void:
	var active: Array[Button] = []
	for button: Button in buttons:
		if not button.disabled and button.is_visible_in_tree(): active.append(button)
	for index in active.size():
		var button := active[index]
		button.focus_next = button.get_path_to(active[(index+1)%active.size()])
		button.focus_previous = button.get_path_to(active[posmod(index-1,active.size())])
		button.focus_neighbor_bottom = button.focus_next
		button.focus_neighbor_top = button.focus_previous
	if is_instance_valid(restart_dialog) and restart_dialog.visible: return
	if preferred in active: preferred.grab_focus.call_deferred()
	elif not active.is_empty(): active[0].grab_focus.call_deferred()

func _button(title: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.position = rect.position
	button.size = rect.size
	UiArt.button(button,15 if rect.size.x>250 else 12)
	button.pressed.connect(callback)
	canvas.add_child(button)
	buttons.append(button)
	return button

func _online() -> bool:
	return "network" in game and is_instance_valid(game.network) and game.network.active

func has_session_action() -> bool:
	return (is_instance_valid(restart_dialog) and restart_dialog.visible) or (is_instance_valid(social_panel) and is_instance_valid(social_panel.confirmation) and social_panel.confirmation.visible)

func has_text_entry() -> bool:
	if is_instance_valid(chat_panel) and chat_panel.composing: return true
	var focus := get_viewport().gui_get_focus_owner()
	return is_instance_valid(focus) and focus.is_visible_in_tree() and (focus is LineEdit or focus is TextEdit)

func social_pending_count() -> int:
	var service: Node=game.social if "social" in game and is_instance_valid(game.social) else get_node_or_null("/root/SocialHub")
	if not is_instance_valid(service): return 0
	var pending: int=service.requests.size()
	var now := Time.get_unix_time_from_system()
	for invite: Dictionary in service.invitations:
		if float(invite.get("expires",0))>now: pending+=1
	return mini(99,pending)

func blocks_gameplay_input() -> bool:
	return is_instance_valid(crafting_panel) or (is_instance_valid(game.travel_cinematic) and game.travel_cinematic.blocks_gameplay()) or not overlay.is_empty() or has_session_action() or has_text_entry() or (is_instance_valid(chat_panel) and chat_panel.blocks_input())

func _crafting_interaction(event: InputEvent) -> bool:
	for player in game.players:
		if _online() and player.player_id != game.network.local_player_id: continue
		var pressed: bool = event.is_action_pressed("p1_interact" if _online() else player.action("interact"))
		if player.player_id == 1 or _online():
			pressed = pressed or (preload("res://scripts/network_input.gd").primary_controller_enabled(game) and event.is_action_pressed("primary_pad_interact"))
		if not pressed: continue
		var target: Node = player._chosen_focus()
		if target is FieldWorkshop and target.can_interact(player):
			return open_crafting(player,target)
	return false

func open_crafting(player: Node,bench: Node) -> bool:
	if is_instance_valid(crafting_panel) or not overlay.is_empty() or has_session_action() or has_text_entry() or not game.started or not bench is FieldWorkshop or not bench.can_interact(player) or not game.valid_focus(player,bench): return false
	if _online() and player.player_id != game.network.local_player_id: return false
	preload("res://scripts/network_input.gd").quarantine_menu_inputs(game)
	player._cancel_actions()
	crafting_panel = preload("res://scripts/field_crafting_panel.gd").new()
	crafting_panel.game = game
	crafting_panel.hud = self
	crafting_panel.player = player
	crafting_panel.bench = bench
	canvas.add_child(crafting_panel)
	canvas.move_child(crafting_panel,-1)
	return true

func close_crafting() -> void:
	if not is_instance_valid(crafting_panel): return
	preload("res://scripts/network_input.gd").quarantine_menu_inputs(game)
	crafting_panel.hide()
	crafting_panel.queue_free()
	crafting_panel = null

func _open_social() -> void:
	if has_session_action() or overlay=="air_raid_intro": return
	if is_instance_valid(options_panel) and options_panel.has_method("has_modal_subpanel") and options_panel.has_modal_subpanel(): return
	if overlay=="friends":
		_close_social()
		return
	if is_instance_valid(chat_panel): chat_panel.close()
	social_return_overlay = overlay
	overlay="friends"
	_apply_overlay_pause()

func _close_social() -> void:
	if is_instance_valid(social_panel) and is_instance_valid(social_panel.confirmation) and social_panel.confirmation.visible:
		social_panel._cancel_confirmation()
		return
	overlay=social_return_overlay
	_apply_overlay_pause()

func _open_network() -> void:
	overlay = "network"
	_apply_overlay_pause()

func _apply_overlay_pause() -> void:
	preload("res://scripts/network_input.gd").quarantine_menu_inputs(game)
	if _online() and game.started:
		# A partner may pause or resume while this player inspects a local menu.
		# Restore the current shared state when closing it, not its stale origin.
		if overlay in ["","pause"]:
			overlay = "pause" if game.network.match_paused else ""
		return
	get_tree().paused = not overlay.is_empty()

func _toggle_match_pause() -> void:
	overlay = "" if overlay=="pause" else "pause"
	if _online():
		game.network.pause_match(overlay=="pause")
	else:
		_apply_overlay_pause()

func _resume_match() -> void:
	overlay = ""
	if _online(): game.network.pause_match(false)
	_apply_overlay_pause()

func _restart_match() -> void:
	if not game.started or (_online() and not game.network.is_host): return
	if _online() and (game.network.state!="playing" or game.network._loading): return
	if overlay in ["network","air_raid_intro"]: return
	if is_instance_valid(restart_dialog) and restart_dialog.visible: return
	if overlay not in ["victory","defeat","campaign_victory"]:
		var body := "Die laufende Mission beginnt erneut am letzten gesicherten Startpunkt." if game.campaign.active else "Der Fortschritt der laufenden Mission geht verloren."
		_show_session_action("restart","Schicht neu starten?",body,"Neu starten")
		return
	_perform_restart()

func _show_session_action(action: String,title: String,body: String,accept: String) -> void:
	if is_instance_valid(restart_dialog) and restart_dialog.visible: return
	if not is_instance_valid(restart_dialog):
		restart_dialog = preload("res://scripts/session_action_panel.gd").new()
		restart_dialog.hud = self
		restart_dialog.confirmed.connect(_confirm_session_action)
		restart_dialog.canceled.connect(_cancel_restart)
		canvas.add_child(restart_dialog)
		restart_dialog.visibility_changed.connect(_sync_session_action_content)
	canvas.move_child(restart_dialog,-1)
	_session_action = action
	_restart_was_paused = get_tree().paused
	var focus := get_viewport().gui_get_focus_owner()
	_session_action_focus = weakref(focus) if is_instance_valid(focus) else null
	if not _online(): get_tree().paused = true
	var note := "Einstellungen und gelernte Tänze bleiben erhalten."
	if _online() and action=="restart": note = "Der Neustart gilt für die gesamte Crew. Einstellungen und gelernte Tänze bleiben erhalten."
	restart_dialog.open(title,body,note,accept)
	_sync_session_action_content()

func _sync_session_action_content() -> void:
	var shown: bool = is_instance_valid(restart_dialog) and restart_dialog.visible
	if not shown and _session_action_visibility.is_empty(): return
	if shown:
		# Preserve native selection and visible states while removing controls
		# behind the full-screen question from rendering and focus navigation.
		# Network events may rebuild the underlying screen during this question.
		for instance_id: int in _session_action_visibility.keys():
			if not is_instance_valid(instance_from_id(instance_id)):
				_session_action_visibility.erase(instance_id)
		for child in canvas.get_children():
			if not child is CanvasItem or child.is_queued_for_deletion(): continue
			if child in [restart_dialog,combat_overlay,air_raid_panel,travel_cinematic_panel,chat_panel,friends_dock,version_badge]: continue
			var instance_id: int = child.get_instance_id()
			if not _session_action_visibility.has(instance_id): _session_action_visibility[instance_id] = child.visible
			child.hide()
	else:
		for instance_id: int in _session_action_visibility:
			var child := instance_from_id(instance_id) as CanvasItem
			if is_instance_valid(child) and not child.is_queued_for_deletion(): child.visible = bool(_session_action_visibility[instance_id])
		_session_action_visibility.clear()
	canvas.queue_redraw()

func _confirm_session_action() -> void:
	var action := _session_action
	_session_action = ""
	if is_instance_valid(restart_dialog): restart_dialog.hide()
	if action=="restart": _perform_restart()
	elif action=="menu": _leave_online_match()

func _cancel_restart() -> void:
	if is_instance_valid(restart_dialog): restart_dialog.hide()
	_session_action = ""
	if not _online(): get_tree().paused = _restart_was_paused
	var focus: Object = _session_action_focus.get_ref() if _session_action_focus!=null else null
	_session_action_focus = null
	if is_instance_valid(focus) and focus is Control and focus.is_visible_in_tree() and not (focus is BaseButton and focus.disabled):
		focus.grab_focus.call_deferred()
	elif overlay=="network" and is_instance_valid(network_panel):
		network_panel._focus_initial.call_deferred()
	elif overlay=="upgrades" and is_instance_valid(upgrade_panel):
		upgrade_panel._focus_initial.call_deferred()
	else:
		_wire_overlay_focus(pause_buttons.get("continue_match"))

func _perform_restart() -> void:
	if not game.started: return
	if is_instance_valid(restart_dialog): restart_dialog.hide()
	if not game.restart(): _apply_overlay_pause()

func _request_main_menu() -> void:
	if not game.started: return
	var body := "Der Fortschritt dieser Schicht geht verloren."
	if _online():
		body = "Du beendest den Online-Raum für die gesamte Crew." if game.network.is_host else "Du verlässt den Online-Raum. Die übrige Crew spielt weiter."
	elif game.campaign.active:
		body = "Die laufende Mission endet. Du kannst die Kampagne am letzten gesicherten Zwischenstand fortsetzen."
	elif overlay in ["victory","defeat","campaign_victory"]:
		_leave_online_match()
		return
	_show_session_action("menu","Zum Hauptmenü zurückkehren?",body,"Zum Hauptmenü")

func _sync_network_overlay() -> void:
	if not _online():
		return
	var state: String = game.network.state
	if state=="playing" and game.started and overlay=="network":
		overlay = ""
	elif state=="lobby" and overlay not in ["network","scenario","audio","microphone","friends"]:
		overlay = "network"
	elif state=="reconnecting" and overlay!="network":
		overlay = "network"
	elif state=="error" and overlay not in ["network","friends","audio","microphone"]:
		overlay = "network"

func _leave_online_match() -> void:
	if _online():
		game.network.leave()
	game.return_to_menu()

func _locale_changed(_code: String) -> void:
	# Refresh existing controls in place: retain match state, focus and typed codes.
	for panel in [main_menu_panel,network_panel,character_panel,scenario_panel,personal_panel,upgrade_panel,microphone_panel,options_panel,expedition_panel,restart_dialog,social_panel,chat_panel,help_panel,solo_story_panel]:
		if is_instance_valid(panel) and panel.has_method("refresh_locale"):
			panel.refresh_locale()
	for index in language_buttons.size():
		language_buttons[index].button_pressed = L.current_locale()==["de","en"][index]
	_redraw_locale_tree(canvas)

func _redraw_locale_tree(node: Node) -> void:
	if node is CanvasItem: node.queue_redraw()
	for child in node.get_children(): _redraw_locale_tree(child)

func _convoy_status_active() -> bool:
	return is_instance_valid(game.campaign) and game.campaign.active and is_instance_valid(game.expedition) and (game.expedition.stage in ["travel","stop","occupation"] or game.expedition.outpost_pending() or game.expedition.boarding_active())

func _convoy_repair_active() -> bool:
	if not is_instance_valid(game.expedition) or not is_instance_valid(game.expedition.vehicle): return false
	return game.expedition.vehicle.journey_state.get("phase","")=="repair"

func _convoy_controls() -> String:
	var trip = game.expedition
	if not is_instance_valid(trip.vehicle): return L.text("Umgebung sichern · Karte M")
	var phase: String=str(trip.vehicle.journey_state.get("phase","garage"))
	match phase:
		"boarding": return L.text("Zum Transporter · E einsteigen · M Einsatzkarte")
		"departure","starting": return L.text("Crew bereit · Motor startet")
		"repair": return trip.vehicle.repair_roles_text()
		"reboarding": return L.text("Rad gewechselt · E einsteigen · Weiterfahrt")
	if trip.stage=="occupation": return L.text("Umgebung sichern · Karte M")
	return L.text("A/D fahren · Maus zielen · R laden · E aussteigen")

func _convoy_header() -> void:
	var trip=game.expedition
	var rect:=status_bounds()
	UiArt.hud_strip(canvas,rect)
	var lines:=UiArt.wrap_text(trip.status_text(),484,14)
	for row in lines.size():
		UiArt.text(canvas,rect.position+Vector2(12,23+row*18),lines[row],14,UiArt.AMBER)
	var y:=rect.position.y+24+lines.size()*18
	UiArt.text(canvas,Vector2(rect.position.x+12,y),L.format("Kraftstoff %.1f · Fahrzeug %d · Karte M",[float(game.campaign.expedition.vehicle.fuel),int(game.campaign.expedition.vehicle.hp)]),13,UiArt.MUTED)
	UiArt.bar(canvas,Rect2(rect.position.x+12,y+9,484,4),trip.progress,UiArt.GREEN)
	if _convoy_repair_active():
		var service: Dictionary=trip.vehicle.journey_state
		var gauge:=Rect2(rect.position+Vector2(12,rect.size.y-47),Vector2(350,6))
		if service.repair_step=="tighten":
			canvas.draw_rect(gauge,Color("101817"))
			var task=preload("res://scripts/convoy_journey.gd")
			canvas.draw_rect(Rect2(gauge.position+Vector2(gauge.size.x*task.TIMING_START,0),Vector2(gauge.size.x*(task.TIMING_END-task.TIMING_START),gauge.size.y)),UiArt.GREEN)
			var needle: float=gauge.position.x+gauge.size.x*float(service.repair_cursor)
			canvas.draw_line(Vector2(needle,gauge.position.y-3),Vector2(needle,gauge.end.y+3),UiArt.IVORY,2)
			UiArt.text(canvas,rect.position+Vector2(378,rect.size.y-39),L.format("Bolzen %d/3",int(service.repair_bolts)),12,UiArt.AMBER)
		else:
			UiArt.bar(canvas,gauge,float(service.repair_work),UiArt.GREEN)
			UiArt.text(canvas,rect.position+Vector2(378,rect.size.y-39),L.format("Arbeit %d%%",roundi(float(service.repair_work)*100)),12,UiArt.MUTED)
	UiArt.centered(canvas,Vector2(rect.get_center().x,rect.end.y-10),_convoy_controls(),12,UiArt.MUTED)
