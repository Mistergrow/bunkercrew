extends SceneTree
## Real recorded and native decoders retire before a process-level exit.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("AUDIO EXIT ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1; push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var audio = game.audio
	check(audio.menu_music.playing, "Actual main menu has an active recorded decoder")
	var recorded: WeakRef = weakref(audio.menu_music.player.get_stream_playback())
	audio.menu_music.stop()
	audio.set_process(false)
	audio.live_music.begin_session("mountain_pass", 1047)
	check(audio.live_music.native_active and audio.live_music.player.playing, "Real native Tessel decoder is active before retirement")
	var native: WeakRef = weakref(audio.live_music.player.get_stream_playback())
	var native_stream: WeakRef = weakref(audio.live_music.native_stream)
	audio.set_music_volume(.61)
	check(await audio.drain_for_exit(), "Stop/drain finishes on actual AudioServer handle release")
	check(recorded.get_ref() == null and native.get_ref() == null and native_stream.get_ref() == null, "Previously stopped recorded and current native playback objects all release")
	check(not audio.is_processing() and not audio.menu_music.playing and not audio.live_music.session_active, "The waiting source cannot restart its music during handoff")
	check(not audio._settings_dirty and is_equal_approx(audio.music_volume, .61), "Pending valid settings are retained while no-profile writes remain disabled")
	check(await audio.drain_for_exit(), "Repeated retirement is safe and completes immediately")
	# An external consumer can keep a native playback handle alive. Shutdown
	# must stop sound and finish its bounded wait without claiming it was freed.
	audio.menu_music.start()
	var retained: AudioStreamPlayback = audio.menu_music.player.get_stream_playback()
	var retained_weak: WeakRef = weakref(retained)
	var wait_started := Time.get_ticks_msec()
	var fully_drained: bool = await audio.drain_for_exit()
	var waited := Time.get_ticks_msec() - wait_started
	check(not fully_drained and waited >= 5000 and waited < 5500, "Externally retained real decoder returns false after the bounded five-second wait")
	check(retained_weak.get_ref() != null and not audio.menu_music.playing, "Timeout reports the live handle truthfully while playback remains stopped")
	retained = null
	check(await audio.drain_for_exit() and retained_weak.get_ref() == null, "Releasing the external owner permits a subsequent clean drain")
	check(await Cleanup.free_scene(game, self), "Retired scene and every audio player still teardown normally")
	print("AUDIO EXIT DRAIN: %d/%d checks passed" % [checks-failures, checks])
	quit(1 if failures else 0)
