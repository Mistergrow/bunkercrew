extends SceneTree
## Actual child startup consumes the same nonce request as an embedded handoff.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const DANCE := preload("res://scripts/worker_dance_catalog.gd")
const OUTPUT := "res://artifacts/fullscreen-f11"
var game: Node
var checks := 0
var failures := 0
var overlay := "menu"

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("FULLSCREEN_PREF_CHECK ",label)
	else:
		failures += 1
		push_error(label)

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var token := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--standalone-handoff="): token = argument.trim_prefix("--standalone-handoff=")
		if argument=="--handoff-overlay=audio": overlay = "audio"
	if token.length()!=32:
		quit(2)
		return
	var profiles := DANCE.defaults()
	profiles.mara.style = "mara_lockstep"
	var snapshot := {"version":1,"locale":"en","vsync_enabled":false,"violence":1,"overlay":overlay,"options_tab":4,"menu":{"environment":"mountain_pass","focus":"options","elapsed":4.5},"preferences":{"camera":{"mode":"overview","zoom":.8},"audio":{"music":.37,"sfx":.42,"voice":.58,"live":false,"style":"breakbeat","reduced_motion":true,"calibration":.125,"dance_intensity":.77,"dance_profiles":profiles},"reduced_effects":true,"records":{"achievements":[],"dance_levels":{"mara":10},"counters":{"mined":51,"crafted":7}}}}
	var request_path := "user://fullscreen-handoff-"+token+".request"
	var ready_path := "user://fullscreen-handoff-"+token+".ready"
	var request := FileAccess.open(request_path,FileAccess.WRITE)
	request.store_string(JSON.stringify(snapshot))
	request.close()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	for index in 35: await process_frame
	check(root.mode==Window.MODE_FULLSCREEN and not game.hud.display_settings.is_embedded() and not game.started,"Actual independent fullscreen scene starts safely as a main-menu child")
	check(game.hud.display_settings._handoff_preferences_ready and FileAccess.file_exists(ready_path),"Actual DisplaySettings acknowledges only after restoring its nonce request and rendering fullscreen")
	var ready: Variant = JSON.parse_string(FileAccess.get_file_as_string(ready_path)) if FileAccess.file_exists(ready_path) else {}
	check(ready is Dictionary and int(ready.get("pid",0))==OS.get_process_id() and ready.get("fullscreen",false)==true,"Actual readiness acknowledgement identifies this rendered child process")
	check(is_equal_approx(game.audio.music_volume,.37) and is_equal_approx(game.audio.sfx_volume,.42) and is_equal_approx(game.audio.voice_volume,.58),"Unsaved music, effects and voice sliders restore before the first visible menu")
	check(not game.audio.live_music_enabled and game.audio.music_style=="breakbeat","Unsaved native-music choice and genre restore independently of the menu track")
	check(game.audio.rhythm_motion_reduced and is_equal_approx(game.audio.music_calibration_seconds,.125),"Unsaved reduced movement and device beat calibration survive child startup")
	check(is_equal_approx(game.audio.dance_intensity,.77) and game.audio.dance_profiles.mara.style=="mara_lockstep","Unsaved dance intensity and the selected personal move survive child startup")
	check(LocaleText.current_locale()=="en" and game.weather.reduced_effects,"English language and reduced weather restore without saving the user profile")
	var camera: Dictionary = game.player_camera.settings()
	check(camera.mode=="overview" and is_equal_approx(float(camera.zoom),.8),"Unsaved camera mode and zoom survive the standalone handoff")
	var records: Dictionary = game.combat_events.session_records()
	check(int(records.dance_levels.get("mara",0))==10 and records.counters.mined==51 and records.counters.crafted==7,"JSON roundtrip retains integer dance unlocks and progression counters in the real game")
	check(game.hud.overlay==overlay and game.hud.options_tab==4,"The original menu or options overlay and language tab survive child startup")
	check(game.hud._main_menu_navigation.environment=="mountain_pass" and game.hud._main_menu_navigation.focus=="options","The original landscape preview and navigation focus survive child startup")
	check(game.audio.menu_music.playing and game.audio.menu_rhythm_frame().active,"Restored settings keep the dedicated menu music playing")
	check(game.combat_gore.level==1 and DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED,"Violence level and vertical synchronization restore without writing preferences")
	if overlay=="audio":
		check(is_instance_valid(game.hud.options_panel) and game.hud.options_panel.tab==4,"Actual child renders the preserved language page of its options panel")
	else:
		check(is_instance_valid(game.hud.main_menu_panel) and game.hud.main_menu_panel.preview.environment_id=="mountain_pass" and game.hud.main_menu_panel.wordmark_state().reduced,"Actual child shows the preserved landscape and stationary reduced-motion title")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT+"/preferences-"+overlay+".png")==OK,"Actual fullscreen child screenshot is recorded")
	var preferences: Dictionary = game.session_preferences()
	var report := {"checks":checks,"failures":failures,"overlay":overlay,"actual_main_scene":true,"actual_fullscreen":true,"nonce_request_consumed":true,"profile_saving_disabled":true,"locale":LocaleText.current_locale(),"preferences":preferences,"snapshot":snapshot,"ready":ready}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(request_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ready_path))
	paused = false
	check(await CLEANUP.free_scene(game,self),"Actual restored child releases every scene and playback cleanly")
	report.checks = checks
	report.failures = failures
	var file := FileAccess.open(OUTPUT+"/preferences-"+overlay+"-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("FULLSCREEN REAL PREFERENCES: ",checks-failures,"/",checks," passed")
	quit(0 if failures==0 else 1)
