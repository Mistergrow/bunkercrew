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
var _previous_overlay := ""
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
const RESULT_OVERLAYS := ["victory","defeat","campaign_victory"]
## Staged rows of the closing report before its buttons fade in.
const RESULT_STAGES := 8
## Stagger between the report's rows: the plate fills within half a second.
const RESULT_STEP := 0.045
const RESULT_PLATE := Rect2(260,96,920,716)
const RESULT_COLUMN := 310.0
const RESULT_WIDTH := 820.0
## Icon atlas ids for the four report tiles: shift time, wave, kills, core.
const RESULT_ICONS: Array[String] = ["helmet","wall","rifle","core"]
var focus_glide: Control
var _frame_delta := 0.0
var _overlay_started := -10.0
var _notice_text := ""
var _notice_started := -10.0
var _meter_trails: Dictionary = {}
var _pause_marker_y := -1.0
var _phase_shown := ""
var _phase_previous := ""
var _phase_started := -10.0
## Dimming under an in-match panel (see _sync_curtain): the match stays
## visible behind MATCH_SCRIM of the HUD ink while every word of the panel sits
## on its own opaque sheet (SocialUiArt.match_sheet), which rises in and sinks
## out without a fade. Under the bench sheet it is an opaque backing while that
## sheet fades. 0..1, with the panel it sits under and the time a leaving panel
## still needs it.
const MATCH_SCRIM := 0.78
var _curtain: Control
var _curtain_alpha := 0.0
var _curtain_hold := 0.0
var _curtain_panel: WeakRef
var _curtain_on_sheet := false
var _curtain_screen := Rect2()
## Central wave announcement: enter, hold and leave durations in seconds.
const BANNER_ENTER := 0.24
const BANNER_LEAVE := 0.3
const BANNER_HOLD := 1.9
## Display titles use the crisp Signal size (see UiArt.TEXT_SIGNAL).
const SIGNAL_CRISP := UiArt.TEXT_SIGNAL
var _banner: Dictionary = {}
## The banner's own clipped node (see _sync_wave_banner).
var _banner_view: Control
var _banner_phase := ""
var _hazard_strips: Dictionary = {}
const PHASES = {"build": "BAUPAUSE", "warning": "KONTAKT", "attack": "ANGRIFF", "salvage": "BERGUNG", "victory": "SCHICHT GESICHERT", "defeat": "SIGNAL VERLOREN", "convoy":"KONVOI", "occupation":"BUNKER SICHERN"}

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	canvas = Control.new()
	canvas.size = DESIGN_SIZE
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw)
	# Shared style tokens reach every code-built control below the canvas.
	canvas.theme = UiArt.theme()
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
	# Threat read (enemy bars, labels, edge arrows) under the combat messages.
	var threat_overlay: Control = preload("res://scripts/threat_overlay.gd").new()
	threat_overlay.game = game
	threat_overlay.hud = self
	canvas.add_child(threat_overlay)
	canvas.move_child(threat_overlay, combat_overlay.get_index())
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
	focus_glide=preload("res://scripts/ui_focus_glide.gd").new()
	canvas.add_child(focus_glide)
	_banner_view = Control.new()
	_banner_view.name = "WaveBanner"
	_banner_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_view.clip_contents = true
	_banner_view.visible = false
	_banner_view.draw.connect(_draw_wave_banner)
	canvas.add_child(_banner_view)
	# Under the threat read and the combat words, like the HUD strips.
	canvas.move_child(_banner_view,0)
	_curtain = Control.new()
	_curtain.name = "PanelCurtain"
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.visible = false
	_curtain.draw.connect(_draw_curtain)
	canvas.add_child(_curtain)
	var localization := get_node_or_null("/root/Localization")
	if localization != null:
		localization.locale_changed.connect(_locale_changed)

func _layout_viewport() -> void:
	# Keep the authored controls together while the world fills wider displays.
	# Canvas-item stretching renders text at the actual output resolution.
	var viewport_size := get_viewport().get_visible_rect().size
	var fit := minf(1.0,minf(viewport_size.x/DESIGN_SIZE.x,viewport_size.y/DESIGN_SIZE.y))*_hud_boost
	canvas.scale = Vector2.ONE*fit
	canvas.position = ((viewport_size-DESIGN_SIZE*fit)*0.5).floor()
	canvas.queue_redraw()
	if is_instance_valid(main_menu_panel): main_menu_panel.queue_redraw()
	if is_instance_valid(version_badge) and version_badge.is_inside_tree(): version_badge._layout()

## Small windows draw the whole design canvas below 0.8 real pixels per design
## pixel (2/3 at 960x600, where 13 px labels land at about 7 px cap height).
## While the match is in play (no menu, session prompt or bench sheet open)
## the HUD is drawn larger there, up to 1.25x, so its
## smallest copy reaches the 0.8 floor; every HUD element anchors to
## screen_rect()/hud_rect(), which shrink to match, so the layout still fits.
## Menus and fixed-layout panels keep the authored 1440x900 canvas. At
## 1280x720 and above nothing changes.
const HUD_MIN_OUTPUT := 0.8
var _hud_boost := 1.0

func _hud_boost_target() -> float:
	if not is_instance_valid(game) or not game.started or not overlay.is_empty() or has_session_action() or is_instance_valid(crafting_panel): return 1.0
	# Three or four couch players share the compact co-op footer (one level
	# row of fixed-height cards, see COOP_CARD_HEIGHT), which stays low enough
	# to be drawn larger too.
	# A headless run has no real window (its dummy one is 64 px wide); a real
	# window never goes below the project's 960x600 minimum (2/3 scale).
	if DisplayServer.get_name()=="headless": return 1.0
	var stretch := absf(get_viewport().get_final_transform().get_scale().y)
	if stretch < 0.6: return 1.0
	return clampf(HUD_MIN_OUTPUT/stretch,1.0,1.25)

func _sync_hud_boost() -> void:
	var target := _hud_boost_target()
	if is_equal_approx(target,_hud_boost): return
	_hud_boost = target
	_layout_viewport()

func screen_rect() -> Rect2:
	return Rect2(-canvas.position/canvas.scale,get_viewport().get_visible_rect().size/canvas.scale)

## In-play HUD elements (status strip, player panels, context cards, notices,
## captions, the friends dock) anchor to this centred safe area: the visible
## screen, at most 16:9 wide. Up to 16:9 it is the whole screen; on an
## ultrawide window the HUD keeps the 1080p layout around the middle instead of
## the far corners. Full-screen menus, shades and edge threat arrows (which
## point at what lies beyond the real edge) keep using screen_rect().
const HUD_MAX_ASPECT := 16.0/9.0
func hud_rect() -> Rect2:
	var screen := screen_rect()
	var width := minf(screen.size.x,screen.size.y*HUD_MAX_ASPECT)
	return Rect2(Vector2(roundf(screen.get_center().x-width*0.5),screen.position.y),Vector2(width,screen.size.y))

func world_to_ui(world_position: Vector2) -> Vector2:
	return canvas.get_global_transform_with_canvas().affine_inverse()*(get_viewport().get_canvas_transform()*world_position)

func _process(delta: float) -> void:
	_frame_delta = delta*UiMotion.time_scale
	_page_clock += delta
	# The reduced-effects option is the single switch for interface motion.
	UiMotion.reduced = is_instance_valid(game.weather) and game.weather.reduced_effects
	_refresh_world_labels(delta)
	_lift_callsigns()
	_track_wave_banner()
	_sync_wave_banner()
	_sync_network_overlay()
	if last_overlay != overlay:
		_previous_overlay = last_overlay
		_rebuild_buttons()
		last_overlay = overlay
		_overlay_started = UiMotion.now()
		_pause_marker_y = -1.0
		_present_overlay()
	_sync_curtain()
	_sync_session_action_content()
	_sync_hud_boost()
	var bounds := hud_rect()
	friends_dock.position=Vector2(bounds.end.x-(280 if is_instance_valid(chat_panel) and chat_panel.available() else 150),bounds.position.y+13)
	friends_dock.visible=game.started and overlay.is_empty() and not has_session_action() and not game.travel_cinematic.is_presented()
	friends_dock.focus_mode=Control.FOCUS_NONE if overlay.is_empty() else Control.FOCUS_ALL
	var social_unread := social_pending_count()
	friends_dock.text=L.format("Freunde · %d",social_unread) if social_unread>0 else L.text("Freunde · F7")
	canvas.queue_redraw()

func _input(event: InputEvent) -> void:
	if InputLabels.note_event(event,game.started and game.players.size()>1 and not _online()):
		_redraw_locale_tree(canvas)
	# Any deliberate input completes a result sequence; the event still acts.
	if overlay in RESULT_OVERLAYS and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed():
		_finish_overlay_sequence()
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
	# A closing panel's sheet is still sinking out: the match HUD returns with
	# the scene once it has gone, never as dimmed words beside the sheet.
	if _curtain_hold>0.0 and not _curtain_on_sheet: return
	_header()
	_draw_aux_status()
	if game.started:
		_inventory()
		_context()
	if game.notice_time > 0 and not game.notice.is_empty():
		# Short lived feedback stays in the left margin, below progress events.
		# It slides in from the edge and fades out; the occupied rectangle that
		# the camera avoids is the settled one from the first frame.
		if game.notice != _notice_text:
			_notice_text = game.notice
			_notice_started = UiMotion.now()
		var reveal := UiMotion.progress(_notice_started,UiMotion.BASE)
		var opacity := reveal*(clampf(game.notice_time/UiMotion.SLOW,0.0,1.0) if UiMotion.enabled() else 1.0)
		var lines := UiArt.wrap_text(game.notice,318,14)
		var rect := notice_bounds()
		rect.position.x -= UiMotion.slide(UiMotion.SLIDE*2.0,reveal)
		UiArt.hud_strip(canvas,rect,opacity)
		canvas.draw_rect(Rect2(rect.position,Vector2(2,rect.size.y)),Color(UiArt.AMBER,opacity))
		for index in lines.size():
			UiArt.text(canvas,rect.position+Vector2(12,23+index*19),lines[index],14,Color(UiArt.AMBER,opacity))
	else:
		_notice_text = ""

## Wave turns are tracked every frame from the replicated round phase, also
## while a menu is open, so a turn that happened under a panel is never
## announced late when the panel closes.
func _track_wave_banner() -> void:
	if not is_instance_valid(game) or not game.started or not is_instance_valid(game.get("rounds")):
		_banner_phase = ""
		_banner = {}
		return
	if not _banner.is_empty() and UiMotion.now()-float(_banner.started)>float(_banner.hold)+BANNER_LEAVE: _banner = {}
	var phase := str(game.rounds.phase)
	if phase==_banner_phase: return
	var previous := _banner_phase
	_banner_phase = phase
	# The first observed phase (scene start, a guest joining mid-wave) is state,
	# not an event.
	if previous.is_empty(): return
	# A turn that replaces a banner still holding (contact cut short by the
	# attack) swaps the words on the open band instead of collapsing it.
	var showing := not _banner.is_empty() and UiMotion.now()-float(_banner.started)<float(_banner.hold)
	match phase:
		"warning": _banner = {"word":"KONTAKT","accent":UiArt.AMBER,"hazard":true,"hold":BANNER_HOLD}
		"attack": _banner = {"word":"ANGRIFF","accent":UiArt.RED,"hazard":true,"hold":BANNER_HOLD}
		"salvage","build":
			if previous!="attack": return
			_banner = {"word":"ABGEWEHRT","accent":UiArt.GREEN,"hazard":false,"hold":1.4}
		_: return
	_banner.wave = int(game.rounds.wave)
	_banner.started = UiMotion.now()-(BANNER_ENTER if showing else 0.0)

func wave_banner_bounds() -> Rect2:
	return Rect2(Vector2(screen_rect().get_center().x-300.0,screen_rect().position.y+132.0),Vector2(600,74))

## A wave turning is announced once, centred under the status strip: the wave
## number in display type, the phase word, and an alarm band whose hazard caps
## and accent rules carry the urgency (amber contact, red attack, green when the
## wave is repelled). The round controller's alarm sound already plays on host
## and guests; this reads the replicated phase, so every peer sees the same
## moment. The band opens like a shutter from its centre line within
## BANNER_ENTER (its own clipped node, so the words are uncovered with the
## plate, never faded over the scene), the caps close in from its ends and one
## light sweep crosses it; it shuts the same way. With reduced effects it
## appears and leaves without motion.
const BANNER_SWEEP := 0.36
func _sync_wave_banner() -> void:
	var shown := not _banner.is_empty() and overlay.is_empty() and is_instance_valid(game) and bool(game.started)
	var age := UiMotion.now()-float(_banner.started) if shown else 0.0
	if shown and (age<0.0 or age>float(_banner.hold)+BANNER_LEAVE): shown = false
	var full := wave_banner_bounds()
	var height := roundf(full.size.y*_banner_opening(age,float(_banner.get("hold",0.0)))) if shown else 0.0
	_banner_view.visible = height>=2.0
	if not _banner_view.visible: return
	_banner_view.position = Vector2(full.position.x,roundf(full.get_center().y-height*0.5))
	_banner_view.size = Vector2(full.size.x,height)
	_banner_view.queue_redraw()

## The band's rect while it shows (combat words keep clear of it), else empty.
func wave_banner_rect() -> Rect2:
	return wave_banner_bounds() if is_instance_valid(_banner_view) and _banner_view.visible else Rect2()

## The banner's shutter: 0 shut .. 1 open, from its age; 1 with motion off.
func _banner_opening(age: float,hold: float) -> float:
	if not UiMotion.enabled(): return 1.0
	if age<BANNER_ENTER: return UiMotion.ease_out(age/BANNER_ENTER)
	if age>hold: return 1.0-UiMotion.ease_in_out((age-hold)/BANNER_LEAVE)
	return 1.0

func _draw_wave_banner() -> void:
	if _banner.is_empty(): return
	var full := wave_banner_bounds()
	var rect := Rect2(full.position-_banner_view.position,full.size)
	var age := UiMotion.now()-float(_banner.started)
	var moving := UiMotion.enabled()
	var accent: Color = _banner.accent
	_banner_view.draw_rect(rect,Color(.03,.045,.045))
	_banner_view.draw_rect(Rect2(rect.position,Vector2(rect.size.x,2)),accent)
	_banner_view.draw_rect(Rect2(rect.position+Vector2(0,rect.size.y-2),Vector2(rect.size.x,2)),accent)
	if bool(_banner.hazard):
		# Hazard caps slide in from beyond the band's ends while it opens, then
		# march slowly while it holds (motion only); 12 px stripes moving 24 px/s
		# never read as flicker.
		var strip := _hazard_strip(accent)
		var shift := float(int(age*24.0)%12) if moving else 0.0
		var travel := roundf(26.0*(1.0-UiMotion.ease_out(age/BANNER_ENTER))) if moving else 0.0
		for side in [-travel,rect.size.x-26.0+travel]:
			_banner_view.draw_texture_rect_region(strip,Rect2(rect.position+Vector2(side,2),Vector2(26,rect.size.y-4)),Rect2(shift,0,26,rect.size.y-4))
	var title := L.format("WELLE %02d",int(_banner.wave))
	var title_width := UiArt.TITLE_FONT.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,SIGNAL_CRISP).x
	UiArt.text(_banner_view,Vector2(rect.get_center().x-title_width*0.5,rect.position.y+42),title,SIGNAL_CRISP,UiArt.IVORY,UiArt.TITLE_FONT)
	UiArt.centered(_banner_view,Vector2(rect.get_center().x,rect.position.y+64),str(_banner.word),18,accent,UiArt.MENU_FONT)
	# One light sweep crosses the open band, left to right, on whole pixels.
	var sweep := clampf((age-BANNER_ENTER*0.5)/BANNER_SWEEP,0.0,1.0) if moving else 0.0
	if sweep>0.0 and sweep<1.0:
		var x := roundf(lerpf(-44.0,rect.size.x+44.0,UiMotion.ease_in_out(sweep)))
		var top := rect.position.y+2.0
		var bottom := rect.end.y-2.0
		_banner_view.draw_colored_polygon(PackedVector2Array([Vector2(x,top),Vector2(x+24.0,top),Vector2(x+4.0,bottom),Vector2(x-20.0,bottom)]),Color(1.0,.95,.82,.18))

## Diagonal hazard stripes for the banner caps, authored on the design grid:
## 6 px bands at 45 degrees, wide enough to march one 12 px period.
func _hazard_strip(accent: Color) -> ImageTexture:
	var key := accent.to_html()
	if _hazard_strips.has(key): return _hazard_strips[key]
	var pixels := Image.create(38,72,false,Image.FORMAT_RGBA8)
	var ink := Color("10181a")
	for y in 72:
		for x in 38:
			pixels.set_pixel(x,y,accent.darkened(0.12) if int((x+y)/6.0)%2==0 else ink)
	var texture := ImageTexture.create_from_image(pixels)
	_hazard_strips[key] = texture
	return texture

## Travel of a full-screen panel opening (rising into place) and closing
## (sinking while it fades), in design pixels.
const PANEL_RISE := UiMotion.SLIDE*3.0
const PANEL_SINK := UiMotion.SLIDE*1.5
## Bring the freshly built screen in: it rises PANEL_RISE design pixels into place
## while it fades in (eased, UiMotion.SLOW). Controls are focusable and
## clickable from the first frame; only the drawing travels.
func _present_overlay() -> void:
	var covering := _covering_panel()
	if covering != null:
		_place_curtain(covering)
		# The pause screen already dims the match: the scrim continues from
		# there instead of flashing the scene bright for a frame.
		if _previous_overlay=="pause": _curtain_alpha = maxf(_curtain_alpha,.6)
	for panel: Variant in [social_panel,network_panel,scenario_panel,character_panel,personal_panel,microphone_panel,options_panel,expedition_panel,upgrade_panel,help_panel,solo_story_panel]:
		if not is_instance_valid(panel): continue
		# Over the match the sheet never fades: it appears opaque once the
		# scrim has begun to dim the scene and rises into place.
		if panel==covering: UiMotion.rise(panel,Vector2(0,PANEL_RISE),UiMotion.SLOW,_curtain_wait())
		else: UiMotion.enter(panel,Vector2(0,PANEL_RISE),UiMotion.SLOW)
	if overlay=="pause":
		var index := 0
		for key: String in pause_buttons:
			UiMotion.fade_in(pause_buttons[key],UiMotion.BASE,index*UiMotion.STAGE*0.5)
			index += 1
	elif overlay in RESULT_OVERLAYS:
		for index in buttons.size():
			if is_instance_valid(buttons[index]): UiMotion.fade_in(buttons[index],UiMotion.BASE,RESULT_STEP*(RESULT_STAGES+index))

## The panel that covers the running match (full-screen menus over the match,
## the bench sheet); null in the main menu, where every screen brings its own
## landscape.
func _covering_panel() -> Control:
	if not is_instance_valid(game) or not game.started: return null
	for panel: Variant in [social_panel,personal_panel,microphone_panel,options_panel,expedition_panel,upgrade_panel,help_panel,solo_story_panel,crafting_panel]:
		if is_instance_valid(panel) and not (panel as Node).is_queued_for_deletion(): return panel
	return null

## Seconds an entering panel waits: a bench sheet fades in once its backing is
## opaque; a full-screen sheet appears once the scrim has dimmed the scene by
## half, so the match visibly recedes before the sheet covers it.
func _curtain_wait() -> float:
	if not UiMotion.enabled(): return 0.0
	if _curtain_on_sheet: return UiMotion.QUICK*(1.0-_curtain_alpha)
	return UiMotion.QUICK*maxf(0.0,0.5-_curtain_alpha)

## The curtain sits directly under `panel` (above the HUD, the threat read and
## the badge, below the panel and anything raised over it).
func _place_curtain(panel: Control) -> void:
	_curtain_panel = weakref(panel)
	_curtain_on_sheet = panel.has_method("backing_rect")
	var at := panel.get_index()
	canvas.move_child(_curtain,at-1 if _curtain.get_index()<at else at)

## The scrim under a full-screen in-match panel rises over QUICK, holds while
## the panel is open and while a closing panel sinks out (_retire), then clears
## over QUICK; the scene is dimmed, never blacked out. With motion off it
## follows the panel at once. Under the bench sheet it backs the sheet's fade
## (motion only; a settled sheet is opaque itself).
func _sync_curtain() -> void:
	var covering := _covering_panel()
	var wanted := covering != null or _curtain_hold > 0.0
	if _curtain_on_sheet and not UiMotion.enabled(): wanted = false
	var target := 1.0 if wanted else 0.0
	_curtain_hold = maxf(0.0,_curtain_hold-_frame_delta)
	var previous := _curtain_alpha
	_curtain_alpha = move_toward(_curtain_alpha,target,_frame_delta/UiMotion.QUICK) if UiMotion.enabled() else target
	_curtain.visible = _curtain_alpha > 0.0
	# A settled full-screen curtain keeps its recorded drawing; the bench sheet
	# it backs may still be rising into place.
	if _curtain.visible and (_curtain_on_sheet or not is_equal_approx(previous,_curtain_alpha) or _curtain_screen!=screen_rect()):
		_curtain_screen = screen_rect()
		_curtain.queue_redraw()

func _draw_curtain() -> void:
	var ink := Color(.024,.040,.044,_curtain_alpha)
	if _curtain_on_sheet:
		# The bench keeps the match around its sheet: only the sheet is backed,
		# and it closes in one frame, so its backing goes with it.
		var sheet: Variant = _curtain_panel.get_ref() if _curtain_panel != null else null
		if is_instance_valid(sheet) and not (sheet as Node).is_queued_for_deletion(): _curtain.draw_rect(sheet.backing_rect(),ink)
		return
	# The HUD ink with the plates' grain over the whole screen: the match stays
	# visible, dimmed, around the panel's opaque sheet.
	var screen := screen_rect()
	_curtain.draw_rect(screen,Color(ink,MATCH_SCRIM*_curtain_alpha))
	_curtain.draw_texture_rect(UiArt.steel_grain(),screen,true,Color(1,1,1,_curtain_alpha))

func _finish_overlay_sequence() -> void:
	if not UiMotion.running(_overlay_started,UiMotion.COUNT,RESULT_STEP*RESULT_STAGES): return
	_overlay_started = -10.0
	for button: Button in buttons:
		if is_instance_valid(button): UiMotion.fade_in(button,0.0)

## Ratio a draining bar still shows behind its fill. The lost part holds for a
## moment, then drains, so damage reads without any flash. -1 with motion off.
func _meter_trail(key: Variant,ratio: float) -> float:
	if not UiMotion.enabled():
		if not _meter_trails.is_empty(): _meter_trails.clear()
		return -1.0
	if not _meter_trails.has(key):
		if _meter_trails.size()>24: _meter_trails.clear()
		_meter_trails[key] = [ratio,0.0]
	var entry: Array = _meter_trails[key]
	if ratio>=entry[0]:
		entry[0] = ratio
		entry[1] = 0.0
	else:
		entry[1] += _frame_delta
		if entry[1]>0.35: entry[0] = maxf(ratio,entry[0]-_frame_delta*0.55)
	return entry[0]

func _panel(rect: Rect2, _color: Color = Color("152129")) -> void:
	UiArt.panel(canvas,rect)

func status_bounds() -> Rect2:
	var screen := hud_rect()
	var height := 48.0
	if _convoy_status_active(): height=70+UiArt.wrap_text(game.expedition.status_text(),484,14).size()*18
	if _convoy_repair_active(): height+=34
	return Rect2(Vector2(screen.get_center().x-254,screen.position.y+12),Vector2(508,height))

func player_bounds(index: int) -> Rect2:
	var screen := hud_rect().grow(-18)
	if _online():
		var local_index: int=game.network.local_player_id-1
		if index==local_index: return Rect2(screen.position.x,screen.end.y-58,326,58)
		var rank: int=index if index<local_index else index-1
		return Rect2(screen.end.x-244,screen.end.y-26-rank*30,244,26)
	var count: int=maxi(1,game.players.size())
	# Two couch players have the room for a wider card at either edge.
	var width := minf(400.0 if count==2 else 326.0,(screen.size.x-12*(count-1))/count)
	var left := screen.position.x+(screen.size.x-width)*float(index)/maxi(1,count-1)
	var height := COOP_CARD_HEIGHT if count>1 else 58.0
	return Rect2(left,screen.end.y-height,width,height)

## Couch co-op (two to four local players) uses compact cards: one fixed-height
## card per player (health, medical glyphs, ammunition, weapon and carried
## goods on two rows) and, while that player has a target, one fixed-height
## band directly above it (target and its state on one row, the action on the
## next). Every card and every band has the same height on one baseline, so
## the footer is a level row of about 11 % of the screen instead of a ragged
## stack of wrapped sentences. Text that does not fit one row is split at its
## " · " separators into pages that take turns; nothing is dropped.
const COOP_CARD_HEIGHT := 50.0
const COOP_BAND_HEIGHT := 44.0
## While a wave is on (contact, attack, occupation) the target band is one
## row: the target, then icon-led prompts (key glyph + verb); details and the
## "other target" hint wait for the quiet phases.
const COMBAT_BAND_HEIGHT := 28.0
const COOP_BAND_GAP := 2.0
const COOP_PAGE_SECONDS := 2.6
## Medical glyphs on the card, 2x2 design-pixel cells (bleeding, fracture,
## first aid in progress).
const MEDICAL_GLYPHS := {
	"bleeding": ["..#..", ".###.", ".###.", "#####", "#####", ".###."],
	"fracture": ["#.....#", "#######", "#.....#"],
	"aid": [".###.", "#####", ".###."],
}
var _page_clock := 0.0
var _page_cache: Dictionary = {}

func compact_coop() -> bool:
	return is_instance_valid(game) and not _online() and game.players.size()>1

## True while the co-op target bands show their one-row combat form.
func combat_bands() -> bool:
	if not compact_coop(): return false
	var rounds: Variant = game.get("rounds")
	return rounds is Node and is_instance_valid(rounds) and str(rounds.get("phase")) in ["warning","attack","occupation"]

func _band_height() -> float:
	return COMBAT_BAND_HEIGHT if combat_bands() else COOP_BAND_HEIGHT

func _player_aux_top(index: int) -> float:
	var worker = game.players[index]
	var rect := player_bounds(index)
	var top := rect.position.y
	if compact_coop(): return top
	if not worker.inventory.is_empty(): top-=33
	var medical_message := MedicalHud.brief_status(worker)
	if not medical_message.is_empty(): top-=UiArt.wrap_text(medical_message,rect.size.x-20,13).size()*18+10
	return top

func context_bounds(index: int,detail: Dictionary) -> Rect2:
	if compact_coop(): return _context_rect(index,_band_height())
	var height: float=38+(detail.lines.size()+detail.action_lines.size())*19
	if not detail.cycle_hint.is_empty(): height+=19
	return _context_rect(index,height)

func _context_rect(index: int,height: float) -> Rect2:
	var screen := hud_rect().grow(-18)
	var player := player_bounds(index)
	var solo: bool = _online() or game.players.size()==1
	var width := minf(520,screen.size.x-356) if solo else (player.size.x if compact_coop() or game.players.size()!=2 else 440.0)
	if solo:
		return Rect2(player.end.x+12,screen.end.y-height,width,height)
	var left := minf(player.position.x,screen.end.x-width)
	# Shared-screen cards rest on one common line above the tallest player
	# stack instead of stepping up and down with each player's carried goods.
	var base := _player_aux_top(index)
	for other in game.players.size(): base = minf(base,_player_aux_top(other))
	return Rect2(left,base-height-(COOP_BAND_GAP if compact_coop() else 6.0),width,height)

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
	var top := hud_rect().position.y+74
	if is_instance_valid(combat_overlay) and (not combat_overlay.boss.is_empty() or not combat_overlay.banners.is_empty()):
		top=combat_overlay.notification_bounds(not combat_overlay.boss.is_empty()).end.y+12
	return Rect2(Vector2(hud_rect().position.x+18,top),Vector2(342,20+UiArt.wrap_text(game.notice,318,14).size()*19))

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
		var width:=minf(520,hud_rect().size.x-392) if solo else (440.0 if game.players.size()==2 else rect.size.x)
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
	# Wave start and wave clear announce themselves inside the status strip: the
	# phase word slides in and one accent rule runs along the lower edge. The
	# strip keeps its rectangle, so nothing else on screen has to move.
	if phase!=_phase_shown:
		_phase_previous = _phase_shown
		_phase_shown = phase
		_phase_started = UiMotion.now() if not _phase_previous.is_empty() else -10.0
	var phase_reveal := UiMotion.progress(_phase_started,UiMotion.SLOW)
	UiArt.text(canvas,rect.position+Vector2(12,20),L.format("WELLE %02d / %02d",[wave,Balance.TOTAL_WAVES]),15)
	UiArt.text(canvas,rect.position+Vector2(12+UiMotion.slide(UiMotion.SLIDE,phase_reveal),38),PHASES.get(phase,phase),UiArt.TEXT_LABEL,UiMotion.faded(UiArt.RED if urgent else UiArt.MUTED,phase_reveal))
	var announced := phase=="attack" or (phase in ["salvage","build"] and _phase_previous=="attack")
	if announced and UiMotion.running(_phase_started,1.4):
		var sweep := UiMotion.progress(_phase_started,0.45)
		var fade := 1.0-UiMotion.ease_in_out(UiMotion.linear(_phase_started,0.5,0.9))
		canvas.draw_rect(Rect2(rect.position+Vector2(0,rect.size.y-2),Vector2(roundf(rect.size.x*sweep),2)),Color(UiArt.RED if phase=="attack" else UiArt.GREEN,fade))
	if phase in ["build","warning","salvage"]:
		var remaining: float = game.rounds.time_left if game.started else Balance.BUILD_TIMES[0]
		UiArt.text(canvas,rect.position+Vector2(183,29),L.format("%02d:%02d",[floori(remaining/60.0),int(remaining)%60]),16,UiArt.AMBER)
	else:
		# Enemies left in this attack: those in the field plus those the wave
		# still sends (replicated roster counters), so the count never reads 00
		# while an attack is only starting.
		var remaining := get_tree().get_nodes_in_group("enemies").size()
		if game.started and phase=="attack": remaining += maxi(0,int(game.rounds.wave_total)-int(game.rounds.spawned))
		UiArt.text(canvas,rect.position+Vector2(158,29),L.format("%02d FEINDE",remaining),UiArt.TEXT_LABEL,UiArt.RED)
	UiArt.divider(canvas,rect.position+Vector2(252,10),rect.position+Vector2(252,38))
	var ratio: float = game.core.hp/game.core.max_hp
	UiArt.text(canvas,rect.position+Vector2(267,20),"BUNKER",UiArt.TEXT_LABEL,UiArt.MUTED)
	UiArt.meter(canvas,Rect2(rect.position+Vector2(267,27),Vector2(176,8)),ratio,UiArt.GREEN if ratio>.4 else UiArt.RED,_meter_trail("core",ratio),0.0 if ratio>.4 else UiMotion.pulse())
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
			UiArt.meter(canvas,Rect2(rect.position+Vector2(128,9),Vector2(55,6)),worker.hp/worker.max_hp,UiArt.RED if worker.is_downed() or worker.hp<35 else UiArt.GREEN,_meter_trail(worker.get_instance_id(),worker.hp/worker.max_hp))
			UiArt.text(canvas,rect.position+Vector2(193,18),L.text("FORT") if bool(worker.get_meta("network_departed",false)) else ("KO" if worker.is_downed() else str(ceili(worker.hp))),UiArt.TEXT_MICRO,UiArt.RED if worker.is_downed() else UiArt.IVORY)
			continue
		if compact_coop():
			_coop_card(worker,rect,tint)
			continue
		UiArt.hud_strip(canvas,rect)
		UiArt.text(canvas,rect.position+Vector2(10,23),L.format("P%d",worker.player_id),14,tint)
		var health_color: Color = UiArt.RED if worker.hp<35 or worker.is_downed() else UiArt.GREEN
		var departed := bool(worker.get_meta("network_departed",false))
		var health_ratio: float = worker.hp/worker.max_hp
		var health_text := L.format("%d",ceili(worker.hp))
		if departed: health_text=L.text("AUSGESCHIEDEN")
		elif worker.is_downed(): health_text="KRITISCH" if worker.medical.state=="critical" else L.format("KO · %ds",ceili(worker.medical.critical_remaining))
		if departed or worker.is_downed():
			# A downed worker has no health to chart; the state takes the whole row.
			UiArt.text(canvas,rect.position+Vector2(41,23),_short_text(health_text,154,13),13,health_color)
		else:
			# Low health breathes slowly (0.6 Hz) and stays red when motion is off.
			var warning := UiMotion.pulse() if worker.hp<35 else 0.0
			UiArt.meter(canvas,Rect2(rect.position+Vector2(41,13),Vector2(76,9)),health_ratio,health_color,_meter_trail(worker.get_instance_id(),health_ratio),warning)
			if worker.hp<35: canvas.draw_rect(Rect2(rect.position,Vector2(3,rect.size.y)),Color(UiArt.RED,0.45+0.4*warning if UiMotion.enabled() else 0.85))
			UiArt.text(canvas,rect.position+Vector2(126,23),_short_text(health_text,69,13),13,health_color)
		var arms := _weapon_state(worker)
		var name_text: String=arms.name
		var ammunition: String=arms.ammunition
		var reloading: bool=arms.reloading
		var loose_rounds: int=arms.loose_rounds
		var ammo_width := UiArt.FONT.get_string_size(ammunition,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		UiArt.text(canvas,Vector2(rect.end.x-12-ammo_width,rect.position.y+23),ammunition,14,UiArt.AMBER if reloading else UiArt.IVORY)
		if not ammunition.is_empty(): UiArt.icon(canvas,"ammo",Vector2(rect.end.x-12-ammo_width-22,rect.position.y+8),18,Color(1,1,1,0.72) if reloading else Color.WHITE)
		UiArt.text(canvas,rect.position+Vector2(10,46),_short_text(name_text,194.0 if reloading or loose_rounds>0 else rect.size.x-20,13),13,UiArt.MUTED)
		if reloading: UiArt.text(canvas,rect.position+Vector2(212,46),"NACHLADEN",UiArt.TEXT_MICRO,UiArt.AMBER)
		elif loose_rounds>0: UiArt.text(canvas,rect.position+Vector2(212,46),L.format("+%d Rest",loose_rounds),UiArt.TEXT_MICRO,UiArt.MUTED)
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

## Weapon readout of a worker: the mounted gun's when one is manned.
func _weapon_state(worker: Node) -> Dictionary:
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
	return {"name":name_text,"ammunition":ammunition,"reloading":reloading,"loose_rounds":loose_rounds}

## Medical state as glyphs: [glyph id, short text, colour] per condition.
func _medical_marks(worker: Node) -> Array:
	var marks: Array = []
	var medical = worker.medical
	if not is_instance_valid(medical): return marks
	if is_instance_valid(medical.aid_target):
		marks.append(["aid",L.format("%d%%",roundi(medical.aid_progress*100)),UiArt.GREEN])
	if medical.incapacitated(): return marks
	if medical.bleeding>0: marks.append(["bleeding",["","I","II","III"][clampi(int(medical.bleeding),0,3)],UiArt.RED])
	if medical.fractured: marks.append(["fracture","",UiArt.IVORY])
	return marks

func _glyph(rows: Array,at: Vector2,cell: float,color: Color) -> Vector2:
	var width := 0
	for row in rows.size():
		var line := str(rows[row])
		width = maxi(width,line.length())
		for column in line.length():
			if line[column]=="#": canvas.draw_rect(Rect2(at+Vector2(column,row)*cell,Vector2(cell,cell)),color)
	return Vector2(width,rows.size())*cell

## One compact co-op card (see COOP_CARD_HEIGHT): row one carries the player,
## health, medical glyphs and ammunition; row two the weapon (or the reload)
## and the carried goods as material icons with counts.
func _coop_card(worker: Node,rect: Rect2,tint: Color) -> void:
	UiArt.hud_strip(canvas,rect)
	var departed := bool(worker.get_meta("network_departed",false))
	var low: bool=worker.hp<35 and not departed
	var warning := UiMotion.pulse() if low else 0.0
	# The player's colour runs down the card's edge (red while health is low)
	# and continues on the target band above it, so both read as one card.
	canvas.draw_rect(Rect2(rect.position,Vector2(3,rect.size.y)),Color(UiArt.RED,0.45+0.4*warning if UiMotion.enabled() else 0.85) if low or worker.is_downed() else tint)
	var top := rect.position.y
	UiArt.text(canvas,Vector2(rect.position.x+11,top+20),L.format("P%d",worker.player_id),14,tint)
	var health_color: Color = UiArt.RED if worker.hp<35 or worker.is_downed() else UiArt.GREEN
	var health_ratio: float = worker.hp/worker.max_hp
	var arms := _weapon_state(worker)
	var ammunition: String = arms.ammunition
	var ammo_width := UiArt.FONT.get_string_size(ammunition,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
	var ammo_left := rect.end.x-10-ammo_width-(21 if not ammunition.is_empty() else 0)
	var x := rect.position.x+38
	if departed or worker.is_downed():
		var state := L.text("AUSGESCHIEDEN") if departed else (L.text("KRITISCH") if worker.medical.state=="critical" else L.format("KO · %ds",ceili(worker.medical.critical_remaining)))
		state = _short_text(state,maxf(24.0,ammo_left-x-8),13)
		UiArt.text(canvas,Vector2(x,top+20),state,13,health_color)
		x += UiArt.FONT.get_string_size(state,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+10
	else:
		var meter_width := clampf(rect.size.x*.2,44.0,70.0)
		UiArt.meter(canvas,Rect2(Vector2(x,top+11),Vector2(meter_width,9)),health_ratio,health_color,_meter_trail(worker.get_instance_id(),health_ratio),warning)
		x += meter_width+7
		var health_text := str(ceili(worker.hp))
		UiArt.text(canvas,Vector2(x,top+20),health_text,13,health_color)
		x += UiArt.FONT.get_string_size(health_text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+10
	# Medical conditions: a red drop with its stage, a splinted bone, a green
	# cross while giving first aid, instead of a wrapped sentence.
	for mark: Array in _medical_marks(worker):
		var rows: Array = MEDICAL_GLYPHS[mark[0]]
		var size := Vector2(str(rows[0]).length(),rows.size())*2.0
		var label: String = mark[1]
		var label_width := UiArt.FONT.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x if not label.is_empty() else 0.0
		if x+size.x+label_width+4 > ammo_left-6: break
		var at := Vector2(x,top+15-size.y*.5).round()
		canvas.draw_rect(Rect2(at-Vector2.ONE,size+Vector2.ONE*2),Color(UiArt.INK,.9))
		_glyph(rows,at,2.0,mark[2])
		x += size.x+3
		if not label.is_empty():
			UiArt.text(canvas,Vector2(x,top+20),label,12,mark[2])
			x += label_width
		x += 7
	if not ammunition.is_empty():
		UiArt.icon(canvas,"ammo",Vector2(ammo_left,top+6),18,Color(1,1,1,0.72) if arms.reloading else Color.WHITE)
		UiArt.text(canvas,Vector2(rect.end.x-10-ammo_width,top+20),ammunition,14,UiArt.AMBER if arms.reloading else UiArt.IVORY)
	# Row two: carried goods from the right, the weapon in what remains.
	var baseline := top+41
	var cargo_left := rect.end.x-10
	if not worker.inventory.is_empty():
		var materials: Array = worker.material_kinds()
		var counts := L.format("%d/%d",[worker.carried_count(),worker.capacity()])
		var count_width := UiArt.FONT.get_string_size(counts,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
		var room := rect.size.x*.62-count_width-6
		var spacing := minf(34.0,room/maxi(1,materials.size()))
		cargo_left = rect.end.x-10-spacing*materials.size()
		var selected: String = worker.selected_material()
		for slot in materials.size():
			var kind: String = materials[slot]
			var at := Vector2(cargo_left+slot*spacing,top+27)
			UiArt.material(canvas,kind,at,16)
			var chosen := kind==selected
			UiArt.text(canvas,Vector2(at.x+17,baseline),str(worker.inventory[kind]),12,tint if chosen else UiArt.MUTED)
			if chosen: canvas.draw_rect(Rect2(Vector2(at.x,top+rect.size.y-4),Vector2(minf(spacing-4,28),1)),tint)
		cargo_left -= count_width+6
		UiArt.text(canvas,Vector2(cargo_left,baseline),counts,12,UiArt.MUTED)
	var weapon_room := cargo_left-rect.position.x-11-10
	if arms.reloading:
		UiArt.text(canvas,Vector2(rect.position.x+11,baseline),_short_text("NACHLADEN",weapon_room,12),12,UiArt.AMBER)
	else:
		var weapon_text: String = L.text(arms.name)
		if int(arms.loose_rounds)>0: weapon_text += " · "+L.format("+%d Rest",int(arms.loose_rounds))
		UiArt.text(canvas,Vector2(rect.position.x+11,baseline),_short_text(weapon_text,weapon_room,12),12,UiArt.MUTED)

## `value` split at its " · " separators (and line breaks) into rows that fit
## `width`; a single part longer than a row continues on the next row at a
## word break, so nothing is cut off.
func _pages(value: String,width: float,size: int) -> Array[String]:
	var key := "%s|%d|%d" % [value,int(width),size]
	if _page_cache.has(key): return _page_cache[key]
	var pages: Array[String] = []
	var line := ""
	for part: String in value.replace("\n"," · ").split(" · ",false):
		part = part.strip_edges()
		if part.is_empty(): continue
		var candidate := part if line.is_empty() else line+" · "+part
		if UiArt.FONT.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=width:
			line = candidate
			continue
		if not line.is_empty(): pages.append(line)
		var rows := UiArt.wrap_plain_text(part,maxf(8.0,width),size)
		line = rows.pop_back() if not rows.is_empty() else ""
		pages.append_array(rows)
	if not line.is_empty(): pages.append(line)
	if _page_cache.size()>96: _page_cache.clear()
	_page_cache[key] = pages
	return pages

## The page of `pages` shown now; all of them take turns every few seconds.
func _page(pages: Array[String]) -> int:
	if pages.size()<=1: return 0
	return int(_page_clock/COOP_PAGE_SECONDS)%pages.size()

## Small pips at the right end of a paged row: which page is showing.
func _page_pips(right: float,baseline: float,count: int,current: int,color: Color) -> float:
	if count<=1: return 0.0
	var width := count*6.0-3.0
	for index in count:
		canvas.draw_rect(Rect2(Vector2(right-width+index*6.0,baseline-7.0),Vector2(3,3)),Color(color,1.0 if index==current else .3))
	return width+6.0

## The target band of one co-op player (see COOP_BAND_HEIGHT).
func _coop_band(worker: Node,rect: Rect2,tint: Color) -> void:
	var detail := context_details(worker)
	var title: String = L.text(detail.title)
	var body: String = L.text(detail.body)
	var action: String = L.text(detail.action)
	if not action.is_empty() and body.contains(action): action = ""
	UiArt.hud_strip(canvas,rect)
	canvas.draw_rect(Rect2(rect.position,Vector2(3,rect.size.y)),tint)
	var inner := rect.size.x-23
	var left := rect.position.x+12
	if rect.size.y<COOP_BAND_HEIGHT:
		_combat_band_row(detail,rect,tint,title,action)
		return
	var row_one := rect.position.y+18
	title = _short_text(title,inner*(.62 if not body.is_empty() else 1.0),14)
	UiArt.text(canvas,Vector2(left,row_one),title,14,tint)
	if not body.is_empty():
		var start := left+UiArt.FONT.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+9
		var pages := _pages(body,rect.end.x-11-start-14,13)
		if not pages.is_empty():
			var shown := _page(pages)
			_page_pips(rect.end.x-11,row_one,pages.size(),shown,UiArt.MUTED)
			UiArt.text(canvas,Vector2(start,row_one),pages[shown],13,UiArt.IVORY)
	# Row two: the action. With more than one target in reach, the key that
	# changes the target sits at its right end: in full where it fits, else
	# its key alone before a small two-way arrow.
	var row_two := rect.position.y+37
	var right := rect.end.x-11
	if bool(detail.multiple):
		var full: String = L.text(detail.cycle_hint)
		var keys: String = full.split(" · ")[0]
		var action_width := UiArt.FONT.get_string_size(action,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x if not action.is_empty() else 0.0
		var full_width := UiArt.FONT.get_string_size(full,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
		if action_width+30+full_width<=inner:
			UiArt.text(canvas,Vector2(right-full_width,row_two),full,13,UiArt.MUTED)
			right -= full_width+16
		else:
			var keys_width := UiArt.FONT.get_string_size(keys,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
			_swap_arrow(Vector2(right-9,row_two-9),UiArt.MUTED)
			UiArt.text(canvas,Vector2(right-13-keys_width,row_two),keys,12,UiArt.MUTED)
			right -= keys_width+13+12
	if not action.is_empty():
		var pages := _pages(action,right-left-14,13)
		if not pages.is_empty():
			var shown := _page(pages)
			_page_pips(right,row_two,pages.size(),shown,UiArt.MUTED)
			UiArt.text(canvas,Vector2(left,row_two),pages[shown],13,UiArt.AMBER if detail.show_key else UiArt.MUTED)

## The one-row target band of a wave: the target in the player's colour, then
## its prompts right-aligned as key glyphs (keycap, or a face button for pad
## keys) each followed by a short verb. Prompts that do not fit are left out
## from the end (the first one is the main action); a target without key
## prompts shows its action text instead, paged like the quiet band.
func _combat_band_row(detail: Dictionary,rect: Rect2,tint: Color,title: String,action: String) -> void:
	var left := rect.position.x+12
	var right := rect.end.x-10
	var baseline := rect.position.y+19
	var size := 14
	var glyph_size := 13
	var prompts: Array = detail.get("prompts",[])
	var widths: Array[float] = []
	var total := 0.0
	var room := right-left-maxf(48.0,minf(UiArt.FONT.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x,(right-left)*.42))-12.0
	for entry: Array in prompts:
		var width := _key_glyph_width(str(entry[0]),glyph_size)+5.0+UiArt.FONT.get_string_size(L.text(str(entry[1])),HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
		var gap := 0.0 if widths.is_empty() else 14.0
		if total+gap+width>room:
			if widths.is_empty():
				# The main prompt alone: its verb is shortened to the room left.
				widths.append(maxf(48.0,room))
				total = widths[0]
			break
		widths.append(width)
		total += gap+width
	var title_room := right-left-(total+12.0 if total>0.0 else 0.0)
	if widths.is_empty() and not action.is_empty(): title_room = (right-left)*.42
	var shown_title := _short_text(title,maxf(24.0,title_room),size)
	UiArt.text(canvas,Vector2(left,baseline),shown_title,size,tint)
	if widths.is_empty():
		if action.is_empty(): return
		var start := left+UiArt.FONT.get_string_size(shown_title,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x+12.0
		var pages := _pages(action,right-start-14.0,13)
		if pages.is_empty(): return
		var shown := _page(pages)
		_page_pips(right,baseline,pages.size(),shown,UiArt.MUTED)
		UiArt.text(canvas,Vector2(start,baseline),pages[shown],13,UiArt.AMBER if detail.show_key else UiArt.MUTED)
		return
	var x := right-total
	for index in widths.size():
		var entry: Array = prompts[index]
		var glyph := str(entry[0])
		x += _key_glyph(glyph,Vector2(x,baseline),glyph_size)+5.0
		var verb := _short_text(L.text(str(entry[1])),maxf(16.0,widths[index]-_key_glyph_width(glyph,glyph_size)-5.0),size)
		UiArt.text(canvas,Vector2(x,baseline),verb,size,UiArt.AMBER if detail.show_key else UiArt.IVORY)
		x += UiArt.FONT.get_string_size(verb,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x+14.0

const PAD_GLYPHS := ["A","B","X","Y","LB","RB","LT","RT","L3","R3"]

func _key_glyph_width(glyph: String,font_size: int) -> float:
	return UiArt.prompt_width(L.text(glyph),glyph in PAD_GLYPHS,font_size)

## A key glyph on the HUD canvas: a round face button for pad keys, a keycap
## otherwise. Returns its width.
func _key_glyph(glyph: String,at: Vector2,font_size: int) -> float:
	return UiArt.prompt(canvas,at,L.text(glyph),glyph in PAD_GLYPHS,font_size)

## Two stacked pixel arrows (left over right): "change the target".
func _swap_arrow(at: Vector2,color: Color) -> void:
	at = at.round()
	canvas.draw_rect(Rect2(at+Vector2(1,1),Vector2(8,1)),color)
	canvas.draw_rect(Rect2(at+Vector2(0,1),Vector2(1,1)),color)
	canvas.draw_rect(Rect2(at+Vector2(1,0),Vector2(1,3)),color)
	canvas.draw_rect(Rect2(at+Vector2(0,6),Vector2(8,1)),color)
	canvas.draw_rect(Rect2(at+Vector2(8,6),Vector2(1,1)),color)
	canvas.draw_rect(Rect2(at+Vector2(7,5),Vector2(1,3)),color)

func _context() -> void:
	for index in game.players.size():
		var worker = game.players[index]
		if _online() and worker.player_id!=game.network.local_player_id: continue
		var focus = worker.focus
		if is_instance_valid(worker.mounted_turret) and "vehicle" in worker.mounted_turret: continue
		if not is_instance_valid(focus) or focus.is_queued_for_deletion(): continue
		var solo: bool = _online() or game.players.size()==1
		var width := minf(520,hud_rect().size.x-392) if solo else (440.0 if game.players.size()==2 else player_bounds(index).size.x)
		var tint: Color=PartyConfig.player_color(worker.player_id)
		var rect: Rect2
		if compact_coop():
			rect = _context_rect(index,_band_height())
			_remember_context_height(index,worker,width,rect.size.y)
			_coop_band(worker,rect,tint)
		else:
			var detail := compact_context_details(worker,width-24,14)
			rect = context_bounds(index,detail)
			_remember_context_height(index,worker,width,rect.size.y)
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
	# Opening or closing a menu also redraws static machinery: a warning label
	# that may show in play must vanish under the panel (and come back after).
	var covered:=UiArt.menu_covers_world(game)
	for node in get_tree().get_nodes_in_group("interactables"):
		if not node is Node2D or not "game" in node or node.game!=game: continue
		if not (node.is_in_group("supplies") or node.is_in_group("stations") or node.is_in_group("field_workshops") or node.is_in_group("core") or node.is_in_group("flak_stations")): continue
		var shown:=UiArt.world_label_visible(node)
		if not node.has_meta("hud_label_visible") or bool(node.get_meta("hud_label_visible"))!=shown or bool(node.get_meta("hud_menu_covered",false))!=covered:
			node.set_meta("hud_label_visible",shown)
			node.set_meta("hud_menu_covered",covered)
			node.queue_redraw()
	for medic in get_tree().get_nodes_in_group("medics"):
		var callsign: Node=medic.get_node_or_null("Callsign")
		if callsign is CanvasItem: callsign.visible=not covered

## SAN-1's callsign rides above the medic's head. When a worker's P tag (as
## that tag was actually drawn: crouched, climbing, grown at the couch camera
## or stepped aside) would meet it, it lifts on whole world units to rest just
## above every tag it meets, and drops back once the worker moves on. Moving
## the callsign node needs no redraw.
const CALLSIGN_REST := 0.0
const CALLSIGN_GAP := 2.0
func _lift_callsigns() -> void:
	if not is_instance_valid(game) or not game.started: return
	var tags := _crew_tags()
	var shape := _callsign_plate()
	for medic in get_tree().get_nodes_in_group("medics"):
		if not medic is Node2D: continue
		var callsign := medic.get_node_or_null("Callsign") as Node2D
		if callsign == null: continue
		var lift := CALLSIGN_REST
		# The medic owns the sideways step (it rides with its idle step aside).
		var origin: Vector2 = (medic as Node2D).global_position+Vector2(callsign.position.x,0)
		# Two passes: resting above one tag may meet the tag of a second worker.
		for _pass in 2:
			for tag: Rect2 in tags:
				var plate := Rect2(origin+shape.position+Vector2(0,lift),shape.size)
				if plate.grow(CALLSIGN_GAP).intersects(tag): lift = minf(lift,tag.position.y-CALLSIGN_GAP-(origin.y+shape.end.y))
		callsign.position.y = roundf(lift)

## SAN-1's callsign plate around the medic's origin (UiArt.callsign: 10 px
## type with its baseline 54 above the medic, on the crew tags' ink plate).
func _callsign_plate() -> Rect2:
	if _callsign_locale==L.current_locale(): return _callsign_shape
	var width := UiArt.FONT.get_string_size(L.text("SAN-1"),HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
	var ascent := UiArt.FONT.get_ascent(10)
	_callsign_locale = L.current_locale()
	_callsign_shape = Rect2(-roundf(width*0.5)-3.0,-54.0-ascent-1.0,width+6.0,ascent+UiArt.FONT.get_descent(10)+3.0)
	return _callsign_shape
var _callsign_shape := Rect2()
var _callsign_locale := ""

## The crew's P tags as drawn this frame (global world rects).
var _tags: Array[Rect2] = []
var _tags_frame := -1
func _crew_tags() -> Array[Rect2]:
	# Asked by the callsign lift and the combat words in the same frame.
	if _tags_frame==Engine.get_process_frames(): return _tags
	_tags_frame = Engine.get_process_frames()
	var result: Array[Rect2] = []
	_tags = result
	if not is_instance_valid(game): return result
	for worker in game.players:
		if not is_instance_valid(worker): continue
		var visual: Node = worker.get_node_or_null("PixelVisual")
		if visual == null or not visual.has_method("tag_bounds"): continue
		var tag: Rect2 = visual.tag_bounds()
		if tag.has_area(): result.append(tag)
	return result

## HUD-canvas rects of the words written into the world for the crew (P tags,
## SAN-1's callsign). Combat words placed by the HUD keep clear of them.
func world_label_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not is_instance_valid(game) or not game.started: return result
	var world: Array[Rect2] = _crew_tags().duplicate()
	var shape := _callsign_plate()
	for medic in get_tree().get_nodes_in_group("medics"):
		var callsign := medic.get_node_or_null("Callsign") as Node2D
		if medic is Node2D and callsign != null and callsign.is_visible_in_tree():
			world.append(Rect2((medic as Node2D).global_position+callsign.position+shape.position,shape.size))
	for rect in world:
		result.append(Rect2(world_to_ui(rect.position),Vector2.ZERO).expand(world_to_ui(rect.end)))
	return result

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
	# The same action as key glyphs and short verbs (German locale keys) for
	# the one-row target band shown while a wave is on: [glyph, verb] pairs.
	var prompts: Array = [[key,"arbeiten"]]
	var show_key := true
	if focus.has_method("action_hint"):
		action = L.format("%s halten · %s", [key,focus.action_hint(player)])
		prompts = [[key,str(focus.action_hint(player))]]
		if focus is ProductionStation:
			show_key = not focus.working and ((focus.output_amount>0 and player.carried_count()<Balance.capacity_for(player)) or (focus.output_amount==0 and focus.binder>=int(focus.recipe().get("binder",0)) and focus._has_usable_input(player)))
			if not show_key:
				action = "Automatische Herstellung" if focus.working else focus.action_hint(player)
				prompts = []
	if focus.is_in_group("perimeter_sites") and focus.action_for(player).is_empty():
		action = ""
		prompts = []
		show_key = false
	if focus.has_method("controls_hint"):
		action = focus.controls_hint(player)
		prompts = []
		# Storage has two separate actions. Its full controls live in the panel;
		# a single world key would obscure neighbouring labels and imply one action.
		show_key = false
	elif focus.has_method("display_name") and (focus.is_in_group("convoy_vehicles") or "vehicle" in focus):
		if not focus.is_in_group("convoy_vehicles") or focus.journey_state.phase!="repair":
			action=L.format("%s antippen · %s",[key,"verlassen"]) if is_instance_valid(player.mounted_turret) else L.format("%s antippen · einsteigen",key)
			prompts = [[key,"verlassen" if is_instance_valid(player.mounted_turret) else "einsteigen"]]
	elif focus.is_in_group("pickups"):
		action = L.format("%s antippen · aufnehmen", key)
		prompts = [[key,"aufnehmen"]]
	elif focus.is_in_group("turrets"):
		action = L.format("%s antippen · %s", [key,"verlassen" if is_instance_valid(player.mounted_turret) else "bedienen"])
		prompts = [[key,"verlassen" if is_instance_valid(player.mounted_turret) else "bedienen"]]
	elif focus.is_in_group("medical_targets"):
		action = L.format("%s halten · Erste Hilfe leisten", key)
		prompts = [[key,"Erste Hilfe leisten"]]
	elif focus.is_in_group("solo_story_npcs"):
		action = L.format("%s antippen · sprechen",key)
		prompts = [[key,"sprechen"]]
	elif focus.is_in_group("solo_story_finds"):
		action = L.format("%s antippen · lesen",key)
		prompts = [[key,"lesen"]]
	elif focus is FieldWorkshop:
		action = L.format("%s antippen · Baupläne öffnen",key)
		prompts = [[key,"Baupläne öffnen"]]
	if focus is ProductionStation:
		if focus.output_amount>0:
			body=L.format("%s abholbereit",Balance.resource_quantity(focus.output_kind(),focus.output_amount))
			if not show_key:
				action="Inventar voll · Material einlagern"
				prompts = []
		elif focus.working:
			body=L.format("Herstellung · noch %.1f s",maxf(0,focus.duration()-focus.production_time))
			action=""
			prompts = []
		else:
			body=focus.input_status()+"\n"+focus.recipe_text()
	elif focus is BunkerCore and not focus._outpost():
		show_key=focus.hp>0 and focus.hp<focus.max_hp and (int(player.inventory.get("steel",0))>0 or int(player.inventory.get("scrap",0))>0)
		action=L.format("%s halten · reparieren",key) if show_key else (L.text("1 Stahl oder 1 Schrott mitbringen") if focus.hp>0 and focus.hp<focus.max_hp else "")
		prompts = [[key,"reparieren"]] if show_key else []
		if focus.hp>0 and focus.hp<focus.max_hp:
			body=L.format("%d/%d LP · Reparatur: +%d LP",[ceili(focus.hp),int(focus.max_hp),int(focus.repair_amount())])
	elif focus is ScenarioRoomSite:
		title=L.text(focus.spec().title)
		show_key=false
		action=""
		prompts = []
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
				prompts = [[key,task]]
			else: action="Benötigtes Material mitbringen"
	elif focus is Supply:
		body=L.format("%s gelagert",Balance.resource_quantity(focus.kind,focus.amount))
		if focus.amount<=0: body=L.text("Kiste leer · kann wieder befüllt werden")
	elif focus.is_in_group("turrets"):
		# Ammunition already has a dedicated, continuously updated HUD readout.
		if is_instance_valid(player.mounted_turret):
			body=""
			action=L.text("Maus zielen · LMB feuern · R laden · E verlassen") if primary_controls else L.text("Pos1/Ende oder Stick zielen · RStrg/RT feuern · Entf/Y laden · Enter/X verlassen") if player.player_id==2 else L.text("Stick zielen · RT feuern · Y laden · X verlassen")
			prompts = [["LMB","feuern"],["R","laden"],["E","verlassen"]] if primary_controls else [["RStrg/RT","feuern"],["Entf/Y","laden"],["Enter/X","verlassen"]] if player.player_id==2 else [["RT","feuern"],["Y","laden"],["X","verlassen"]]
		else:
			body=L.format("%d / %d · Reserve %d",[focus.ammo,focus.ammo_capacity() if focus.has_method("ammo_capacity") else Balance.MAGAZINE,focus.reserve])
			if is_instance_valid(focus.occupant):
				action="Geschütz besetzt"
				prompts = []
				show_key=false
		if focus is FlakTurret:
			body=(body+" · " if not body.is_empty() else "")+L.text("WACHE AN" if focus.autonomous else "WACHE AUS")
			action=L.text(action)+" · "+L.format("%s: Wache", "G" if primary_controls else "L3")
			prompts.append(["G" if primary_controls else "L3","Wache"])
	var action_lines: Array[String]=[]
	if not action.is_empty(): action_lines=UiArt.wrap_text(L.text(action),366,10)
	return {"title":title,"body":body,"lines":UiArt.wrap_text(body,366,12),"key":key,"action":action,"action_lines":action_lines,"show_key":show_key,"prompts":prompts,
		"multiple":not is_instance_valid(player.mounted_turret) and game.focus_candidates(player).size()>1,
		"cycle_hint":"F · anderes Ziel" if primary_controls else "Bild ab / RB · anderes Ziel" if player.player_id==2 else "RB · anderes Ziel"}

func _wrap(value: String, limit: int) -> Array[String]:
	return UiArt.wrap_text(L.text(value),limit*UiArt.FONT.get_string_size("M",HORIZONTAL_ALIGNMENT_LEFT,-1,12).x,12)

func _overlay() -> void:
	if overlay in ["menu", "air_raid_intro", "audio", "personal", "upgrades"]: return
	if overlay=="pause":
		_pause_overlay()
		return
	if overlay in ["upgrades","characters","personal","scenario","network","microphone","audio","expedition","friends","help","story_journal","story_encounter"]:
		# Over the match the curtain is the one scrim under the panel.
		if _covering_panel()==null: UiArt.scrim(canvas,screen_rect())
		return
	_result_overlay()

## Closing report as a staged sequence: scrim, plate and accent band, a large
## title, then four measured tiles that count up one after another, the core
## meter, the crew who held the shift and the outlook. Everything shown is read
## from replicated state (elapsed, wave, kill counters, core, each worker's
## progression), so host and guests see the same report. Buttons are focusable
## from the first frame and any input completes the sequence at once.
func _result_overlay() -> void:
	var started := _overlay_started
	UiArt.scrim(canvas,screen_rect(),UiMotion.progress(started,UiMotion.SLOW))
	# The report arrives with its plate: the opaque plate and its headline are
	# there from the first frame and rise a few whole pixels into place; the
	# tiles, crew and outlook follow on the plate in quick steps. No word ever
	# shows semi-transparent over the match, and the plate is never empty.
	var plate := RESULT_PLATE
	plate.position.y += UiMotion.slide(UiMotion.SLIDE*1.5,UiMotion.progress(started,UiMotion.QUICK))
	canvas.draw_rect(plate,Color(.098,.133,.118))
	UiArt.plate(canvas,plate,false,1.0)
	var titles := {"victory":"Schicht geschafft","defeat":"Bunker verloren","campaign_victory":"Alle Orte gesichert"}
	if game.story_mode:
		titles.victory="Das Signal kommt an"
		titles.defeat="Das Signal ist verstummt"
	var won: bool = overlay in ["victory","campaign_victory"]
	var accent: Color = UiArt.GREEN if won else UiArt.RED
	var x := RESULT_COLUMN
	var top := plate.position.y
	# The outcome colours the plate head: a stamped band and a soft wash below
	# it, warm green for a held bunker and signal red for a lost one. The band
	# sweeps out from the centre while the headline already stands.
	var band := UiMotion.progress(started,UiMotion.SLOW)
	var band_width := roundf(plate.size.x*band)
	canvas.draw_rect(Rect2(plate.position+Vector2((plate.size.x-band_width)*0.5,0),Vector2(band_width,5)),accent)
	canvas.draw_polygon(PackedVector2Array([plate.position+Vector2(0,5),plate.position+Vector2(plate.size.x,5),plate.position+Vector2(plate.size.x,150),plate.position+Vector2(0,150)]),PackedColorArray([Color(accent,.16*band),Color(accent,.16*band),Color(accent,0),Color(accent,0)]))
	UiArt.text(canvas,Vector2(x,top+86),titles.get(overlay,"BUNKERCREW"),SIGNAL_CRISP,UiArt.RED if overlay=="defeat" else UiArt.IVORY,UiArt.TITLE_FONT)
	canvas.draw_rect(Rect2(x,top+104,roundf(120*band),3),accent)
	var location_name: String=ScenarioCatalog.environment(str(game.scenario_options.get("environment","sector07"))).title
	UiArt.text(canvas,Vector2(x,top+138),L.format("ABSCHLUSSBERICHT / %s",L.text(location_name).to_upper()),UiArt.TEXT_BODY,UiArt.AMBER)
	UiArt.text(canvas,Vector2(x,top+172),("Strategischer Außenposten gesichert." if CampaignCatalog.site_kind(game.campaign.pending_node)=="outpost" else L.format("%d Wellen überstanden. Der Bunker lebt.", Balance.TOTAL_WAVES)) if won else "Der Bunkerkern wurde zerstört.",19,UiArt.IVORY)
	canvas.draw_rect(Rect2(x,top+194,roundf(RESULT_WIDTH*band),1),Color("61706a"))
	# Four measured tiles. Each counts up while its tile lands and every count
	# settles in the same moment, when the last tile has landed, so no tile
	# still runs after the headline. The wave tile states the outcome the
	# headline already gives ("20 Wellen überstanden"): it never counts.
	var counts_end := RESULT_STEP*4+UiMotion.COUNT*0.6
	var core_ratio: float = clampf(game.core.hp/game.core.max_hp,0.0,1.0) if is_instance_valid(game.core) else 0.0
	var kills: int = int(game.stats.get("kills",0)) if game.stats is Dictionary else 0
	var tiles := [
		["SCHICHTZEIT",float(game.elapsed),UiArt.AMBER],
		["WELLE",float(game.rounds.wave),UiArt.IVORY],
		["ABSCHÜSSE",float(kills),UiArt.IVORY],
		["BUNKERKERN",core_ratio,accent]]
	var tile_width := (RESULT_WIDTH-3.0*20.0)/4.0
	var reveal := 0.0
	for index in tiles.size():
		var tile: Array = tiles[index]
		var stage_index := 1+index
		reveal = UiMotion.stage(started,stage_index,UiMotion.BASE,RESULT_STEP)
		if reveal<=0.0: continue
		var rect := Rect2(x+index*(tile_width+20.0),top+216+UiMotion.slide(UiMotion.SLIDE,reveal),tile_width,84)
		canvas.draw_rect(rect,Color(.018,.03,.03,.62*reveal))
		canvas.draw_rect(Rect2(rect.position,Vector2(rect.size.x,2)),Color(tile[2] if index==3 else UiArt.MUTED,.55*reveal))
		# Atlas art at its native 32 px (the core tile uses the crystal, not the
		# carried-pickup crate that UiArt.icon substitutes for "core").
		canvas.draw_texture_rect_region(UiArt.ICONS,Rect2(rect.position+Vector2(12,16),Vector2(32,32)),Rect2(UiArt.ICON_NAMES.find(RESULT_ICONS[index])*32,0,32,32),Color(1,1,1,reveal))
		UiArt.text(canvas,rect.position+Vector2(54,31),str(tile[0]),UiArt.TEXT_NOTE,UiMotion.faded(UiArt.MUTED,reveal))
		var count_start := RESULT_STEP*stage_index
		var shown := float(tile[1]) if index==1 else UiMotion.count(0.0,float(tile[1]),started,counts_end-count_start,count_start)
		var value := ""
		match index:
			0: value = L.format("%02d:%02d",[floori(shown/60.0),int(shown)%60])
			1: value = L.format("%02d / %02d",[roundi(shown),Balance.TOTAL_WAVES])
			2: value = str(roundi(shown))
			_: value = L.format("%d%%",roundi(shown*100))
		UiArt.text(canvas,rect.position+Vector2(54,69),value,28,UiMotion.faded(tile[2],reveal),UiArt.MENU_FONT)
	reveal = UiMotion.stage(started,5,UiMotion.BASE,RESULT_STEP)
	if reveal>0.0: UiArt.meter(canvas,Rect2(x,top+318,RESULT_WIDTH,10),UiMotion.count(0.0,core_ratio,started,counts_end-RESULT_STEP*4,RESULT_STEP*4),accent)
	_result_crew(Vector2(x,top+340),won,UiMotion.stage(started,6,UiMotion.BASE,RESULT_STEP))
	reveal = UiMotion.stage(started,7,UiMotion.BASE,RESULT_STEP)
	var lead := UiMotion.faded(UiArt.IVORY,reveal)
	var note := UiMotion.faded(UiArt.MUTED,reveal)
	var drop := UiMotion.slide(UiMotion.SLIDE,reveal)
	var lines: Array[String] = []
	if overlay=="campaign_victory":
		lines = ["Das Warnnetz steht. Die Region ist gesichert.","8 Bunker · 4 Außenposten · Eine gemeinsame Zukunft"]
	elif game.campaign.active:
		# A lost mission secures nothing and opens no route (fail_mission).
		lines = [L.format("Strategische Orte gesichert: %d / 12",game.campaign.completed.size()),"Transporter beladen und die nächste Route wählen." if won else "Dieser Ort ist nicht gesichert. Neu starten, um ihn zu halten."]
	elif game.story_mode:
		lines = ["Mehrere Bunker haben geantwortet." if won else "Die Verbindung ist abgebrochen.","Das Warnnetz lebt. Die Crew bleibt auf Empfang." if won else "Eine neue Schicht beginnt wieder am Bauplatz."]
	else:
		lines = ["Verstärkte Wände kaufen Zeit.","Frischer Beton braucht Schutz."]
	UiArt.text(canvas,Vector2(x,top+500+drop),lines[0],18,lead)
	UiArt.text(canvas,Vector2(x,top+526+drop),lines[1],UiArt.TEXT_LEAD,note)

## The crew who held (or lost) the shift: each worker's bust portrait (whole
## real pixels per texel, UiArt.pixel_fit via draw_bust) with name and kills
## from their replicated progression. A lost shift dims the portraits.
const RESULT_BUST := 102.0
func _result_crew(at: Vector2,won: bool,reveal: float) -> void:
	if reveal<=0.0 or game.players.is_empty(): return
	UiArt.text(canvas,at+Vector2(0,10),"CREW",UiArt.TEXT_NOTE,UiMotion.faded(UiArt.MUTED,reveal))
	var slot := RESULT_WIDTH/4.0
	var clock := UiMotion.now() if UiMotion.enabled() else 0.0
	# A smaller crew is centred under the tiles instead of leaving the right
	# half of the plate empty.
	var shown := mini(4,game.players.size())
	var lead := roundf((4-shown)*slot*0.5)
	for index in shown:
		var worker = game.players[index]
		if not is_instance_valid(worker): continue
		var origin := at+Vector2(lead+index*slot,20+UiMotion.slide(UiMotion.SLIDE,reveal))
		# The room is as tall as the bust lands, so it hangs under the caption.
		var side := UiArt.pixel_fit(canvas,Vector2(CharacterSelectPanel.BUST_SIZE,CharacterSelectPanel.BUST_SIZE),Vector2(RESULT_BUST-2.0,RESULT_BUST-2.0))*CharacterSelectPanel.BUST_SIZE
		var room := Rect2(origin,Vector2(RESULT_BUST,side+2.0))
		var picture := UiArt.pixel_rect(canvas,Vector2(CharacterSelectPanel.BUST_SIZE,CharacterSelectPanel.BUST_SIZE),Rect2(room.position+Vector2(1,0),room.size-Vector2(2,2)))
		CharacterSelectPanel.draw_bust(canvas,str(worker.character_id),room,clock)
		canvas.draw_rect(Rect2(picture.position+Vector2(-1,picture.size.y-1),Vector2(picture.size.x+2,3)),PartyConfig.player_color(worker.player_id))
		if not won: canvas.draw_rect(picture.grow(1),Color(.03,.02,.02,.5))
		var text_left := picture.end.x+12.0-origin.x
		var title := _short_text(L.text(str(CharacterCatalog.data(worker.character_id).title)).capitalize(),slot-text_left-8.0,18)
		var base := picture.end.y-origin.y
		UiArt.text(canvas,origin+Vector2(text_left,base-52),L.format("P%d",worker.player_id),UiArt.TEXT_NOTE,UiMotion.faded(PartyConfig.player_color(worker.player_id),reveal))
		UiArt.text(canvas,origin+Vector2(text_left,base-28),title,18,UiMotion.faded(UiArt.IVORY,reveal))
		var progression = worker.get("progression")
		if is_instance_valid(progression):
			UiArt.text(canvas,origin+Vector2(text_left,base-5),L.format("%d Abschüsse",int(progression.kills)),UiArt.TEXT_NOTE,UiMotion.faded(UiArt.MUTED,reveal))


func _pause_overlay() -> void:
	var bounds := screen_rect()
	canvas.draw_rect(bounds,Color(0.01,0.015,0.018,0.22))
	SocialUiArt.reading_shade(canvas,bounds,430,980)
	UiArt.text(canvas,Vector2(80,112),"Pause",UiArt.TEXT_SIGNAL,UiArt.IVORY,UiArt.TITLE_FONT)
	UiArt.text(canvas,Vector2(80,146),"Pause für die gesamte Crew." if _online() else "Die Schicht wartet auf dich.",16,UiArt.MUTED)
	var selected := _pause_selected_key()
	if pause_buttons.has(selected):
		var button: Button = pause_buttons[selected]
		# The marker settles onto the selected row instead of jumping to it.
		_pause_marker_y = button.position.y if _pause_marker_y<0.0 else UiMotion.approach(_pause_marker_y,button.position.y,_frame_delta/UiMotion.time_scale)
		canvas.draw_line(Vector2(64,_pause_marker_y+12),Vector2(64,_pause_marker_y+button.size.y-12),UiArt.AMBER,2)
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
	UiArt.hints(canvas,Vector2(80,819),InputLabels.navigation_hints(),InputLabels.pad_active,UiArt.TEXT_BODY)
	UiArt.text(canvas,Vector2(1040,819),"F3 Effekte · F11 Vollbild",UiArt.TEXT_BODY,UiArt.MUTED)

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
		_retire(help_panel)
		help_panel = null
	if is_instance_valid(solo_story_panel):
		solo_story_navigation = solo_story_panel.navigation_state()
		_retire(solo_story_panel)
		solo_story_panel = null
	if is_instance_valid(social_panel):
		_retire(social_panel)
		social_panel=null
	if is_instance_valid(expedition_panel):
		_retire(expedition_panel)
		expedition_panel=null
	if is_instance_valid(options_panel):
		options_panel.close_modal_subpanel()
		_retire(options_panel)
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
		_retire(upgrade_panel)
		upgrade_panel = null
	if is_instance_valid(character_panel):
		_character_navigation = character_panel.navigation_state()
		character_panel.queue_free()
		character_panel = null
	if is_instance_valid(scenario_panel):
		scenario_panel.queue_free()
		scenario_panel=null
	if is_instance_valid(personal_panel):
		_retire(personal_panel)
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
				_button("KONVOI VORBEREITEN",Rect2(RESULT_COLUMN,688,RESULT_WIDTH,54),func():game.expedition.request("prepare"),20)
			else:
				_button("NEU STARTEN  [F5]",Rect2(RESULT_COLUMN,688,RESULT_WIDTH,54),_restart_match,20)
		_button("ONLINE-RAUM VERLASSEN" if _online() else "ZUM HAUPTMENÜ",Rect2(RESULT_COLUMN,750,RESULT_WIDTH,42),_request_main_menu,17)
		if is_instance_valid(game.solo_story) and game.solo_story.enabled:
			_button("Logbuch · J",Rect2(RESULT_COLUMN,642,RESULT_WIDTH,36),_open_solo_story,16)
		_wire_overlay_focus()
	if is_instance_valid(chat_panel): canvas.move_child(chat_panel,-1)
	if is_instance_valid(restart_dialog): canvas.move_child(restart_dialog,-1)

## Closing mirrors opening: a panel dismissed back to the match fades out over
## the same BASE duration the opening fade uses instead of vanishing in one
## frame. The retiring copy is renamed, takes no input, focus or processing and
## frees itself; the HUD field is cleared at once, so nothing else sees it.
## Panel-to-panel changes, reduced effects and scripted runs free it at once.
func _retire(panel: Control) -> void:
	if not is_instance_valid(panel): return
	if not overlay.is_empty() or not UiMotion.enabled() or not panel.is_inside_tree():
		panel.queue_free()
		return
	panel.name = "Retiring%d" % panel.get_instance_id()
	panel.process_mode = Node.PROCESS_MODE_DISABLED
	_release_input(panel)
	# The scrim under it holds until the sheet is gone, then clears.
	if game.started: _curtain_hold = UiMotion.QUICK
	# The opaque sheet sinks a few pixels and is gone (the mirror of the
	# opening rise); it never fades over the match.
	# Bound to the HUD (always processing): a scene change that frees the HUD
	# takes the tween and the retiring panel with it.
	UiMotion.sink(panel,panel.queue_free,Vector2(0,PANEL_SINK),UiMotion.QUICK,self)

func _release_input(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE
		if node.has_focus(): node.release_focus()
	for child in node.get_children(): _release_input(child)

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

func _button(title: String, rect: Rect2, callback: Callable, font_size: int = 0) -> Button:
	var button := Button.new()
	button.text = title
	button.position = rect.position
	button.size = rect.size
	UiArt.button(button,font_size if font_size>0 else (15 if rect.size.x>250 else 12))
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
	_place_curtain(crafting_panel)
	UiMotion.enter(crafting_panel,Vector2(0,PANEL_RISE),UiMotion.SLOW,_curtain_wait())
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
	UiArt.text(canvas,Vector2(rect.position.x+12,y),L.format("Kraftstoff %s · Fahrzeug %d · Karte M",[L.decimal(float(game.campaign.expedition.vehicle.fuel)),int(game.campaign.expedition.vehicle.hp)]),13,UiArt.MUTED)
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
