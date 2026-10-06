extends SceneTree
## Refresh authored generation inputs without duplicating the dialogue strings.

func _initialize() -> void:
	var locale := "de"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--locale="): locale = argument.trim_prefix("--locale=")
	if not LocaleText.set_locale(locale, false):
		push_error("Unsupported voice locale: " + locale)
		quit(1)
		return
	var catalog := preload("res://scripts/story_dialogue_catalog.gd")
	var lines: Array[Dictionary] = []
	for id: String in catalog.LINES:
		for speaker_id: String in catalog.SPEAKERS:
			var detail := catalog.line(id, speaker_id)
			if detail.is_empty(): continue
			if locale == "en" and detail.text == detail.source_text:
				push_error("Missing English dialogue translation: " + id + "/" + speaker_id)
				quit(1)
				return
			var entry := {"id":id,"speaker":speaker_id,"text":detail.text,"file":speaker_id+"_"+id+".wav"}
			if locale != "de": entry.source_text = detail.source_text
			lines.append(entry)
	var directory: String = catalog.VOICE_ROOT + ("en/" if locale == "en" else "")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var output := FileAccess.open(directory + "lines.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"language":"de-DE" if locale == "de" else "en-US","lines":lines}, "\t") + "\n")
	print("Exported ", lines.size(), " authored ", locale, " voice lines")
	quit()
