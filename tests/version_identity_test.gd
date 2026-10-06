extends SceneTree
## Real UI identity, local notes and bounded export-sidecar validation. No saves.
const Identity := preload("res://scripts/build_identity.gd")
const Notes := preload("res://scripts/release_notes_catalog.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const L := preload("res://scripts/locale_text.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks:=0
var failures:=0
var game: Node

func _initialize() -> void: _run.call_deferred()

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func frames(count: int=4) -> void:
	for unused in count: await process_frame

func reloaded(previous_id: int,expected_started: bool) -> bool:
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=previous_id and current_scene.started==expected_started:
			game=current_scene
			await frames()
			return true
	check(false,"The confirmed action reloads its actual target scene")
	return false

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.pressed=pressed
		Input.parse_input_event(event)
		await process_frame
	await frames()

func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts/version-identity-20261005")
	check(root.get_texture().get_image().save_png("res://artifacts/version-identity-20261005/"+name+".png")==OK,"Native identity screenshot is saved")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	AudioServer.set_bus_mute(0,true)
	var version:=str(ProjectSettings.get_setting("application/config/version"))
	check(Identity.version()==version,"ProjectSettings stays the only live release source")
	var info: Dictionary={"version":version,"network_protocol":Protocol.BUILD,"world_revision":Protocol.WORLD_REVISION,"platform":"ubuntu-x86_64","source_sha256":"a".repeat(64),"secret":"PRIVATE-BUILD-SENTINEL"}
	var accepted:=Identity.validated_info(info,version,"ubuntu-x86_64")
	check(accepted.build=="a".repeat(12) and accepted.exported,"Real builder schema provides a short public source identity")
	check("PRIVATE-BUILD-SENTINEL" not in JSON.stringify(accepted),"Unexpected sidecar fields never enter a report or label")
	for field: String in ["version","network_protocol","world_revision","platform","source_sha256"]:
		var corrupt:=info.duplicate()
		corrupt[field]="mismatch"
		check(Identity.validated_info(corrupt,version,"ubuntu-x86_64").is_empty(),"Stale export identity is rejected: "+field)
	var path:="user://version-regression-info.json"
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(info))
	file.close()
	check(Identity.read_info(path,version,"ubuntu-x86_64")==accepted,"Matching BUILD_INFO is read from a bounded local file")
	file=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(" ".repeat(Identity.MAX_INFO_BYTES+1))
	file.close()
	check(Identity.read_info(path,version,"ubuntu-x86_64").is_empty(),"Oversized external metadata cannot be loaded")
	check(DirAccess.remove_absolute(path)==OK,"Only the test's own sidecar fixture is removed")
	check(not Notes.entries().is_empty() and Notes.entries()[0].version==version,"Shipped newest milestone agrees with the running game")
	L.set_locale("de",false)
	var german:=Notes.body_text()
	L.set_locale("en",false)
	check(Notes.body_text()!=german and "Archived Ubuntu" in Notes.body_text(),"The same release source has real English notes")
	L.set_locale("de",false)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await frames(6)
	var badge:=game.hud.canvas.get_node("VersionBadge") as Label
	check(badge!=null and badge.is_visible_in_tree() and badge.mouse_filter==Control.MOUSE_FILTER_IGNORE and badge.focus_mode==Control.FOCUS_NONE,"Identity is visible in the main menu without capturing input")
	check(version in badge.text and "dev" in badge.text,"Source runs identify their development build honestly")
	for dimensions: Vector2i in [Vector2i(960,600),Vector2i(1440,900),Vector2i(1920,1080)]:
		root.size=dimensions
		await frames()
		badge._layout()
		var bounds: Rect2=game.hud.screen_rect()
		check(bounds.encloses(Rect2(badge.position,badge.size)),"Version label stays inside supported viewport "+str(dimensions))
	await capture("main-menu-de")
	var menu: Control=game.hud.main_menu_panel
	menu.release_button.grab_focus()
	await key(KEY_ENTER)
	check(menu.has_modal_subpanel() and not menu.release_button.is_visible_in_tree(),"Native main-menu action opens local notes and hides underlying actions")
	for shortcut: Key in [KEY_SPACE,KEY_F1,KEY_F4,KEY_F7,KEY_P,KEY_T]:
		await key(shortcut)
		check(menu.has_modal_subpanel() and game.hud.overlay=="menu" and not game.started,"Shortcut cannot start or replace the notes modal: "+OS.get_keycode_string(shortcut))
	var panel: Control=menu.release_panel
	check(panel.back_button.has_focus(),"Local notes own initial focus")
	await key(KEY_TAB)
	check(panel.reader.has_focus(),"The note reader is reachable by keyboard/controller focus")
	await key(KEY_TAB)
	check(panel.back_button.has_focus(),"Reader focus stays inside the active modal")
	L.set_locale("en",false)
	await frames()
	check("Archived Ubuntu" in panel.reader.text and panel.back_button.text==L.text("Zurück · Esc"),"Open notes update language without rebuilding the game")
	await capture("notes-en")
	await key(KEY_ESCAPE)
	check(not menu.has_modal_subpanel() and menu.release_button.has_focus(),"Escape returns to the exact main-menu opener")
	await key(KEY_F4)
	var options: Control=game.hud.options_panel
	options.release_button.grab_focus()
	await key(KEY_ENTER)
	check(options.has_modal_subpanel() and is_instance_valid(options.release_panel),"The same local notes remain available in Options")
	await key(KEY_ESCAPE)
	check(not options.has_modal_subpanel() and options.release_button.has_focus(),"Options notes restore the parent and its exact native focus")
	var report: Dictionary=game.hud.support_diagnostics.capture()
	check(report.version==version and report.build==Identity.current().build and report.source_sha256==Identity.current().source_sha256,"Tester report shares exactly the visible version/build identity")
	check(not game.started and game.players.is_empty() and not game.network.active,"Reading versions and notes never starts gameplay or networking")
	await key(KEY_F4)
	game.start_scenario(1,{"environment":"ash_foundry","position":"center","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.set_process(false)
	game.story.set_process(false)
	await frames(6)
	check(badge.is_visible_in_tree() and game.hud.version_badge==badge,"The same identity remains visible after the real mission starts")
	await key(KEY_ESCAPE)
	for action: String in ["restart","menu"]:
		var opener: Button=game.hud.pause_buttons["restart" if action=="restart" else "main_menu"]
		opener.grab_focus()
		await key(KEY_ENTER)
		check(game.hud.has_session_action() and game.hud._session_action==action,"The real paused mission opens its "+action+" confirmation")
		check(badge.is_visible_in_tree() and not game.hud._session_action_visibility.has(badge.get_instance_id()),"Identity stays visible outside the underlying-control hide transaction: "+action)
		check(badge.focus_mode==Control.FOCUS_NONE and badge.mouse_filter==Control.MOUSE_FILTER_IGNORE and game.hud.restart_dialog.cancel_button.has_focus(),"The visible identity never steals confirmation input: "+action)
		await key(KEY_ESCAPE)
		check(not game.hud.has_session_action() and badge.is_visible_in_tree() and opener.has_focus() and game.hud.overlay=="pause", "Cancellation restores its opener while keeping identity visible: "+action)
	game.hud.pause_buttons.restart.grab_focus()
	await key(KEY_ENTER)
	game.hud.restart_dialog.confirm_button.grab_focus()
	var previous_scene_id: int=game.get_instance_id()
	var previous_badge: WeakRef=weakref(badge)
	var expected_identity: String=badge.text
	await key(KEY_ENTER)
	if not await reloaded(previous_scene_id,true): quit(1); return
	badge=game.hud.version_badge
	check(game.players.size()==1 and badge.is_visible_in_tree() and badge.text==expected_identity and previous_badge.get_ref()==null,"A confirmed mission restart replaces the old scene while preserving its visible identity")
	game.rounds.running=false
	game.rounds.set_process(false)
	game.story.set_process(false)
	await key(KEY_ESCAPE)
	game.hud.pause_buttons.main_menu.grab_focus()
	await key(KEY_ENTER)
	game.hud.restart_dialog.confirm_button.grab_focus()
	previous_scene_id=game.get_instance_id()
	previous_badge=weakref(badge)
	await key(KEY_ENTER)
	if not await reloaded(previous_scene_id,false): quit(1); return
	badge=game.hud.version_badge
	check(game.hud.overlay=="menu" and badge.is_visible_in_tree() and badge.text==expected_identity and previous_badge.get_ref()==null,"A confirmed return to the main menu preserves visible identity and retires the old scene")
	check(await Cleanup.free_scene(game,self),"Identity widgets, readers and report service retire with their scene")
	print("VERSION IDENTITY: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
