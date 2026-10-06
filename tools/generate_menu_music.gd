extends SceneTree
## Offline original composition through Bunkercrew's licensed Tessel engine.
const Catalog := preload("res://scripts/menu_music_catalog.gd")
const DESTINATION := "res://artifacts/menu-rave/source"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ClassDB.class_exists("TesselStream"):
		push_error("The Bunkercrew native music extension is required for authoring.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
	var stream: AudioStream = ClassDB.instantiate("TesselStream")
	stream.call("set_theme", Catalog.SEED, Catalog.NATIVE_THEME)
	var rate := int(stream.call("mix_rate"))
	# Headless Godot may mix at 44100 Hz. The finishing generator resamples
	# PCM and the extracted event timestamps together to the 48000 Hz master.
	var pcm: PackedFloat32Array = stream.call("render_offline", roundi(Catalog.SECONDS * rate))
	var events: Array[Dictionary] = []
	while true:
		var batch: Array = stream.call("poll_events", 1024)
		if batch.is_empty(): break
		for event: Dictionary in batch:
			if str(event.get("kind", "")) == "hit" and int(event.get("track", -1)) in [0, Catalog.SECONDARY_TRACK]:
				events.append(event)
	var metadata: Dictionary = stream.call("metadata")
	var kicks := events.filter(func(event: Dictionary): return int(event.track) == 0)
	var secondary := events.filter(func(event: Dictionary): return int(event.track) == Catalog.SECONDARY_TRACK)
	if int(metadata.get("dropped_events", 0)) != 0 or pcm.size() != roundi(Catalog.SECONDS * rate) * 2 or kicks.size() != Catalog.BARS * 4 or secondary.size() != Catalog.BARS * 4:
		push_error("Menu rendering lost PCM or native kick markers.")
		quit(1)
		return
	var file := FileAccess.open(DESTINATION + "/native.f32", FileAccess.WRITE)
	file.store_buffer(pcm.to_byte_array())
	file = FileAccess.open(DESTINATION + "/native.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"title": Catalog.TITLE, "rate": rate, "bpm": Catalog.BPM, "seed": Catalog.SEED, "settings": Catalog.NATIVE_THEME, "events": events, "metadata": metadata}, "\t"))
	print("MENU MUSIC NATIVE MASTER: %d stereo frames, %d actual kicks and %d offbeat bass hits, no lost events" % [int(pcm.size() / 2.0), kicks.size(), secondary.size()])
	quit(0)
