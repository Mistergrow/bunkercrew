extends SceneTree
## Validate the delivered recordings through Godot's actual imported resources.
const Catalog := preload("res://scripts/story_dialogue_catalog.gd")
var checks := 0
var failures := 0

func _initialize(): run.call_deferred()

func check(ok: bool, label: String):
	checks += 1
	if ok: print("PASS ", label)
	else:
		failures += 1
		push_error(label)

func run():
	var locale := "de"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--locale="): locale = argument.trim_prefix("--locale=")
	if not LocaleText.set_locale(locale, false):
		push_error("Unsupported test locale")
		quit(1)
		return
	var files := 0
	var total_duration := 0.0
	var checksums: Dictionary = {}
	var speaker_anchors: Dictionary = {}
	var speaker_counts: Dictionary = {}
	var directory := Catalog.VOICE_ROOT + ("en/" if locale == "en" else "")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(directory + "lines.json"))
	var source = JSON.parse_string(FileAccess.get_file_as_string(directory + "source.json"))
	check(manifest is Dictionary and manifest.lines.size() == 85, "All eighty-five recordings have authored generation inputs")
	check(source is Dictionary and source.model_license == "Apache-2.0" and str(source.reference_audio).contains("synthetic fictional"), "Model provenance records the license and entirely synthetic voice anchors")
	for id: String in Catalog.LINES:
		for speaker: String in Catalog.SPEAKERS:
			var detail := Catalog.line(id, speaker)
			if detail.is_empty(): continue
			files += 1
			speaker_counts[speaker] = int(speaker_counts.get(speaker, 0)) + 1
			var resource = load(detail.voice_path)
			check(resource is AudioStreamWAV, detail.voice_path.get_file() + " imports as recorded PCM speech")
			if not resource is AudioStreamWAV: continue
			var stream: AudioStreamWAV = resource
			check(stream.mix_rate == 24000 and not stream.stereo and stream.format in [AudioStreamWAV.FORMAT_16_BITS, AudioStreamWAV.FORMAT_QOA] and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, id + " keeps mono 24kHz speech with no looping")
			check(stream.get_length() > .8 and stream.get_length() < 16 and stream.data.size() > 5000, id + " has a complete finite voiced recording")
			total_duration += stream.get_length()
			var file_name: String = detail.voice_path.get_file()
			check(source.files.has(file_name) and source.files[file_name].text == detail.text and source.files[file_name].speaker == speaker, id + " subtitle and exact recorded script agree")
			var digest := FileAccess.get_sha256(detail.voice_path)
			check(not digest.is_empty() and not checksums.has(digest) and str(source.files[file_name].sha256) == digest, file_name + " has unique audio and verified provenance")
			checksums[digest] = file_name
			if locale == "de" or speaker in ["nora", "levin", "selma", "oskar", "rika"]:
				var metadata: Dictionary = source.files[file_name]
				var anchor_file := "res://" + str(metadata.get("anchor_file", ""))
				var anchor_sha := str(metadata.get("anchor_sha256", ""))
				check(not anchor_sha.is_empty() and anchor_sha == FileAccess.get_sha256(anchor_file) and anchor_sha == str(speaker_anchors.get(speaker, anchor_sha)), speaker + " consistently uses its own verified synthetic voice anchor")
				speaker_anchors[speaker] = anchor_sha
	for speaker: String in Catalog.SPEAKERS:
		check(int(speaker_counts.get(speaker, 0)) == (29 if speaker == "san" else 7), speaker + " has a complete individual voice bank")
	check(files == 85 and total_duration > 200, "All eighty-five authored lines ship as complete recordings")
	check(speaker_anchors.values().size() == 9 if locale == "de" else speaker_anchors.values().size() == 5, "Every newly generated speaker has a separate anchor")
	var unique_anchors: Dictionary = {}
	for anchor_sha: String in speaker_anchors.values(): unique_anchors[anchor_sha] = true
	check(unique_anchors.size() == speaker_anchors.size(), "Characters never reuse another character's voice identity")
	print("Story voice assets (%s): %d/%d checks passed, %.2f seconds of recorded speech" % [locale, checks - failures, checks, total_duration])
	quit(1 if failures else 0)
