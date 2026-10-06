class_name UserDataMigration
extends Node
## Place before Localization in [autoload] when the project title changes.
## Existing saves stay untouched; only named, missing files are imported.
const LEGACY_TITLES := ["LETZTE SCHICHT"]
const FILES := [
	"language.cfg", "audio.cfg", "camera.cfg", "display.cfg", "violence.cfg",
	"voice.cfg", "microphone.cfg", "achievements.cfg", "crew_roster.cfg",
	"campaign_v1.json", "campaign_v1.json.bak",
]
const MAX_BYTES := 262144

func _enter_tree() -> void:
	if Engine.is_editor_hint() or "--no-profile-save" in OS.get_cmdline_user_args(): return
	var destination := OS.get_user_data_dir().simplify_path()
	for old_title: String in LEGACY_TITLES:
		var source := destination.get_base_dir().path_join(old_title)
		if source == destination: continue
		var result := copy_missing(source, destination)
		if not result.copied.is_empty():
			print("User data migration: copied ", result.copied.size(), " missing settings/save files.")

static func copy_missing(source: String, destination: String) -> Dictionary:
	var result := {"copied":[], "skipped":[], "errors":[]}
	source = ProjectSettings.globalize_path(source).simplify_path()
	destination = ProjectSettings.globalize_path(destination).simplify_path()
	if source == destination or not DirAccess.dir_exists_absolute(source): return result
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		result.errors.append("destination")
		return result
	var directory := DirAccess.open(source)
	var target_directory := DirAccess.open(destination)
	if directory == null or target_directory == null:
		result.errors.append("directory")
		return result
	# A checkpoint and its recovery copy belong together. Never mix a legacy
	# checkpoint with an already-created save in the new directory.
	var has_campaign := FileAccess.file_exists(destination.path_join("campaign_v1.json")) or FileAccess.file_exists(destination.path_join("campaign_v1.json.bak"))
	for filename: String in FILES:
		var input_path := source.path_join(filename)
		var output_path := destination.path_join(filename)
		if not FileAccess.file_exists(input_path): continue
		if FileAccess.file_exists(output_path) or directory.is_link(filename) or target_directory.is_link(filename) or (has_campaign and filename.begins_with("campaign_v1.json")):
			result.skipped.append(filename)
			continue
		var input := FileAccess.open(input_path, FileAccess.READ)
		if input == null:
			result.errors.append(filename)
			continue
		var length := input.get_length()
		if length <= 0 or length > MAX_BYTES:
			input.close()
			result.skipped.append(filename)
			continue
		var bytes := input.get_buffer(length)
		input.close()
		var temporary := output_path + ".migration-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
		var output := FileAccess.open(temporary, FileAccess.WRITE)
		if output == null:
			result.errors.append(filename)
			continue
		output.store_buffer(bytes)
		output.flush()
		var written := output.get_error() == OK and output.get_length() == length
		output.close()
		# Recheck after writing: another startup may already have copied it.
		if not written or FileAccess.file_exists(output_path) or target_directory.is_link(filename):
			DirAccess.remove_absolute(temporary)
			result.skipped.append(filename)
			continue
		if DirAccess.rename_absolute(temporary, output_path) != OK:
			DirAccess.remove_absolute(temporary)
			result.errors.append(filename)
		else:
			result.copied.append(filename)
	return result
