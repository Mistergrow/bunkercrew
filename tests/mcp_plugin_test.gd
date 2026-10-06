@tool
extends SceneTree
## Isolated histories and protocol envelopes; never starts the MCP listener.
class ToolProbe extends "res://addons/godot_mcp/tools/editor_tools.gd":
	var histories: Dictionary = {}
	func _get_undo_history(context: String = "local") -> UndoRedo:
		return histories.get(context)
class ValueProbe extends RefCounted:
	var value := 0

var checks := 0
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func run() -> void:
	var base = preload("res://addons/godot_mcp/tools/base_tools.gd").new()
	check(not Engine.is_editor_hint() and base._get_editor_interface() == null, "Normal headless runtime handles the missing editor singleton")
	check(base._get_edited_scene_root() == null and base._get_selection() == null and base._get_filesystem() == null, "Editor-only helpers safely report unavailable in runtime")
	var tool := ToolProbe.new()
	var local_history := UndoRedo.new()
	var global_history := UndoRedo.new()
	tool.histories = {"local":local_history, "global":global_history}
	var local_value := ValueProbe.new()
	var global_value := ValueProbe.new()
	for entry in [[local_history, local_value, 12], [global_history, global_value, 23]]:
		entry[0].create_action("Audit fixture")
		entry[0].add_do_property(entry[1], "value", entry[2])
		entry[0].add_undo_property(entry[1], "value", 0)
		entry[0].commit_action()
	check(local_value.value == 12 and global_value.value == 23, "Separate test histories contain independent changes")
	check(tool.execute("undo_redo", {"action":"undo"}).success and local_value.value == 0 and global_value.value == 23, "Default undo affects only the local history")
	check(tool.execute("undo_redo", {"action":"undo", "context":"global"}).success and global_value.value == 0, "Explicit global undo selects its own history")
	check(not tool.execute("undo_redo", {"action":"undo"}).success, "An empty undo stack returns an error without changing other histories")
	check(tool.execute("undo_redo", {"action":"redo", "context":"global"}).success and global_value.value == 23 and local_value.value == 0, "Global redo leaves local history untouched")
	check(tool.execute("undo_redo", {"action":"redo"}).success and local_value.value == 12, "Local redo restores its actual property")
	check(not tool.execute("undo_redo", {"action":"redo"}).success, "An empty redo stack returns an error")
	for action in ["get_info", "undo", "redo"]:
		check(not tool.execute("undo_redo", {"action":action, "context":"invalid"}).success, "Unknown history context is rejected before access")
	tool.histories.clear()
	check(not tool.execute("undo_redo", {"action":"undo"}).success and not tool.execute("undo_redo", {"action":"redo"}).success, "Missing history cannot produce a successful undo/redo")
	local_history.clear_history()
	global_history.clear_history()
	local_history.free()
	global_history.free()
	var server = preload("res://addons/godot_mcp/mcp_server.gd").new()
	for payload in [{"success":true, "data":{"value":7}}, {"success":false, "error":"Unavailable"}, {}]:
		var response: Dictionary = server._create_tool_response(payload, 42)
		check(response.id == 42 and response.jsonrpc == "2.0" and not response.has("error"), "Tool response retains its valid JSON-RPC envelope and request ID")
		check(response.result.isError == (payload.get("success", false) != true), "MCP isError accurately reflects tool failure, including an empty runtime result")
		check(JSON.parse_string(response.result.content[0].text) == JSON.parse_string(JSON.stringify(payload)), "Structured tool details remain intact under standard JSON number conversion")
	check(not server.is_running(), "Protocol checks never bind a socket or disturb the editor listener")
	server.free()
	print("MCP PLUGIN: %d/%d checks passed" % [checks-failures, checks])
	quit(1 if failures else 0)
