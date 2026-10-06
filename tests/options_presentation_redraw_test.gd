extends SceneTree
## Real retained text commands must refresh on edits, locale and window changes.
## The independent panorama and native controls continue rendering every frame.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/beta-0.5-hardening-20261004/presentation/options-retained/"
var game: Node
var checks := 0
var failures := 0
var foreground_draws := 0
var records: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func frames(count: int=8) -> void:
	for frame in count: await process_frame

func unchanged(panel: Control,label: String) -> void:
	await frames()
	foreground_draws=0
	var menu_time: float=panel._landscape.preview.elapsed if is_instance_valid(panel._landscape.get("preview")) else -1.0
	await frames(20)
	check(foreground_draws==0,label+" retains unchanged text and shade commands")
	records.append({"sample":label,"frames":20,"foreground_redraws":foreground_draws})
	if menu_time>=0.0:
		check(panel._landscape.preview.elapsed>menu_time,label+" keeps the independent landscape animation alive")

func updated(label: String) -> void:
	await frames()
	check(foreground_draws>0,label+" refreshes actual rendered foreground commands")

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	check(picture.get_size()==root.size and picture.save_png(OUTPUT+label+".png")==OK,label+" records the actual native options view")

func run() -> void:
	if DisplayServer.get_name()=="headless" or AudioServer.get_driver_name()!="Dummy" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	LocaleText.set_locale("de",false)
	root.size=Vector2i(1440,900)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await frames()
	game.hud._toggle_audio()
	await frames()
	var panel: Control=game.hud.options_panel
	panel.decoration.draw.connect(func(): foreground_draws+=1)
	check(not game.audio.persistence_enabled and not game.campaign.persistence_enabled and not game.combat_events.persistence_enabled,"Actual options fixture cannot save settings or progress")
	for tab in 5:
		panel.select_tab(tab)
		await unchanged(panel,"Category %d"%tab)
	panel.select_tab(2)
	await frames()
	var audio_id: int=game.audio.get_instance_id()
	foreground_draws=0
	game.audio.set_music_volume(.27)
	await updated("External Music change")
	check(is_equal_approx(panel.audio_sliders[0].value,.27),"Real native Music slider follows its edited audio owner")
	await unchanged(panel,"Edited audio page")
	foreground_draws=0
	panel.audio_sliders[1].value=.68
	await updated("Native SFX slider edit")
	check(is_equal_approx(game.audio.sfx_volume,.68),"Native SFX slider still adjusts the mixer immediately")
	await capture("audio-de")
	panel.select_tab(1)
	await frames()
	foreground_draws=0
	game.set_camera_zoom(.85)
	await updated("External camera zoom")
	check(is_equal_approx(panel.zoom_slider.value,.85),"Native camera slider and its percentage remain current")
	panel.select_tab(3)
	await frames()
	foreground_draws=0
	game.audio.set_music_calibration(.125)
	await updated("Device compensation change")
	foreground_draws=0
	panel.dance_gain_slider.value=.77
	await updated("Dance intensity edit")
	check(is_equal_approx(game.audio.dance_intensity,.77),"Native dance slider still reaches the real retained audio owner")
	foreground_draws=0
	LocaleText.set_locale("en",false)
	await updated("Live DE to EN change")
	check(panel==game.hud.options_panel and game.audio.get_instance_id()==audio_id and is_equal_approx(game.audio.music_volume,.27),"Locale switching preserves options identity, mixer and edited values")
	await capture("rhythm-en")
	await unchanged(panel,"English rhythm page")
	foreground_draws=0
	root.size=Vector2i(1680,900)
	await create_timer(.12,true).timeout
	await updated("Native widescreen resize")
	check(game.hud.screen_rect().size.x>1440,"Widescreen resize expands the actual foreground bounds")
	await capture("rhythm-en-wide")
	await unchanged(panel,"Resized rhythm page")
	panel._open_calibration()
	await frames()
	check(panel.has_modal_subpanel() and game.audio.calibration_active,"Opening a modal still suspends main music and hides underlying controls")
	foreground_draws=0
	panel.close_modal_subpanel()
	await updated("Calibration close")
	check(not panel.has_modal_subpanel() and not game.audio.calibration_active and panel.pages[3].visible,"Modal close restores the selected native settings page and original music routing")
	await unchanged(panel,"Returned rhythm page")
	check(not game.network.active and not game.microphone.capturing,"Rendering regression opens neither transport nor microphone")
	check(await Cleanup.free_scene(game,self),"Native scene and active or retired audio handles release cleanly")
	var report:=FileAccess.open(OUTPUT+"verification.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records,"prepared_state":"Actual main menu options, Dummy audio, isolated XDG, real external and native control edits, live locale change, owned native window resize, calibration modal return. No renderer switch, connection, microphone or profile save."},"\t")+"\n")
	print("OPTIONS PRESENTATION REDRAW: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
