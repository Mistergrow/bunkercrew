extends Node
## Loaded only as an isolated temporary autoload beside an unchanged export.
class RoutingProbe extends "res://scripts/network_session.gd":
	var packets: Array[PackedByteArray] = []
	func _send_encoded(data: PackedByteArray, _reliable: bool, _target_id: int = 0, _channel: int = -1) -> bool:
		packets.append(data)
		return true

func _ready() -> void: run.call_deferred()

func run() -> void:
	var campaign = load("res://scripts/campaign_state.gd")
	var protocol = load("res://scripts/network_protocol.gd")
	var state = campaign.new("user://disposable-compat.json", false)
	var began: bool = state.begin_new({"environment":"ash_foundry", "position":"left", "build_type":"bastion"}, ["mara", "branko"], 2)
	var checkpoint: Dictionary = state.checkpoint()
	var normal: bool = campaign.valid_checkpoint(checkpoint)
	checkpoint.expedition.garage_stock = {"steel":20000}
	var result := {"build":protocol.BUILD, "campaign_stock_limit":campaign.get_script_constant_map().get("MAX_STOCK_PER_KIND", -1), "stock_10000":campaign.valid_stock({"steel":10000}), "stock_10001":campaign.valid_stock({"steel":10001}), "stock_20000":campaign.valid_stock({"steel":20000}), "created_checkpoint":began, "normal_checkpoint_valid":normal, "aggregate_checkpoint_valid":campaign.valid_checkpoint(checkpoint)}
	var game = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	var room := RoutingProbe.new()
	game.add_child(room)
	room.game = game
	room.set_process(false)
	room.set_physics_process(false)
	room.active = true
	room.state = "connecting"
	room.relay_url = "ws://127.0.0.1:24999/ws"
	room._connected()
	var hello: Dictionary = protocol.decode(room.packets[0])
	result.hello_world_revision = hello.get("world_revision", 0)
	var target := OS.get_environment("BUNKERCREW_COMPAT_PACKET_DIR")
	if not target.is_empty():
		var file := FileAccess.open(target.path_join("hello.packet"), FileAccess.WRITE)
		file.store_buffer(room.packets[0])
	room.packets.clear()
	room.is_host = true
	room._authenticated = false
	room._peer_connected_id(82)
	# An old host sees the new guest's offered revision but cannot confirm it.
	hello.world_revision = 2
	hello.voice_member_keys = true
	room._packet_from(protocol.encode(hello), 82)
	result.new_hello_authenticated = room._peers[82]._authenticated
	for packet: PackedByteArray in room.packets:
		var decoded: Dictionary = protocol.decode(packet)
		if decoded.get("kind") == "welcome":
			result.welcome_world_revision = decoded.get("world_revision", 0)
			if not target.is_empty():
				var file := FileAccess.open(target.path_join("welcome.packet"), FileAccess.WRITE)
				file.store_buffer(packet)
	print("CAMPAIGN_BINARY_COMPAT ", JSON.stringify(result))
	room.leave()
	get_tree().paused = false
	var cleanup = load("res://tests/scene_cleanup.gd")
	var clean: bool = await cleanup.free_scene(game, get_tree())
	get_tree().quit(0 if clean else 1)
