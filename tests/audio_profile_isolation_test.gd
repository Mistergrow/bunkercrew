extends SceneTree
## The runner supplies a temporary XDG_DATA_HOME, never a real player profile.
const Audio := preload("res://scripts/audio.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func run() -> void:
	var fixture_root := OS.get_environment("BUNKERCREW_AUDIO_FIXTURE")
	if "--no-profile-save" not in OS.get_cmdline_user_args() or fixture_root.is_empty() or not OS.get_user_data_dir().begins_with(fixture_root+"/"):
		push_error("Run this test with --no-profile-save and a temporary XDG_DATA_HOME declared as BUNKERCREW_AUDIO_FIXTURE")
		quit(2)
		return
	var fixture := ConfigFile.new()
	fixture.set_value("audio","music",0.0)
	fixture.set_value("audio","sfx",0.0)
	fixture.set_value("rhythm","live_music",false)
	fixture.set_value("rhythm","dance_intensity",0.0)
	check(fixture.save("user://audio.cfg")==OK,"A muted legacy preference exists only in the temporary fixture directory")
	var original := FileAccess.get_file_as_bytes("user://audio.cfg")
	var audio := Audio.new()
	root.add_child(audio)
	audio.set_process(false)
	check(audio.music_volume==0.5 and audio.sfx_volume==0.5 and audio.live_music_enabled and audio.dance_intensity==1.5,"No-profile gameplay starts with the chosen audible music and active dance defaults instead of inheriting saved player preferences")
	audio.set_music_volume(0.4)
	audio.save_settings()
	check(FileAccess.get_file_as_bytes("user://audio.cfg")==original,"No-profile diagnostics do not overwrite the saved preference file")
	var dedicated := "user://audio-isolation-fixture.cfg"
	check(fixture.save(dedicated)==OK,"An explicitly dedicated persistence fixture remains available to settings tests")
	audio.settings_path=dedicated
	audio._load_settings()
	check(audio.music_volume==0.0 and not audio.live_music_enabled and audio.dance_intensity==0.0,"Explicit isolated settings paths still test real persisted values")
	check(await Cleanup.free_scene(audio,self),"The isolated real audio node releases its native score players")
	print("AUDIO PROFILE ISOLATION: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
