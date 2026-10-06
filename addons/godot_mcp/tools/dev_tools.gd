@tool
extends "res://addons/godot_mcp/tools/base_tools.gd"

## Developer power-tools for the Godot MCP server.
##
## - screenshot: capture the editor (whole window or a scene viewport) to a PNG so
##   the assistant can actually SEE the current state and iterate visually.
## - eval: run an arbitrary GDScript snippet in the editor context and return its
##   result — a general-purpose escape hatch for inspection and automation
##   (ProjectSettings, EditorInterface, the edited scene tree, files, resources …).


func get_tools() -> Array[Dictionary]:
	return [
		{
			"name": "screenshot",
			"description": """SCREENSHOT: Render the editor (or a scene viewport) to a PNG and return its path.

TARGETS:
- editor: the whole editor window (default)
- viewport_2d: the 2D scene editor viewport (current scene)
- viewport_3d: the 3D scene editor viewport

The saved file path is returned; read it back to view the image.

EXAMPLES:
- Whole editor: {"action": "screenshot"}
- 2D scene: {"action": "screenshot", "target": "viewport_2d"}
- Custom path: {"action": "screenshot", "path": "res://out/mcp/look.png"}""",
			"inputSchema": {
				"type": "object",
				"properties": {
					"action": {"type": "string", "enum": ["screenshot"]},
					"target": {
						"type": "string",
						"enum": ["editor", "viewport_2d", "viewport_3d"],
						"description": "What to capture (default editor)"
					},
					"path": {"type": "string", "description": "Output PNG path (default res://out/mcp/mcp_shot.png)"}
				},
				"required": ["action"]
			}
		},
		{
			"name": "eval",
			"description": """EVAL: Run a GDScript snippet in the editor and return its result.

The code is the BODY of a function — use `return <value>` to get output back.
It runs in @tool context: EditorInterface, ProjectSettings, ResourceLoader,
FileAccess, and the edited scene (EditorInterface.get_edited_scene_root()) are
all available. Autoloads are NOT running in the editor. print() goes to the
Godot console. Dictionaries/Arrays are returned as JSON.

EXAMPLES:
- {"action": "eval", "code": "return ProjectSettings.get_setting('application/config/name')"}
- {"action": "eval", "code": "var r = EditorInterface.get_edited_scene_root()\\nreturn r.name if r else 'none'"}
- {"action": "eval", "code": "return DirAccess.get_files_at('res://data')"}""",
			"inputSchema": {
				"type": "object",
				"properties": {
					"action": {"type": "string", "enum": ["eval"]},
					"code": {"type": "string", "description": "GDScript function body; use return to yield a value"}
				},
				"required": ["action", "code"]
			}
		},
		{
			"name": "log",
			"description": """LOG: Return the tail of the Godot editor/game console log file.

Lets the assistant see print() output, warnings and errors that scrolled by in
the Godot console — the last visibility gap next to screenshot + eval.

EXAMPLES:
- Last 60 lines: {"action": "log"}
- Last 200 lines: {"action": "log", "lines": 200}""",
			"inputSchema": {
				"type": "object",
				"properties": {
					"action": {"type": "string", "enum": ["log"]},
					"lines": {"type": "integer", "description": "How many trailing lines (default 60)"}
				},
				"required": ["action"]
			}
		},
		{
			"name": "render",
			"description": """RENDER: Render a scene AT GAME RUNTIME (autoloads active) to a PNG and return its path.

Spawns a short-lived Godot subprocess running tests/preview_shot.gd with profile
saving disabled. Captures the scene's initial runtime state, including its menus.
Requires a graphical display and may briefly flash a render window.
Read the returned PNG to view it.

EXAMPLES:
- Current scene: {"action": "render"}
- Main game scene: {"action": "render", "scene": "res://scenes/main.tscn"}
- Custom output: {"action": "render", "out": "artifacts/mcp/look.png"}""",
			"inputSchema": {
				"type": "object",
				"properties": {
					"action": {"type": "string", "enum": ["render"]},
					"scene": {"type": "string", "description": "Scene path (default: currently edited scene)"},
					"out": {"type": "string", "description": "Output PNG path under res:// (default artifacts/mcp/mcp_render.png)"}
				},
				"required": ["action"]
			}
		},
		{
			"name": "scene_tree",
			"description": """SCENE_TREE: Compact text dump of the currently edited scene (name, type, script, children).

Faster than many single queries when you need an overview of the open scene.

EXAMPLES:
- {"action": "scene_tree"}
- Limit depth: {"action": "scene_tree", "depth": 2}""",
			"inputSchema": {
				"type": "object",
				"properties": {
					"action": {"type": "string", "enum": ["scene_tree"]},
					"depth": {"type": "integer", "description": "Max depth (default unlimited)"}
				},
				"required": ["action"]
			}
		},
		{
			"name": "reload",
			"description": """RELOAD: Rescan the project filesystem (import new/changed assets) and optionally reload the open scene from disk.

Use after adding assets (e.g. ambient audio, PNGs) or editing data files so the
editor picks them up. reload_scene:true re-reads the current scene from disk —
DISCARDS unsaved changes, so only with intent.

EXAMPLES:
- Rescan/import: {"action": "reload"}
- Also reload open scene: {"action": "reload", "reload_scene": true}""",
			"inputSchema": {
				"type": "object",
				"properties": {
					"action": {"type": "string", "enum": ["reload"]},
					"reload_scene": {"type": "boolean", "description": "Reload the open scene from disk (loses unsaved edits)"}
				},
				"required": ["action"]
			}
		}
	]


func execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"screenshot":
			return _screenshot(args)
		"eval":
			return _eval(args)
		"log":
			return _log(args)
		"render":
			return _render(args)
		"scene_tree":
			return _scene_tree(args)
		"reload":
			return _reload(args)
		_:
			return _error("Unknown tool: %s" % tool_name)


func _screenshot(args: Dictionary) -> Dictionary:
	var target := str(args.get("target", "editor"))
	var vp: Viewport = null
	match target:
		"viewport_2d":
			vp = EditorInterface.get_editor_viewport_2d()
		"viewport_3d":
			vp = EditorInterface.get_editor_viewport_3d(0)
		_:
			vp = EditorInterface.get_base_control().get_viewport()
	if vp == null:
		return _error("No viewport available for target '%s'" % target)
	var tex := vp.get_texture()
	if tex == null:
		return _error("Viewport has no texture (nothing rendered yet)")
	var img := tex.get_image()
	if img == null:
		return _error("Failed to grab viewport image")
	var path := str(args.get("path", "res://out/mcp/mcp_shot.png"))
	if not path.ends_with(".png"):
		path += ".png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := img.save_png(path)
	if err != OK:
		return _error("save_png failed: %s" % error_string(err))
	return _success({
		"path": path,
		"absolute_path": ProjectSettings.globalize_path(path),
		"width": img.get_width(),
		"height": img.get_height(),
		"target": target,
	}, "Screenshot saved — read the file to view it.")


func _eval(args: Dictionary) -> Dictionary:
	var code := str(args.get("code", ""))
	if code.strip_edges().is_empty():
		return _error("Empty code")
	# Wrap as the body of run() with one level of indentation.
	var body := ""
	for line in code.split("\n"):
		body += "\t" + line + "\n"
	var src := "@tool\nextends RefCounted\nfunc run():\n" + body
	var script := GDScript.new()
	script.source_code = src
	var err := script.reload()
	if err != OK:
		return _error("Compile error (%s). Remember: the code is a function body; use 'return'." % error_string(err))
	var obj: Object = script.new()
	if obj == null or not obj.has_method("run"):
		return _error("Could not instantiate eval script")
	var result: Variant = obj.call("run")
	return _success({"result": _stringify(result)})


func _log(args: Dictionary) -> Dictionary:
	var n := int(args.get("lines", 60))
	var path := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	if not FileAccess.file_exists(path):
		return _error("No log file at %s (file logging may be off)." % path)
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var start := maxi(0, lines.size() - n)
	var tail := "\n".join(lines.slice(start))
	return _success({"path": path, "total_lines": lines.size(), "tail": tail})


func _render(args: Dictionary) -> Dictionary:
	var scene := str(args.get("scene", ""))
	if scene == "":
		var root := EditorInterface.get_edited_scene_root()
		if root == null or root.scene_file_path == "":
			return _error("No scene given and no saved scene is open.")
		scene = root.scene_file_path
	var out_rel := str(args.get("out", "artifacts/mcp/mcp_render.png"))
	out_rel = out_rel.trim_prefix("res://")
	if out_rel.is_empty() or out_rel.is_absolute_path() or ".." in out_rel.split("/") or out_rel.get_extension().to_lower() != "png":
		return _error("Output must be a PNG path inside the project.")
	var godot := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://").trim_suffix("/")
	# Pass paths as arguments so spaces and quotes remain literal.
	var command_args := PackedStringArray([
		"DSS_SHOT_SCENE=" + scene, "DSS_SHOT_OUT=" + out_rel,
		"timeout", "90", godot, "--path", proj,
		"-s", "res://tests/preview_shot.gd", "--", "--no-profile-save",
	])
	var output: Array = []
	var exit := OS.execute("env", command_args, output, true)
	var log_tail := ""
	if not output.is_empty():
		var lines: PackedStringArray = str(output[0]).split("\n")
		log_tail = "\n".join(lines.slice(maxi(0, lines.size() - 8)))
	var out_path := "res://" + out_rel
	var ok := FileAccess.file_exists(ProjectSettings.globalize_path(out_path))
	if exit != 0 or not ok:
		return _error("Render failed (exit %d). Tail:\n%s" % [exit, log_tail])
	return _success({
		"path": out_path,
		"absolute_path": ProjectSettings.globalize_path(out_path),
		"scene": scene, "exit": exit,
		"log_tail": log_tail,
	}, "Rendered — read the file to view it.")


func _scene_tree(args: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _error("No scene is open in the editor.")
	var max_depth := int(args.get("depth", 99))
	var lines: Array[String] = []
	_dump_node(root, 0, max_depth, lines)
	return _success({"scene": root.scene_file_path, "nodes": lines.size(), "tree": "\n".join(lines)})


func _dump_node(node: Node, depth: int, max_depth: int, out: Array[String]) -> void:
	var indent := "  ".repeat(depth)
	var scr := node.get_script() as Script
	var script_str := "  <%s>" % scr.resource_path.get_file() if scr != null else ""
	var vis := "" if not (node is CanvasItem) or node.visible else "  [hidden]"
	out.append("%s%s (%s)%s%s" % [indent, node.name, node.get_class(), script_str, vis])
	if depth >= max_depth:
		return
	for child in node.get_children():
		_dump_node(child, depth + 1, max_depth, out)


func _reload(args: Dictionary) -> Dictionary:
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()
	var reloaded_scene := ""
	if bool(args.get("reload_scene", false)):
		var root := EditorInterface.get_edited_scene_root()
		if root != null and root.scene_file_path != "":
			reloaded_scene = root.scene_file_path
			EditorInterface.reload_scene_from_path(reloaded_scene)
	return _success({
		"scanned": fs != null,
		"reloaded_scene": reloaded_scene,
	}, "Filesystem rescanned." + (" Scene reloaded." if reloaded_scene != "" else ""))


func _stringify(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Dictionary or value is Array:
		return JSON.stringify(value, "  ")
	return str(value)
