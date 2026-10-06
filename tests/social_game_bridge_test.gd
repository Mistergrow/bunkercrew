extends SceneTree
const Bridge := preload("res://scripts/social_game_bridge.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

class FakeHub extends Node:
	var display_name := "Mara"
	var updates: Array[Dictionary] = []
	func set_presence(data: Dictionary) -> void: updates.append(data.duplicate(true))

class FakeSession extends Node:
	var active := false
	var is_host := false
	var state := "offline"
	@warning_ignore("unused_private_class_variable")
	var _loading := false
	var max_players := 4
	var count := 1
	var room_code := "LAN-CODE"
	var direct_code := "DIRECT-INVITATION"
	var internet_code := ""
	var relay_url := ""
	@warning_ignore("unused_private_class_variable")
	var _relay_resume_token := "test-host-token"
	var names: Array[String] = []
	var name_available := true
	func connected_player_count() -> int: return count
	func set_display_name(value: String) -> bool:
		if not name_available: return false
		names.append(value)
		return true

class FakeHud extends Node:
	var scenario_options := {"environment": "abandoned_harbor"}

class FakeGame extends Node:
	var started := false
	var scenario_options := {"environment": "mountain_pass"}
	var network
	var social
	var hud

func _initialize() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	var game := FakeGame.new()
	game.network = FakeSession.new()
	game.social = FakeHub.new()
	game.hud = FakeHud.new()
	for node: Node in [game.network, game.social, game.hud]: game.add_child(node)
	root.add_child(game)
	var bridge := Bridge.new()
	bridge.game = game
	game.add_child(bridge)
	check(game.social.updates.size() == 1 and game.social.updates[0].status == "menu", "Opening the game publishes menu presence")
	check(game.social.updates[0].environment.is_empty() and not game.social.updates[0].joinable, "Menu browsing does not expose a join invitation")
	bridge.refresh()
	check(game.social.updates.size() == 1 and game.network.names == ["Mara"], "Unchanged presence and profile names are not repeatedly sent")
	game.network.active = true
	game.network.is_host = true
	game.network.state = "lobby"
	bridge.refresh()
	var data: Dictionary = game.social.updates.back()
	check(data.status == "lobby" and data.environment == "abandoned_harbor", "Lobby presence uses the actual selected mission")
	check(data.joinable and data.room_code == "DIRECT-INVITATION" and data.relay_url.is_empty(), "Direct invitations use the complete address code")
	game.network.internet_code = "PUBLIC-INVITATION"
	bridge.refresh()
	check(game.social.updates.back().room_code == "PUBLIC-INVITATION", "An available internet invitation takes precedence over LAN")
	game.network.relay_url = "wss://play.example.test/ws"
	bridge.refresh()
	data = game.social.updates.back()
	check(data.room_code == "LAN-CODE" and data.room_token == "test-host-token", "Relay readiness provides host authentication to the service")
	game.network.count = 4
	bridge.refresh()
	data = game.social.updates.back()
	check(not data.joinable and data.room_code.is_empty() and not data.has("room_token"), "A full room withdraws its invitation and private token")
	game.network.count = 1
	game.network._loading = true
	bridge.refresh()
	check(not bridge.presence().joinable, "Loading cannot advertise a joinable room")
	game.network._loading = false
	game.network.is_host = false
	bridge.refresh()
	check(not bridge.presence().joinable, "Guests cannot advertise another player's room")
	game.network.is_host = true
	game.started = true
	game.network.state = "playing"
	bridge.refresh()
	data = game.social.updates.back()
	check(data.status == "playing" and data.environment == "mountain_pass" and not data.joinable, "A running mission uses its actual map without advertising an open lobby")
	game.network.active = false
	bridge.refresh()
	check(bridge.presence().status == "playing", "Solo play remains visible to confirmed friends")
	game.social.display_name = "Ivo"
	game.network.name_available = false
	bridge.refresh()
	check(game.network.names == ["Mara"], "A temporarily unavailable game link does not acknowledge a nickname update")
	game.network.name_available = true
	bridge.refresh()
	check(game.network.names == ["Mara", "Ivo"], "A changed local nickname reaches the session exactly once")
	game.started = false
	bridge.refresh()
	check(game.social.updates.back().status == "menu", "Returning to the menu updates the presence")
	game.queue_free()
	await process_frame
	var actual = load("res://scenes/main.tscn").instantiate()
	root.add_child(actual)
	actual.start_scenario(1, {"environment":"ash_foundry", "build_type":"workshop", "position":"left"})
	check(is_instance_valid(actual.social_bridge) and actual.social_bridge.get_parent() == actual, "Starting an actual scenario retains the session presence bridge")
	actual.social_bridge.refresh()
	check(actual.social == root.get_node("SocialHub") and actual.social._presence.status == "playing", "Actual scenario publishes playing through the durable autoload")
	check(actual.social_bridge.is_processing() and actual.social_bridge.process_mode == Node.PROCESS_MODE_ALWAYS, "Presence continues while match menus pause the simulation")
	await Cleanup.free_scene(actual, self)
	print("SOCIAL GAME BRIDGE: %d/%d checks passed" % [checks-failures, checks])
	quit(1 if failures else 0)
