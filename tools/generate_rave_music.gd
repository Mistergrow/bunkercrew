extends SceneTree
## Fixed original scores through the licensed native engine. Version-one menu
## recordings remain byte-for-byte preserved during a refreshed world render.
const Catalog := preload("res://scripts/rave_music_catalog.gd")
const DESTINATION := "res://artifacts/music-beat-refresh/source"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ClassDB.class_exists("TesselStream"):
		push_error("The Bunkercrew native music extension is required for authoring.")
		quit(1)
		return
	var selected := ""
	var refresh_only := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): selected = argument.trim_prefix("--only=")
		if argument == "--refresh": refresh_only = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
	for id: String in Catalog.TRACKS:
		if not selected.is_empty() and id != selected: continue
		var track: Dictionary = Catalog.track(id)
		if refresh_only and int(track.version) < 2: continue
		var arrangements: Array[String] = ["combat"]
		if track.role != "menu": arrangements.assign(["calm", "combat"])
		for arrangement in arrangements:
			var settings: Dictionary = Catalog.native_settings_for_track(id)
			settings.initial_intensity = 1 if arrangement == "calm" else 2
			if int(settings.get("score_form", 0)) == 1: settings.initial_intensity = 0
			var stream: AudioStream = ClassDB.instantiate("TesselStream")
			stream.call("set_theme", int(track.seed), settings)
			var rate := int(stream.call("mix_rate"))
			var frames := roundi(float(track.seconds) * rate)
			if frames > 48000 * 60:
				push_error("An authored master exceeds the native offline buffer limit.")
				quit(1)
				return
			var pcm: PackedFloat32Array = stream.call("render_offline", frames)
			var events: Array[Dictionary] = []
			while true:
				var batch: Array = stream.call("poll_events", 1024)
				if batch.is_empty(): break
				for event: Dictionary in batch:
					if str(event.get("kind", "")) == "hit" and int(event.get("track", -1)) in [0, 8]: events.append(event)
			var metadata: Dictionary = stream.call("metadata")
			var kicks := events.filter(func(event: Dictionary): return int(event.track) == 0)
			var bass := events.filter(func(event: Dictionary): return int(event.track) == 8)
			var full_groove := int(settings.get("score_form", 0)) == 0
			var valid_counts := kicks.size() == Catalog.BARS * 4 and bass.size() == Catalog.BARS * 4 if full_groove else kicks.size() == 98 and bass.size() == 100
			if int(metadata.get("dropped_events", 0)) != 0 or pcm.size() != frames * 2 or not valid_counts:
				push_error("Rendering lost PCM or actual native markers: " + id + " " + arrangement)
				quit(1)
				return
			var filename := DESTINATION + "/" + id + "-" + arrangement
			FileAccess.open(filename + ".f32", FileAccess.WRITE).store_buffer(pcm.to_byte_array())
			var form: Array = []
			if not full_groove:
				for phrase in 4:
					form.append({"bar":phrase * 8,"intensity":[0, 1, 2, 1][phrase],"section":["intro", "build", "drop", "relief"][phrase]})
			FileAccess.open(filename + ".json", FileAccess.WRITE).store_string(JSON.stringify({"id":id,"title":"Bunkercrew · " + str(track.title),"version":track.version,"asset":track.asset if arrangement == "combat" else track.calm_asset,"role":track.role,"arrangement":arrangement,"rate":rate,"bpm":track.bpm,"seconds":track.seconds,"target_frames":track.frames,"seed":track.seed,"settings":settings,"form":form,"events":events,"metadata":metadata}, "\t"))
			print("RAVE NATIVE %s v%d %s: %d frames, %d real kicks + %d real bass notes, no lost events" % [id, track.version, arrangement, frames, kicks.size(), bass.size()])
	quit(0)
