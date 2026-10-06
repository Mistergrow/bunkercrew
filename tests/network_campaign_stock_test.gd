extends SceneTree
## Aggregate stock travels separately from bounded individual entity counts.
const Protocol := preload("res://scripts/network_protocol.gd")
const Messages := preload("res://scripts/network_messages.gd")
const Schema := preload("res://scripts/network_replication_schema.gd")
const World := preload("res://scripts/network_world.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.start_scenario(2, {"environment":"sector07", "build_type":"workshop", "position":"left"})
	var world := World.new()
	world.bind(game)
	var baseline: Dictionary = world.capture()
	check(not baseline.expedition.is_empty(), "Actual defense supplies an authoritative campaign checkpoint")
	check(CampaignState.MAX_STOCK_PER_KIND == 9007199254740991, "Aggregate bound preserves the exact JSON integer range")
	for amount: int in [100002, 1000000001, CampaignState.MAX_STOCK_PER_KIND]:
		var packet: Dictionary = baseline.duplicate(true)
		packet.expedition.checkpoint.expedition.garage_stock = {"steel":amount}
		var payload := {"checkpoint":packet.expedition.checkpoint, "mode":"defense", "options":packet.options}
		var start := {"kind":"start", "options":packet.options, "characters":payload.checkpoint.character_ids, "story":false, "reset":true, "generation":1, "count":2, "capacity":4, "slots":[1, 2], "expedition":payload}
		var decoded := Protocol.decode(Protocol.encode(start))
		check(not decoded.is_empty() and decoded.expedition.checkpoint.expedition.garage_stock.steel is int and decoded.expedition.checkpoint.expedition.garage_stock.steel == amount, "%d aggregate units retain their exact integer on the real control codec" % amount)
		check(Messages.valid(decoded, false), "%d aggregate units pass the separate start/checkpoint validator" % amount)
		var envelope := {"kind":"snapshot", "generation":1, "seq":1, "paused":false, "world":packet}
		decoded = Protocol.decode(Protocol.encode(envelope))
		check(Messages.valid(decoded, false), "%d aggregate units pass the separate snapshot envelope validator" % amount)
		check(world.apply(decoded.world), "%d aggregate units apply to the actual defense replica: %s" % [amount, world.last_error])
		check(game.campaign.expedition.garage_stock.steel == amount, "%d aggregate units survive actual host-to-replica state application" % amount)
	for malformed: Variant in [-1, 9007199254740992, 1.5, "100002"]:
		var packet: Dictionary = baseline.duplicate(true)
		packet.expedition.checkpoint.expedition.garage_stock = {"steel":malformed}
		var before: Dictionary = game.campaign.checkpoint()
		check(not world.apply(packet) and game.campaign.checkpoint() == before, "Malformed aggregate stock is rejected before changing the live ledger")
	var over_crate: Dictionary = baseline.duplicate(true)
	for entity: Dictionary in over_crate.entities:
		if entity.type == "supply":
			entity.state.amount = 10001
			break
	check(not world.apply(over_crate), "An individual supply remains capped at 10,000 units")
	check(not Schema.bounded({"counter":1000000001}), "Unrelated gameplay numbers retain the existing one-billion bound")
	check(await Cleanup.free_scene(game, self), "Large-ledger replica releases actual audio and scene nodes")
	print("NETWORK CAMPAIGN STOCK: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
