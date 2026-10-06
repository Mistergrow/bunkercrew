extends SceneTree
## Native bridge regression: all authored musical modes, settings and repeatable
## first-bar PCM reach the same engine used by the live AudioStreamPlayback.
const Themes := preload("res://scripts/music_theme_catalog.gd")
const Genres := preload("res://scripts/music_genre_catalog.gd")
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
	check(ClassDB.class_exists("TesselStream"),"The native bridge is installed for profile rendering")
	if not ClassDB.class_exists("TesselStream"):
		quit(1)
		return
	var hashes: Dictionary = {}
	var report: Dictionary = {}
	for id: String in Themes.THEMES:
		var settings := Themes.native_settings(id)
		var fixture_seed := Themes.seed_for(id,12345)
		var left: AudioStream = ClassDB.instantiate("TesselStream")
		var right: AudioStream = ClassDB.instantiate("TesselStream")
		left.call("set_theme",fixture_seed,settings)
		right.call("set_theme",fixture_seed,settings)
		var frames := int(float(left.call("mix_rate"))*0.6)
		var first: PackedFloat32Array = left.call("render_offline",frames)
		var repeated: PackedFloat32Array = right.call("render_offline",frames)
		check(first.size()==frames*2,"%s native render fills its entire requested stereo block"%id)
		check(first==repeated,"%s identical seed and profile produce bit-identical native PCM"%id)
		var peak := 0.0
		var finite := true
		for value: float in first:
			finite=finite and is_finite(value)
			peak=maxf(peak,absf(value))
		check(finite and peak>0.001 and peak<1.0,"%s native profile is audible, finite and peak-limited"%id)
		check(is_equal_approx(float(left.call("bpm")),float(settings.bpm)),"%s preserves its resolved genre tempo through the native binding"%id)
		var fixture_hash := first.to_byte_array().hex_encode().sha256_text()
		check(not hashes.has(fixture_hash),"%s has a distinct synthesized opening"%id)
		hashes[fixture_hash]=true
		report[id]={"seed":fixture_seed,"samples":frames,"peak":peak,"sha256":fixture_hash,"mode":settings.scale,"normalization_db":settings.normalization_db}
		for genre: String in Genres.GENRES:
			var genre_settings := Themes.native_settings(id,{},genre)
			left.call("set_theme",fixture_seed,genre_settings)
			right.call("set_theme",fixture_seed,genre_settings)
			left.call("request_intensity_at_bar",3,0)
			right.call("request_intensity_at_bar",3,0)
			first=left.call("render_offline",frames)
			repeated=right.call("render_offline",frames)
			check(first==repeated,"%s/%s combat groove is bit-identical for the same profile and seed"%[id,genre])
			peak=0.0
			finite=true
			for value: float in first:
				finite=finite and is_finite(value)
				peak=maxf(peak,absf(value))
			check(finite and peak>0.001 and peak<1.0,"%s/%s combat output stays audible, finite and limited"%[id,genre])
			var metadata: Dictionary = left.call("metadata")
			check(int(metadata.get("genre",-1))==int(genre_settings.genre) and int(metadata.get("intensity",-1))==3 and is_equal_approx(float(left.call("bpm")),float(genre_settings.bpm)),"%s/%s native bridge actually renders the selected combat bank, genre and tempo"%[id,genre])
			report[id+"|"+genre]={"seed":fixture_seed,"samples":frames,"peak":peak,"sha256":first.to_byte_array().hex_encode().sha256_text(),"genre":genre_settings.genre,"bpm":genre_settings.bpm,"normalization_db":genre_settings.normalization_db}
	DirAccess.make_dir_recursive_absolute("res://artifacts/live-music")
	var file := FileAccess.open("res://artifacts/live-music/native-profiles-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"profiles":report},"\t"))
	file.close()
	print("LIVE MUSIC NATIVE PROFILES: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
