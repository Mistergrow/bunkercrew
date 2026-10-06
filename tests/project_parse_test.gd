extends SceneTree
## Load every project script without starting scenes, plugins or network rooms.
## Run with --debug to include Godot's source diagnostics in the captured log.
var checked := 0
var failed: Array[String] = []
var unused_diagnostics := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	unused_diagnostics = "--unused-diagnostics" in OS.get_cmdline_user_args()
	if unused_diagnostics:
		# Session-only settings: never rewrite the game's project or user profile.
		ProjectSettings.set_setting("debug/gdscript/warnings/enable",true)
		ProjectSettings.set_setting("debug/gdscript/warnings/exclude_addons",false)
		for warning: String in ["unused_variable","unused_parameter","unused_private_class_variable","unassigned_variable","unassigned_variable_op_assign","shadowed_variable","shadowed_variable_base_class","shadowed_global_identifier"]:
			ProjectSettings.set_setting("debug/gdscript/warnings/"+warning,1)
	for directory in ["res://scripts","res://addons","res://tests","res://tools"]:
		_scan(directory)
	print("PROJECT PARSE: %d scripts, %d failures" % [checked,failed.size()])
	for script_path in failed:
		push_error("Could not load script: "+script_path)
	quit(0 if failed.is_empty() else 1)

func _scan(directory: String) -> void:
	for filename in DirAccess.get_files_at(directory):
		if filename.get_extension()!="gd":
			continue
		var script_path := directory.path_join(filename)
		if script_path==get_script().resource_path:
			continue
		checked += 1
		var parsed := load(script_path) as GDScript
		if parsed==null or not parsed.can_instantiate() or (unused_diagnostics and parsed.reload(true)!=OK):
			failed.append(script_path)
	for subdirectory in DirAccess.get_directories_at(directory):
		_scan(directory.path_join(subdirectory))
