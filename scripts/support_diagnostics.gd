extends Node
## Small, local diagnostic trace. Only explicit public enums and numbers enter
## the report; raw engine logs, chat, profile IDs, addresses and codes never do.
const L := preload("res://scripts/locale_text.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const Identity := preload("res://scripts/build_identity.gd")
const MAX_EVENTS := 128
const SAMPLE_SECONDS := 0.5
const NETWORK_STATES := ["offline","connecting","lobby","playing","reconnecting","error"]
const ROUND_PHASE_IDS := ["build","warning","attack","salvage","victory","defeat","convoy","occupation"]
const STAGES := ["defense","preparation","map","travel","stop","occupation","failed"]
const OVERLAYS := ["menu","network","scenario","characters","pause","audio","microphone","help","personal","upgrades","expedition","victory","defeat","campaign_victory","friends","story_journal","story_encounter",""]
static var _environment_ids: Array[String] = []
var game: Node
var _events: Array[Dictionary] = []
var _last_state: Dictionary = {}
var _remaining := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sample()

func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_remaining = SAMPLE_SECONDS
		_sample()

static func _value(owner_object: Object, field: String, fallback: Variant = null) -> Variant:
	return owner_object.get(field) if is_instance_valid(owner_object) and field in owner_object else fallback

static func _enum(value: Variant, allowed: Array, fallback: String = "unknown") -> String:
	return str(value) if value is String and value in allowed else fallback

static func _count(value: Variant, maximum: int) -> int:
	return clampi(int(value),0,maximum) if value is int else 0

static func _gain(value: Variant) -> float:
	return snappedf(clampf(float(value),0.0,1.5),0.01) if (value is float or value is int) and is_finite(float(value)) else 0.0

static func _environment_id(value: Variant) -> String:
	if _environment_ids.is_empty():
		for entry: Dictionary in ScenarioCatalog.environments(true): _environment_ids.append(str(entry.id))
	return str(value) if value is String and value in _environment_ids else "unknown"

static func _network_error(message: Variant) -> String:
	# Classification is intentionally lossy: an unexpected message may contain
	# remote-controlled names or addresses. No raw error text is exported.
	if not message is String or message.is_empty(): return "none"
	if "Spielversion" in message or "Weltversion" in message: return "version_mismatch"
	if "Gastgeber hat die Sitzung geschlossen" in message: return "host_left"
	if "30 Sekunden" in message or "Zeit" in message: return "timeout"
	if "voll" in message: return "room_full"
	if "Code" in message: return "join_code"
	return "connection_error"

func state_snapshot() -> Dictionary:
	var network: Object = _value(game,"network")
	var campaign: Object = _value(game,"campaign")
	var rounds: Object = _value(game,"rounds")
	var hud: Object = _value(game,"hud")
	var expedition: Object = _value(game,"expedition")
	var social: Object = _value(game,"social")
	var options: Variant = _value(game,"scenario_options",{})
	var environment := "classic"
	if options is Dictionary and not options.is_empty():
		environment = _environment_id(options.get("environment"))
	var chapter := "none"
	var stage: Variant = _value(expedition,"stage")
	var proposed_chapter: Variant = _value(campaign,"pending_node","") if stage in ["defense","occupation"] else _value(campaign,"current_node","")
	if proposed_chapter is String and not CampaignCatalog.node(proposed_chapter).is_empty(): chapter = proposed_chapter
	var active := bool(_value(network,"active",false))
	var transport := "none"
	if active:
		var relay: Variant = _value(network,"relay_url","")
		transport = "enet" if not relay is String or relay.is_empty() else "wss" if relay.begins_with("wss://") else "ws_loopback"
	return {
		"mode":"menu" if not bool(_value(game,"started",false)) else "story" if bool(_value(game,"story_mode",false)) else "free_shift",
		"campaign_active":bool(_value(campaign,"active",false)),
		"environment":environment, "chapter":chapter,
		"players":_count(_value(game,"player_count",0),4),
		"overlay":_enum(_value(hud,"overlay"),OVERLAYS),
		"phase":_enum(_value(rounds,"phase"),ROUND_PHASE_IDS),
		"wave":_count(_value(rounds,"wave",0),Balance.TOTAL_WAVES),
		"travel_stage":_enum(stage,STAGES),
		"network_state":_enum(_value(network,"state"),NETWORK_STATES),
		"network_role":"host" if active and bool(_value(network,"is_host",false)) else "guest" if active else "offline",
		"transport":transport, "network_error":_network_error(_value(network,"error_message","")),
		"friends_service":_enum(_value(social,"connection_state"),["offline","connecting","authenticating","online","error"]),
		"paused":get_tree().paused if is_inside_tree() else false,
	}

func _sample() -> void:
	if not is_instance_valid(game): return
	var state := state_snapshot()
	if state == _last_state: return
	_last_state = state.duplicate(true)
	var event := {"elapsed_ms":Time.get_ticks_msec(),"state":state}
	_events.append(event)
	if _events.size()>MAX_EVENTS: _events.pop_front()

func capture() -> Dictionary:
	_sample()
	var audio: Object = _value(game,"audio")
	var weather: Object = _value(game,"weather")
	var identity := Identity.current()
	return {
		"schema":1, "application":"Bunkercrew", "version":identity.version,
		"build":identity.build, "source_sha256":identity.source_sha256, "exported":identity.exported,
		"network_build":Protocol.BUILD,
		"world_revision":Protocol.WORLD_REVISION,
		"engine":str(Engine.get_version_info().get("string","unknown")),
		"platform":_enum(OS.get_name(),["Linux","Windows","macOS","Android","iOS","Web"]),
		"renderer":_enum(RenderingServer.get_current_rendering_method(),["gl_compatibility","mobile","forward_plus"],"headless" if DisplayServer.get_name()=="headless" else "unknown"),
		"rendering_driver":_enum(RenderingServer.get_current_rendering_driver_name(),["opengl3","vulkan","d3d12","dummy"],"headless" if DisplayServer.get_name()=="headless" else "unknown"),
		"headless":DisplayServer.get_name()=="headless", "locale":_enum(L.current_locale(),["de","en"]),
		"recorded_utc":Time.get_datetime_string_from_system(true)+"Z",
		"state":state_snapshot(), "events":_events.duplicate(true),
		"settings":{"reduced_weather":bool(_value(weather,"reduced_effects",false)),
			"music":_gain(_value(audio,"music_volume",0.5)), "effects":_gain(_value(audio,"sfx_volume",0.5)),
			"dialogue":_gain(_value(audio,"voice_volume",0.5)), "connected_controller_count":mini(4,Input.get_connected_joypads().size())},
		"privacy":{"raw_logs_included":false,"chat_included":false,"profile_included":false,"network_addresses_included":false,"uploaded":false},
	}

static func encode(report: Dictionary) -> String:
	return JSON.stringify(report,"  ")+"\n"

static func save_local(report: Dictionary, directory: String = "user://reports") -> Dictionary:
	var ancestor := ProjectSettings.globalize_path(directory).simplify_path()
	while not ancestor.is_empty() and not DirAccess.dir_exists_absolute(ancestor):
		if FileAccess.file_exists(ancestor): return {"ok":false,"error":ERR_ALREADY_EXISTS}
		var parent := ancestor.get_base_dir()
		if parent==ancestor: break
		ancestor=parent
	var status := DirAccess.make_dir_recursive_absolute(directory)
	if status!=OK: return {"ok":false,"error":status}
	var filename := "bunkercrew-report-%s-%d.json" % [Time.get_datetime_string_from_system(true).replace(":","-").replace("T","-"),Time.get_ticks_usec()]
	var path := directory.path_join(filename)
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return {"ok":false,"error":FileAccess.get_open_error()}
	file.store_string(encode(report))
	file.flush()
	var error := file.get_error()
	file.close()
	return {"ok":error==OK,"path":path if error==OK else "","error":error}
