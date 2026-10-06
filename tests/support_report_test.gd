extends SceneTree
## Actual main scene and native options modal. Profiles/network/microphone stay
## off; adversarial private values must never enter the saved technical report.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Diagnostics := preload("res://scripts/support_diagnostics.gd")
const L := preload("res://scripts/locale_text.gd")
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	print("SUPPORT %s: %s" % ["PASS" if ok else "FAIL",message])

func frames(count: int = 4) -> void:
	for unused in count: await process_frame

func key(code: Key, shift: bool = false) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.shift_pressed=shift
		event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
	await frames()

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	L.set_locale("de",false)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await frames(6)
	var diagnostics: Node=game.hud.support_diagnostics
	check(is_instance_valid(diagnostics),"Safe report service lives with HUD before any worker exists")
	var before: int=diagnostics._events.size()
	for unused in 10: diagnostics._sample()
	check(diagnostics._events.size()==before,"Unchanged frames do not duplicate diagnostic events")
	var private_marker := "PRIVATE-SENTINEL-CREW-SECRET"
	game.network.room_code=private_marker
	game.network.relay_url="wss://"+private_marker+".invalid/ws"
	game.network.error_message=private_marker+" at 192.168.200.77"
	game.social.display_name=private_marker
	game.social.friend_code=private_marker
	game.social._secret=private_marker
	game.social.friends.clear()
	game.social.friends.append({"display_name":private_marker,"friend_code":private_marker})
	game.scenario_options={"environment":private_marker}
	game.notice=private_marker
	var report: Dictionary=diagnostics.capture()
	var encoded:=Diagnostics.encode(report)
	check(private_marker not in encoded and "192.168.200.77" not in encoded,"Private names, secrets, friends, addresses, room codes and notices never enter report")
	check(report.state.environment=="unknown" and report.state.network_error=="connection_error","Remote-controlled strings are replaced with bounded diagnostic enums")
	check(report.privacy.raw_logs_included==false and report.privacy.uploaded==false,"Report declares local safe trace, without raw logs or upload")
	check(report.version==ProjectSettings.get_setting("application/config/version") and report.network_build=="bunkercrew-net-20" and report.world_revision==5,"Actual app, transport and world identities are present")
	check(report.engine is String and report.recorded_utc.ends_with("Z") and report.platform==OS.get_name(),"Report has actual engine, platform and UTC capture time")
	var previous_stage: String=game.campaign.expedition.stage
	game.campaign.expedition.stage="travel"
	game.campaign.fail_journey()
	check(diagnostics.capture().state.travel_stage=="failed","An actual failed journey remains identifiable")
	game.campaign.expedition.stage=previous_stage
	var expected_renderer: String=RenderingServer.get_current_rendering_method()
	check(report.renderer==expected_renderer or (expected_renderer.is_empty() and report.headless and report.renderer=="headless"),"Reported renderer comes from actual runtime rather than unchanged project defaults")
	game.scenario_options={}
	game.network.room_code=""
	game.network.relay_url=""
	game.network.error_message=""
	game.notice=""
	var previous_wave: int=game.rounds.wave
	for index in Diagnostics.MAX_EVENTS+20:
		game.rounds.wave=index%20
		diagnostics._sample()
	check(diagnostics._events.size()==Diagnostics.MAX_EVENTS,"Transition history stays bounded at128 actual state changes")
	game.rounds.wave=previous_wave
	var saved:=Diagnostics.save_local(diagnostics.capture(),"user://support-regression")
	check(saved.ok,"Safe JSON can be saved locally without any network request")
	var restored: Variant=JSON.parse_string(FileAccess.get_file_as_string(str(saved.path)))
	check(restored is Dictionary and restored.state.mode=="menu" and private_marker not in Diagnostics.encode(restored),"Actual saved report is parseable and preserves privacy")
	check(DirAccess.remove_absolute(str(saved.path))==OK,"Test removes only its own report file")
	var blocked_path := "user://support-regression/blocked-file.txt"
	var blocked_file := FileAccess.open(blocked_path,FileAccess.WRITE)
	blocked_file.store_string("This file deliberately prevents creating a reports directory.")
	blocked_file.close()
	var failed_save:=Diagnostics.save_local(diagnostics.capture(),blocked_path.path_join("reports"))
	check(not failed_save.ok and int(failed_save.error)!=OK,"An actual blocked local directory returns a usable save failure")
	check(DirAccess.remove_absolute(blocked_path)==OK,"Failed save leaves the blocking file intact and cleanup removes only the test file")
	await key(KEY_F4)
	var options: Control=game.hud.options_panel
	options.support_button.grab_focus()
	await key(KEY_ENTER)
	await frames()
	var panel: Control=options.support_panel
	check(is_instance_valid(panel) and options.has_modal_subpanel(),"Actual keyboard activates support modal through Options")
	check(game.hud.overlay=="audio" and paused and game.players.is_empty(),"Report leaves paused menu and worker count unchanged")
	check(not game.microphone.capturing,"Reporting never opens a microphone")
	check(panel.back_button.has_focus() and not options.back_button.is_visible_in_tree(),"Native modal takes focus and hides its parent actions")
	for locale: String in ["de","en"]:
		L.set_locale(locale,false)
		await frames()
		check(panel.copy_button.text==L.text("Bericht kopieren") and panel.back_button.text==L.text("Zurück · Esc"),"Report labels follow language without recreating the modal: "+locale)
		var reached: Dictionary={}
		var initial:=root.gui_get_focus_owner()
		var expected:=4 if panel.copy_button.disabled else 5
		for unused in expected:
			var focus_owner:=root.gui_get_focus_owner()
			check(is_instance_valid(focus_owner) and panel.is_ancestor_of(focus_owner) and focus_owner.is_visible_in_tree(),"Tab stays inside active report in "+locale)
			reached[focus_owner.get_instance_id()]=true
			await key(KEY_TAB)
		check(reached.size()==expected and root.gui_get_focus_owner()==initial,"All available report actions and preview are reachable once: "+locale)
		await key(KEY_TAB,true)
		check(root.gui_get_focus_owner()!=initial,"Shift-Tab navigates backwards inside report: "+locale)
		await key(KEY_TAB)
	for shortcut: Key in [KEY_F1,KEY_F5,KEY_F7,KEY_T,KEY_P]:
		await key(shortcut)
		check(options.support_panel==panel and game.hud.overlay=="audio" and not game.hud.has_session_action(),"Gameplay/menu shortcut cannot escape report modal: "+OS.get_keycode_string(shortcut))
	await key(KEY_ESCAPE)
	check(not options.has_modal_subpanel() and options.support_button.has_focus() and game.hud.overlay=="audio", "Esc restores exact Options opener without leaving the parent menu")
	await key(KEY_F4)
	check(game.hud.overlay=="menu" and paused,"F4 then returns normally to main menu")
	game.start_scenario(1,{"environment":"mountain_pass","position":"left","build_type":"bastion"})
	await frames()
	check(diagnostics.capture().state.mode=="free_shift" and diagnostics.capture().state.campaign_active,"Free Shift remains identifiable while using shared campaign progression")
	var previous_story: bool=game.story_mode
	game.story_mode=true
	check(diagnostics.capture().state.mode=="story","Story remains identifiable with active shared campaign progression")
	game.story_mode=previous_story
	var old_current: String=game.campaign.current_node
	var old_pending: String=game.campaign.pending_node
	previous_stage=game.campaign.expedition.stage
	game.campaign.current_node="harbor"
	game.campaign.pending_node="quarry"
	game.campaign.expedition.stage="preparation"
	check(diagnostics.capture().state.chapter=="harbor","Garage reporting identifies the occupied source rather than the next destination")
	game.campaign.expedition.stage="travel"
	check(diagnostics.capture().state.chapter=="harbor","Travel reporting preserves the departure chapter before arrival")
	game.campaign.expedition.stage="defense"
	check(diagnostics.capture().state.chapter=="quarry","An arrived defense reports its active destination chapter")
	game.campaign.current_node=old_current
	game.campaign.pending_node=old_pending
	game.campaign.expedition.stage=previous_stage
	await key(KEY_F4)
	options=game.hud.options_panel
	options.support_button.grab_focus()
	await key(KEY_ENTER)
	panel=options.support_panel
	check(panel.report.state.environment=="mountain_pass" and panel.report.state.players==1 and panel.report.state.paused,"In-game report captures actual loaded environment, crew and pause")
	var time_before: float=game.rounds.time_left
	await create_timer(.08,true).timeout
	check(is_equal_approx(time_before,game.rounds.time_left),"Offline report keeps the round genuinely paused")
	await key(KEY_ESCAPE)
	await key(KEY_F4)
	check(game.hud.overlay.is_empty() and not paused,"Closing report and parent options resumes the live game")
	check(await Cleanup.free_scene(game,self),"Scene cleanup retires report service and audio handles")
	print("Support report: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
