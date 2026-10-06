extends SceneTree
## Actual shipped WAV metronome crosses its loop without rewinding tap time.
const Calibrator := preload("res://scripts/music_calibration_panel.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or AudioServer.get_driver_name()!="Dummy":
		push_error("Run with Dummy audio and --no-profile-save --no-upnp in isolated XDG directories")
		quit(1)
		return
	InputSetup.install()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	_freeze(game)
	var before_calibration: float = game.audio.music_calibration_seconds
	var panel := Calibrator.new()
	panel.audio=game.audio
	root.add_child(panel)
	panel.set_process(false)
	game.audio._process(0.0)
	var bus := AudioServer.get_bus_index("Music")
	var capture := AudioEffectCapture.new()
	capture.buffer_length=4.0
	AudioServer.add_bus_effect(bus,capture)
	panel._start()
	var length := panel.player.stream.get_length()
	panel.player.seek(length-1.2)
	var previous := -INF
	var backwards := 0
	var largest_step := 0.0
	var samples := 0
	var wrapped := false
	var deadline := Time.get_ticks_msec()+2600
	while Time.get_ticks_msec()<deadline:
		panel._process(0.0)
		if previous!=-INF:
			if panel.time_seconds<previous-1.0/Calibrator.RATE: backwards+=1
			largest_step=maxf(largest_step,panel.time_seconds-previous)
		previous=panel.time_seconds
		samples+=1
		wrapped=wrapped or panel.loops>0
		await create_timer(0.003,true,false,true).timeout
	var pcm := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for sample in pcm: peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
	check(samples>100,"Observe actual mixer time repeatedly on both sides of the WAV loop")
	check(wrapped and panel.time_seconds>length,"The real metronome completes its loop and continues tap time")
	check(backwards==0,"Mixer interpolation and decoder wrapping cannot rewind calibration time")
	check(largest_step<0.12,"The WAV loop does not introduce a full-loop jump in calibration time")
	check(pcm.size()>48000 and peak>0.01 and capture.get_discarded_frames()==0,"The real Music bus emits audible metronome PCM without buffer loss")
	panel._tap()
	check(panel.calibration.result().count==1 and game.audio.music_calibration_seconds==before_calibration,"A real-time tap records input without applying settings")
	AudioServer.remove_bus_effect(bus,AudioServer.get_bus_effect_count(bus)-1)
	check(await Cleanup.free_scene(panel,self),"Calibration playback retires cleanly")
	check(not game.audio.calibration_active,"Closing the metronome restores music")
	check(await Cleanup.free_scene(game,self),"The real game fixture releases all audio players")
	print("MUSIC CALIBRATION TRANSPORT: %d/%d checks passed; %d observations, %d backwards, largest step %.3f s" % [checks-failures,checks,samples,backwards,largest_step])
	quit(1 if failures else 0)
