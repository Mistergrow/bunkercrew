class_name ContentPackPreflight
extends SceneTree
const Content := preload("res://scripts/content_registry.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var errors := Content.diagnostics()
	var report := {"valid":errors.is_empty(), "content_fingerprint":Content.fingerprint(), "packs":Content.packs(), "errors":errors, "resources":Content.enumerated_resources()}
	print(JSON.stringify(report))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--content-report="):
			var file := FileAccess.open(argument.trim_prefix("--content-report="), FileAccess.WRITE)
			if file == null:
				printerr("Cannot write content preflight report")
				quit(1)
				return
			file.store_string(JSON.stringify(report, "  "))
	quit(0 if errors.is_empty() else 1)
