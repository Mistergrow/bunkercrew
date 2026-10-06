extends SceneTree
## Corrupt or hand-edited settings must not send invalid values to AudioServer.
const AUDIO := preload("res://scripts/audio.gd")
var checks := 0
var failures := 0
var settings_path := "user://audio-settings-audit-%d.cfg" % OS.get_process_id()

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	var audio := AUDIO.new()
	audio.settings_path = settings_path
	audio.persistence_enabled = true # Only this isolated test file may be saved.
	root.add_child(audio)
	audio.set_process(false)
	var cases := [
		{"music":0.28, "sfx":0.83, "voice":0.62, "expected":Vector3(0.28, 0.83, 0.62)},
		{"music":0, "sfx":1, "voice":0, "expected":Vector3(0.0, 1.0, 0.0)},
		{"music":-3.0, "sfx":8.0, "voice":4.0, "expected":Vector3(0.0, 1.0, 1.0)},
		{"music":"invalid", "sfx":"0.8", "voice":"0.5", "expected":Vector3.ONE * 0.5},
		{"music":true, "sfx":false, "voice":true, "expected":Vector3.ONE * 0.5},
		{"music":[0.3], "sfx":{"volume":0.7}, "voice":[0.4], "expected":Vector3.ONE * 0.5},
		{"music":Vector2.ONE, "sfx":null, "voice":null, "expected":Vector3.ONE * 0.5},
		{"music":NAN, "sfx":INF, "voice":-INF, "expected":Vector3.ONE * 0.5},
		{"music":-INF, "sfx":0.52, "voice":NAN, "expected":Vector3(0.5, 0.52, 0.5)},
	]
	for index in cases.size():
		var config := ConfigFile.new()
		config.set_value("audio", "mix_version", 2)
		config.set_value("audio", "music", cases[index].music)
		config.set_value("audio", "sfx", cases[index].sfx)
		config.set_value("audio", "voice", cases[index].voice)
		check(config.save(settings_path) == OK, "Fixture %d saves to the dedicated test path" % index)
		audio._load_settings()
		check(is_equal_approx(audio.music_volume, cases[index].expected.x), "Fixture %d loads valid music or its independent default" % index)
		check(is_equal_approx(audio.sfx_volume, cases[index].expected.y), "Fixture %d loads valid effects or their independent default" % index)
		check(is_equal_approx(audio.voice_volume, cases[index].expected.z), "Fixture %d loads valid character voices or their independent default" % index)
	var corrupt := ConfigFile.new()
	corrupt.set_value("audio", "music", ["broken"])
	corrupt.set_value("audio", "sfx", {"broken":true})
	check(corrupt.save(settings_path) == OK, "Corrupt startup fixture remains in the isolated test file")
	var restarted := AUDIO.new()
	restarted.settings_path = settings_path
	root.add_child(restarted)
	restarted.set_process(false)
	await process_frame
	check(restarted.voices.size() == restarted.MAX_VOICES and is_instance_valid(restarted.music_player) and restarted.music_player.playing, "A real audio node initializes all voices and starts its score despite corrupt saved values")
	check(restarted.music_volume == 0.5 and restarted.sfx_volume == 0.5 and restarted.voice_volume == 0.5, "Corrupt and missing saved channels independently recover to fifty percent")
	await preload("res://tests/scene_cleanup.gd").free_scene(restarted, self)
	# Invalid runtime values preserve the last valid setting and its bus level.
	audio.set_music_volume(0.37)
	audio.set_sfx_volume(0.61)
	audio.set_voice_volume(0.72)
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	var voice_bus := AudioServer.get_bus_index("Voice")
	var music_db := AudioServer.get_bus_volume_db(music_bus)
	var sfx_db := AudioServer.get_bus_volume_db(sfx_bus)
	var voice_db := AudioServer.get_bus_volume_db(voice_bus)
	for invalid in [NAN, INF, -INF]:
		audio.set_music_volume(invalid)
		audio.set_sfx_volume(invalid)
		audio.set_voice_volume(invalid)
		check(is_equal_approx(audio.music_volume, 0.37) and is_equal_approx(audio.sfx_volume, 0.61) and is_equal_approx(audio.voice_volume, 0.72), "Non-finite slider values preserve valid settings")
		check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), music_db) and is_equal_approx(AudioServer.get_bus_volume_db(sfx_bus), sfx_db) and is_equal_approx(AudioServer.get_bus_volume_db(voice_bus), voice_db), "Non-finite slider values cannot corrupt bus gain")
	audio.save_settings()
	var saved := ConfigFile.new()
	check(saved.load(settings_path) == OK and is_equal_approx(saved.get_value("audio", "music"), 0.37) and is_equal_approx(saved.get_value("audio", "sfx"), 0.61) and is_equal_approx(saved.get_value("audio", "voice"), 0.72), "Only the last valid volume is persisted")
	var profiles:=preload("res://scripts/worker_dance_catalog.gd").defaults()
	profiles.mara={"style":"moonwalk","intensity":1.25}
	audio.set_music_style("hip_hop")
	audio.set_dance_configuration(1.1,profiles)
	audio.set_music_calibration(0.125)
	audio.set_rhythm_motion_reduced(true)
	audio.save_settings()
	audio.music_style="level_default"
	audio.dance_profiles={}
	audio.music_calibration_seconds=0.0
	audio.rhythm_motion_reduced=false
	audio._load_settings()
	check(audio.music_style=="hip_hop" and audio.dance_profiles.mara.style=="moonwalk" and is_equal_approx(audio.dance_profiles.mara.intensity,1.25),"Saved genre and individual full-body dance preferences survive a reload")
	check(is_equal_approx(audio.dance_intensity,1.1) and audio.rhythm_motion_reduced and is_equal_approx(audio.music_calibration_seconds,0.125),"Saved motion comfort and device timing remain independent of genre")
	audio.set_music_style("unknown_style")
	check(audio.music_style=="hip_hop","Invalid runtime genre cannot replace the last valid preference")
	corrupt.set_value("rhythm","music_style",["hip_hop"])
	corrupt.set_value("rhythm","dance_profiles",{"mara":{"style":"missing","intensity":1.0}})
	corrupt.set_value("rhythm","dance_intensity",NAN)
	corrupt.set_value("rhythm","calibration_seconds",INF)
	corrupt.set_value("rhythm","reduced_motion","true")
	check(corrupt.save(settings_path)==OK,"Malformed rhythm data saves only in the dedicated test file")
	audio._load_settings()
	check(audio.music_style=="level_default" and audio.dance_profiles.mara.style=="character_default","Malformed genre and dance profiles recover to validated defaults")
	check(audio.dance_intensity==1.5 and audio.music_calibration_seconds==0.0 and not audio.rhythm_motion_reduced,"Malformed motion/timing values recover to chosen defaults without entering the presentation clock")
	await preload("res://tests/scene_cleanup.gd").free_scene(audio, self)
	DirAccess.remove_absolute(settings_path)
	print("AUDIO SETTINGS: %d/%d checks passed" % [checks-failures, checks])
	quit(1 if failures else 0)
