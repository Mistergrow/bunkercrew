extends SceneTree
## Actual menu/audio services and controls with fifteen deterministic tap times.
const CalibrationPanel := preload("res://scripts/music_calibration_panel.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	InputSetup.install()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var original_level: float = game.audio.music_volume
	game.audio.set_music_volume(1.0)
	var panel := CalibrationPanel.new()
	panel.audio = game.audio
	root.add_child(panel)
	panel.set_process(false)
	check(game.audio.calibration_active,"Calibration suspends the real game's music mix")
	check(panel.tap_button.disabled and panel.apply_button.disabled,"Tap/apply controls start disabled")
	var start_button: Button
	for child in panel.get_children():
		if child is Button and child.text == LocaleText.text("START"): start_button = child
	check(is_instance_valid(start_button),"The actual start control is present")
	start_button.pressed.emit()
	check(panel.started and panel.player.playing and not panel.tap_button.disabled,"Start control begins the actual audible metronome")
	var before_calibration: float = game.audio.music_calibration_seconds
	for index in 15:
		panel.time_seconds = (index+1)*0.6 + 0.182 + [0.0,0.003,-0.002][index%3]
		panel.tap_button.pressed.emit()
		if index < 14:
			check(game.audio.music_calibration_seconds == before_calibration,"Tap input cannot write settings before confirmation")
	var result := panel.calibration.result()
	check(result.ready and result.count == 15 and absf(float(result.seconds)-0.182) < 0.006,"Fifteen control taps produce a robust output-delay estimate")
	panel._process(0.0)
	check(not panel.apply_button.disabled,"Fifteen consistent taps enable the actual apply control")
	panel.apply_button.pressed.emit()
	await process_frame
	check(absf(game.audio.music_calibration_seconds-0.182) < 0.006,"Apply control saves compensation through the real audio settings API")
	check(not game.audio.calibration_active,"Closing calibration restores the previous music mix")
	var disabled := CalibrationPanel.new()
	disabled.audio = game.audio
	root.add_child(disabled)
	disabled.set_process(false)
	game.audio.set_music_volume(0.0)
	disabled._start()
	check(not disabled.started and not disabled.player.playing,"Muted music cannot start a misleading calibration click")
	await Cleanup.free_scene(disabled,self)
	game.audio.set_music_volume(original_level)
	check(await Cleanup.free_scene(game,self),"Calibration game fixture releases all audio players")
	print("MUSIC CALIBRATION UI: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
