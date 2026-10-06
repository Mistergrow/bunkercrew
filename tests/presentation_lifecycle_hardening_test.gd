extends SceneTree
## Real options/audio ownership under same-frame modal replacement and re-entry.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	print("PRESENTATION %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func frames(count: int = 2) -> void:
	for frame in count: await process_frame

func _run() -> void:
	print("PRESENTATION lifecycle: constructing the main scene")
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await frames()
	game.hud._toggle_audio()
	await frames()
	var options: Control=game.hud.options_panel
	options.select_tab(3)
	for kind: String in ["calibration","music_lab"]:
		game.audio.calibration_active=false
		if kind=="calibration": options._open_calibration()
		else: options._open_music_lab(false)
		var previous: Node=options.calibration_panel if kind=="calibration" else options.music_lab
		check(game.audio.calibration_active,kind+": opening suspends the main music mix")
		previous.close()
		check(not game.audio.calibration_active,kind+": close releases music ownership before notifying callers")
		if kind=="calibration": options._open_calibration()
		else: options._open_music_lab(false)
		var replacement: Node=options.calibration_panel if kind=="calibration" else options.music_lab
		check(is_instance_valid(replacement) and replacement!=previous,kind+": caller can open a new modal in the same frame")
		await frames()
		var current: Node=options.calibration_panel if kind=="calibration" else options.music_lab
		check(current==replacement,kind+": old tree_exited callback retains the replacement modal")
		check(options.has_modal_subpanel() and not options.back_button.visible,kind+": settings stay hidden behind the replacement")
		check(game.audio.calibration_active,kind+": old teardown cannot unmute a running replacement")
		replacement.close()
		await frames()
		check(not game.audio.calibration_active and not options.has_modal_subpanel(),kind+": final close restores the original main mix")
		check(options.back_button.visible,kind+": final close restores the options controls")
	game.audio.calibration_active=false
	options._open_calibration()
	var closing: Node=options.calibration_panel
	var notifications := [0]
	closing.closed.connect(func():
		notifications[0]+=1
		if notifications[0]<2: closing.close())
	closing.close()
	check(notifications[0]==1,"Calibration close emits once even when a closed listener calls close again")
	await frames()
	check(not game.audio.calibration_active,"Reentrant calibration close leaves main music restored")
	for kind: String in ["calibration","music_lab"]:
		if kind=="calibration": options._open_calibration()
		else: options._open_music_lab(false)
		game.hud._rebuild_buttons()
		options=game.hud.options_panel
		options.select_tab(3)
		check(not game.audio.calibration_active,kind+": rebuilding the options parent releases its owned music suspension immediately")
		options._open_calibration()
		await frames()
		check(game.audio.calibration_active,kind+": queued parent teardown cannot unmute the new calibration")
		options.calibration_panel.close()
		await frames()
		check(not game.audio.calibration_active,kind+": replacement options restore the original music state after close")
	check(await Cleanup.free_scene(game,self),"Presentation lifecycle fixture releases actual audio and UI nodes")
	print("PRESENTATION LIFECYCLE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
