extends SceneTree
## Actual main-scene lobby fixture for the two-process Python integration run.

const CLEANUP = preload("res://tests/scene_cleanup.gd")
const TRANSPORT = preload("res://scripts/network_transport.gd")
const PROTOCOL = preload("res://scripts/network_protocol.gd")
const JOIN_CODE = preload("res://scripts/network_join_code.gd")
const OPTIONS := {"environment":"frozen_rail_yard","build_type":"workshop","position":"center"}
var game
var host := false
var done := false
var guest_selected := false
var lobby_verified := false
var coordination := ""
var started_at := 0
var probe
var probe_rejected := false
var role := ""
var relay_url := ""

func _initialize() -> void:
	started_at = Time.get_ticks_msec()
	call_deferred("run")

func run() -> void:
	role = OS.get_environment("LASTSHIFT_LOBBY_ROLE")
	host = role == "host"
	coordination = OS.get_environment("LASTSHIFT_LOBBY_PATH")
	relay_url = OS.get_environment("LASTSHIFT_LOBBY_RELAY")
	if role in ["rejector","silent"]:
		run_rejection_probe()
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.network.changed.connect(observe)
	game.hud.overlay = "network"
	if host:
		game.hud.scenario_options = OPTIONS.duplicate()
		game.network.host_room(relay_url)
		game.network.send_command("character",{"id":"branko"})
		if game.network.state == "error":
			finish(false,game.network.error_message)
			return
		publish_code()
	else:
		var code := FileAccess.get_file_as_string(coordination + ".code").strip_edges()
		game.network.join_room(relay_url,code)

func publish_code() -> void:
	if game.network.state != "lobby" or game.network.room_code.is_empty() or FileAccess.file_exists(coordination + ".code"):
		return
	var file := FileAccess.open(coordination + ".code",FileAccess.WRITE)
	if file == null:
		finish(false,"could not publish test code")
		return
	file.store_string(game.network.room_code)
	file.close()
	print("LOBBY_HOST_READY")

func run_rejection_probe() -> void:
	var decoded: Dictionary = JOIN_CODE.decode(FileAccess.get_file_as_string(coordination + ".code"))
	probe = TRANSPORT.new()
	root.add_child(probe)
	probe.error.connect(func(message: String): finish(false,message))
	probe.connected.connect(func():
		if role == "rejector":
			probe.send(PROTOCOL.encode({"kind":"hello","version":99,"build":"incompatible-test-build","resume":""})))
	probe.packet.connect(func(data: PackedByteArray):
		var message: Dictionary = PROTOCOL.decode(data)
		if message.get("kind","") == "reject":
			probe_rejected = true)
	probe.disconnected.connect(func(_reason: String): finish(probe_rejected,"host rejected and disconnected %s before a healthy join" % role))
	if probe.join(decoded.address,int(decoded.port)) != OK:
		finish(false,"rejection probe could not connect")

func observe() -> void:
	if done or not is_instance_valid(game) or not is_instance_valid(game.network):
		return
	var network = game.network
	if host:
		publish_code()
	if network.state == "error":
		finish(false,network.error_message)
		return
	if network.state != "lobby" or not network.peer_connected or not network._authenticated:
		return
	if not host and not guest_selected:
		guest_selected = true
		network.send_command("character",{"id":"ivo"})
	if game.selected_characters != ["branko","ivo"] or game.hud.scenario_options != OPTIONS:
		return
	if network.local_player_id != (1 if host else 2) or game.started:
		finish(false,"wrong player slot or premature match start")
		return
	lobby_verified = true
	if not host:
		var file := FileAccess.open(coordination + ".guest_passed",FileAccess.WRITE)
		file.store_string("verified actual guest authentication, character selection and host scenario")
		file.close()
		finish(true,"guest authenticated; Branko/Ivo and frozen workshop center synchronized")

func _process(_delta: float) -> bool:
	if done:
		return false
	if Time.get_ticks_msec() - started_at > 45000:
		finish(false,"45-second lobby timeout")
	elif host and lobby_verified and FileAccess.file_exists(coordination + ".guest_passed"):
		finish(true,"host authenticated guest; Branko/Ivo and scenario synchronized")
	return false

func finish(success: bool, detail: String) -> void:
	if done:
		return
	done = true
	print("SESSION_LOBBY_PASS " if success else "SESSION_LOBBY_FAIL ",role," ",detail)
	if is_instance_valid(probe):
		probe.close()
		probe.queue_free()
		await process_frame
	if is_instance_valid(game):
		game.network.leave()
		paused = false
		if not await CLEANUP.free_scene(game,self):
			success = false
	quit(0 if success else 1)
