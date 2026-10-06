extends Node
## Publishes the actual session state without giving the presence service authority
## over the simulation. The durable social connection survives scene reloads.
var game
var _interval := 0.0
var _published: Dictionary = {}
var _name := ""
var _service_binding := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh()

func _process(delta: float) -> void:
	_interval += delta
	if _interval < 0.25: return
	_interval = 0.0
	refresh()

func refresh() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.social): return
	var hub = game.social
	var session = game.network
	if is_instance_valid(session) and session.has_method("observe_public_address") and "observed_address" in hub:
		session.observe_public_address(str(hub.observed_address))
	if is_instance_valid(session) and session.active and hub.has_method("connect_for_room"):
		var service: String = str(session.relay_url)
		if service.is_empty() and session.get("room_social_service") is String: service = session.room_social_service
		if not service.is_empty() and service != _service_binding:
			_service_binding = service
			hub.connect_for_room(service)
	elif is_instance_valid(session) and not session.active:
		_service_binding = ""
	if is_instance_valid(session) and session.has_method("refresh_social_identity") and hub.has_method("crew_identity"):
		session.refresh_social_identity(hub)
	var data := presence()
	if data != _published:
		_published = data.duplicate(true)
		hub.set_presence(data)
	if is_instance_valid(session) and "short_room_code" in session and "room_alias" in hub and session.is_host:
		var alias: String = str(hub.room_alias) if session.active and session.state == "lobby" and not game.started and bool(data.get("joinable", false)) else ""
		if session.short_room_code != alias:
			session.short_room_code = alias
			if session.active: session._send_lobby()
			session.changed.emit()
	if is_instance_valid(session) and session.has_method("set_display_name") and _name != str(hub.display_name):
		if session.set_display_name(str(hub.display_name)):
			_name = str(hub.display_name)

func presence() -> Dictionary:
	var session = game.network
	var active: bool = is_instance_valid(session) and session.active
	var status: String = "playing" if game.started else ("lobby" if active and session.state == "lobby" else "menu")
	var environment := ""
	if status == "playing": environment = str(game.scenario_options.get("environment", "sector07"))
	elif status == "lobby" and is_instance_valid(game.hud): environment = str(game.hud.scenario_options.get("environment", "sector07"))
	var joinable: bool = active and session.is_host and session.state == "lobby" and not game.started and not session._loading and session.connected_player_count() < session.max_players
	var data := {"status": status, "environment": environment, "joinable": false, "room_code": "", "relay_url": ""}
	if not joinable: return data
	var code: String = session.room_code
	if session.relay_url.is_empty():
		code = session.internet_code if not session.internet_code.is_empty() else session.direct_code
	if code.is_empty(): return data
	data.joinable = true
	data.room_code = code
	data.relay_url = session.relay_url
	if not session.relay_url.is_empty(): data.room_token = session._relay_resume_token
	return data
