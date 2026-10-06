extends SceneTree
## A freed session cannot keep a composer active or break automatic rebinding.
const ChatPanel := preload("res://scripts/chat_panel.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class FixtureSession extends Node:
	@warning_ignore("unused_signal")
	signal changed
	@warning_ignore("unused_signal")
	signal chat_changed
	@warning_ignore("unused_signal")
	signal chat_received(row: Dictionary)
	@warning_ignore("unused_signal")
	signal chat_send_completed(text: String, accepted: bool)
	var chat_draft := ""
	var chat_error := ""
	var chat_pending := false
	var chat_history: Array = []
	func chat_available() -> bool: return true

class FixtureHud extends Node:
	var overlay := ""
	func has_session_action() -> bool: return false
	func screen_rect() -> Rect2: return Rect2(0, 0, 1440, 900)

class FixtureGame extends Node:
	var network: Node

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _run() -> void:
	var game := FixtureGame.new()
	var hud := FixtureHud.new()
	var session := FixtureSession.new()
	game.network = session
	game.add_child(hud)
	game.add_child(session)
	root.add_child(game)
	var panel := ChatPanel.new()
	panel.game = game
	panel.hud = hud
	game.add_child(panel)
	panel.open()
	panel.input_field.text = "Old session draft"
	panel._last_available = true
	session.free()
	panel._process(0.0)
	check(not panel.composing and not panel.editor.visible, "A freed session closes its composer and releases gameplay input")
	check(not panel._pending(), "No stale pending submission survives a destroyed session")
	var replacement := FixtureSession.new()
	replacement.chat_draft = "New session draft"
	game.add_child(replacement)
	game.network = replacement
	panel._process(0.0)
	check(panel.network == replacement and panel.input_field.text == "New session draft", "Automatic rebinding restores the new session's own draft")
	panel.open()
	panel.input_field.text = "Latest draft"
	replacement.free()
	var second_replacement := FixtureSession.new()
	second_replacement.chat_draft = "Separate draft"
	game.add_child(second_replacement)
	game.network = second_replacement
	panel._process(0.0)
	check(panel.network == second_replacement and not panel.composing and panel.input_field.text == "Separate draft", "Replacement while composing cannot write into or access a freed session")
	await Cleanup.free_scene(game, self)
	print("CHAT SESSION LIFECYCLE: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
