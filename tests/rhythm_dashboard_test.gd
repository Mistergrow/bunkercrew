extends SceneTree
const Lab := preload("res://scripts/music_dev_dashboard.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class SavedMusic extends Node:
	var dance_intensity := 1.0
	var dance_profiles: Dictionary = {}
	var reduced_motion := false
class AudioSettings extends Node:
	var calibration_active := false
	var live_music: SavedMusic
	var applied: Dictionary = {}
	var reduced := false
	var music_style := "level_default"
	func set_dance_configuration(gain: float,profiles: Dictionary) -> void:
		applied = {"gain":gain,"profiles":profiles.duplicate(true)}
	func set_rhythm_motion_reduced(value: bool) -> void:
		reduced = value
	func set_music_style(value: String) -> void:
		music_style = value
class SourceGame extends Node:
	var audio: AudioSettings

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	InputSetup.install()
	root.size = Vector2i(1440,900)
	var lab := Lab.new()
	root.add_child(lab)
	var source := SourceGame.new()
	root.add_child(source)
	source.audio = AudioSettings.new()
	source.add_child(source.audio)
	source.audio.live_music = SavedMusic.new()
	source.audio.add_child(source.audio.live_music)
	lab.show_for_game(source)
	await process_frame
	await process_frame
	check(lab.preview_world.actors.size() == Dance.IDS.size(), "Lab instantiates every actual crew rig")
	check(lab.styles.size() == Dance.IDS.size() and lab.gains.size() == Dance.IDS.size(), "Every authored style and intensity control is interactive")
	var preview_rows: Dictionary = {}
	for actor: Worker in lab.preview_world.actors:
		check(Rect2(0,0,1440,620).has_point(actor.position),actor.character_id+" rig fits the authored preview")
		preview_rows[actor.position.y] = true
	check(preview_rows.size()==2 and lab.profile_grid.columns==4,"Eight crew rigs and controls use two complete balanced rows")
	check(lab.genre_choice.item_count == 5,"Four musical styles and the level recommendation are selectable")
	check(source.audio.calibration_active,"Main score is suspended while the isolated preview is open")
	check(lab.preview_world.actors.all(func(actor): return not actor.is_in_group("players")),"Preview actors cannot enter the game's player group")
	check(not lab.preview_session.publish_shader_pulse, "Isolated preview never overwrites the game's global pulse")
	for index in Dance.IDS.size():
		var id: String = Dance.IDS[index]
		lab.styles[id].item_selected.emit(index)
		lab.gains[id].value = 0.30 + index * 0.15
		check(lab.configuration.dance_profiles[id].style == str(lab.styles[id].get_item_metadata(index)) and is_equal_approx(float(lab.configuration.dance_profiles[id].intensity),0.30+index*0.15),id+" style and gain signals affect the intended character")
		var expected := Dance.styles_for(id)
		check(lab.styles[id].item_count==expected.size() and expected.size()==9,id+" previews its five own moves and three shared moves with Auto")
		for item in lab.styles[id].item_count:
			var offered := str(lab.styles[id].get_item_metadata(item))
			check(Dance.owner(offered).is_empty() or Dance.owner(offered)==id,id+" never offers another character's unique move")
	lab.configuration.dance_profiles = Dance.defaults()
	lab._sync_controls()
	check(Lab.valid_configuration(JSON.parse_string(lab.export_json())), "Default exported feedback validates")
	var legacy: Dictionary = JSON.parse_string(lab.export_json())
	legacy.version = 1
	legacy.erase("genre")
	legacy.dance_profiles.erase("oskar")
	legacy.dance_profiles.erase("rika")
	check(lab.import_json(JSON.stringify(legacy)) and lab.configuration.version == 2 and lab.configuration.genre == "level_default","Version-one feedback still imports with the level recommendation")
	check(lab.configuration.dance_profiles.size()==Dance.IDS.size() and lab.configuration.dance_profiles.oskar==Dance.defaults().oskar and lab.configuration.dance_profiles.rika==Dance.defaults().rika,"Six-character feedback retains previous choices and supplies defaults for newly available crew")
	var payload: Dictionary = JSON.parse_string(lab.export_json())
	payload.theme_id = "mountain_pass"
	payload.bpm = 88.0
	payload.seed = 777
	payload.music_intensity = 3
	payload.dance_intensity = 1.4
	payload.dance_profiles.ivo = {"style":"hand_tap","intensity":1.25}
	payload.reduced_motion = true
	payload.feedback = "Prefer quieter pads and Ivo's hand tap."
	payload.genre = "hip_hop"
	check(lab.import_json(JSON.stringify(payload)), "Valid shared feedback imports")
	check(lab.configuration.theme_id == payload.theme_id and lab.tempo.value == 88.0 and lab.configuration.dance_profiles.ivo.style == "hand_tap", "Imported feedback updates actual native preview controls")
	var restored: Dictionary = JSON.parse_string(lab.export_json())
	var same := true
	for key: String in payload:
		if restored.get(key) != payload[key]:
			print("Feedback differs: ",key," ",restored.get(key)," / ",payload[key])
			same = false
	check(same, "Feedback round trip preserves every user preference")
	lab._apply_to_game()
	check(source.audio.applied.gain == 1.4 and source.audio.applied.profiles.ivo.style == "hand_tap" and source.audio.reduced and source.audio.music_style=="hip_hop","Selected music style and dance preferences apply through the existing settings API")
	var before := lab.export_json()
	for key: String in ["version","theme_id","seed","bpm","music_intensity","dance_intensity","dance_profiles","reduced_motion","feedback"]:
		var malformed := payload.duplicate(true)
		malformed.erase(key)
		check(not lab.import_json(JSON.stringify(malformed)) and lab.export_json() == before, "Missing " + key + " is rejected atomically")
	for changes in [{"bpm":2.0},{"bpm":500.0},{"seed":-1},{"seed":1.5},{"music_intensity":2.5},{"music_intensity":4},{"dance_intensity":-1.0},{"theme_id":"bad"},{"feedback":1},{"reduced_motion":"false"},{"dance_profiles":{"mara":{"style":"not_a_style","intensity":1.0}}}]:
		var malformed := payload.duplicate(true)
		malformed.merge(changes,true)
		check(not lab.import_json(JSON.stringify(malformed)) and lab.export_json() == before, "Malformed feedback cannot partially change preferences")
	check(not lab.import_json(" ".repeat(16385)) and lab.export_json() == before, "Oversized JSON is rejected")
	var bad_genre := payload.duplicate(true)
	bad_genre.genre = "invalid_style"
	check(not lab.import_json(JSON.stringify(bad_genre)) and lab.export_json() == before,"Unknown music styles are rejected atomically")
	for genre: String in Lab.GENRE_IDS:
		lab.genre_choice.item_selected.emit(Lab.GENRE_IDS.find(genre))
		check(lab.configuration.genre == genre,"Music-style selection reaches the real preview: "+genre)
	lab.configuration.reduced_motion = false
	lab.configuration.dance_intensity = 1.0
	lab.configuration.dance_profiles = Dance.defaults()
	lab._update_dance()
	# Explicit prepared silent clock, independent of headless AudioServer mix
	# scheduling. Production native mode continues to read actual mixed samples.
	lab.preview_session.end_session()
	lab.preview_clock.advance(2.0)
	for actor in lab.preview_world.actors:
		var visual: WorkerVisual = actor.get_node("PixelVisual")
		visual._process(2.0)
		check(visual.rhythm.weight > 0.0, actor.character_id + " preview drives the real waiting rig")
	lab._toggle_playing()
	lab.preview_clock.advance(0.0)
	for actor in lab.preview_world.actors:
		var visual: WorkerVisual = actor.get_node("PixelVisual")
		visual._process(0.0)
		check(visual.rhythm.weight == 0.0, actor.character_id + " stop cancels motion immediately")
	lab._toggle_playing()
	check(lab._playing and lab.preview_clock.playing, "Play resumes the isolated preview")
	check(await Cleanup.free_scene(lab,self), "Lab releases every preview actor and playback")
	check(not source.audio.calibration_active,"Closing the lab restores the previous music state")
	await Cleanup.free_scene(source,self)
	print("RHYTHM DASHBOARD: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
