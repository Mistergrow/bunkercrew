extends SceneTree
## Runtime screenshots for the MCP render tool. Run with -- --no-profile-save.
## DSS_SHOT_SCENE selects a scene; DSS_SHOT_OUT selects a PNG under res://.

const SCENE_CLEANUP = preload("res://tests/scene_cleanup.gd")
var _scene: Node


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Runtime screenshots require a graphical display.")
		return
	var scene_path := OS.get_environment("DSS_SHOT_SCENE")
	if scene_path.is_empty():
		scene_path = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
		_fail("Scene does not exist: %s" % scene_path)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null or not packed.can_instantiate():
		_fail("Could not load a scene from: %s" % scene_path)
		return
	var output := OS.get_environment("DSS_SHOT_OUT")
	if output.is_empty():
		output = "artifacts/mcp/mcp_render.png"
	output = output.replace("\\", "/").trim_prefix("res://")
	if output.is_absolute_path() or ":" in output or ".." in output.split("/") or output.get_extension().to_lower() != "png":
		_fail("Output must be a PNG path inside the project: %s" % output)
		return
	var absolute_output := ProjectSettings.globalize_path("res://" + output)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
	if directory_error != OK:
		_fail("Could not create output directory: %s" % error_string(directory_error))
		return
	_scene = packed.instantiate()
	if _scene == null:
		_fail("Could not instantiate scene: %s" % scene_path)
		return
	root.add_child(_scene)
	current_scene = _scene
	if _scene is Control:
		(_scene as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var texture := root.get_texture()
	var image := texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		push_error("MCP preview: The viewport produced no image.")
		await _finish(1)
		return
	var save_error := image.save_png(absolute_output)
	if save_error != OK:
		push_error("MCP preview: Could not save %s: %s" % [absolute_output, error_string(save_error)])
		await _finish(1)
		return
	print("MCP preview: %s (%dx%d), scene %s" % [absolute_output, image.get_width(), image.get_height(), scene_path])
	await _finish(0)


func _finish(exit_code: int) -> void:
	paused = false
	if is_instance_valid(_scene):
		if not await SCENE_CLEANUP.free_scene(_scene, self):
			exit_code = 1
		_scene = null
	quit(exit_code)


func _fail(message: String) -> void:
	push_error("MCP preview: " + message)
	quit(1)
