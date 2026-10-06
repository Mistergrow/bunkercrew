extends SceneTree
## Malformed full snapshots must leave the live world and processing untouched.
const WORLD := preload("res://scripts/network_world.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func record(packet: Dictionary,kind: String) -> Dictionary:
	for entry in packet.entities:
		if entry.type==kind: return entry
	return {}

func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.combat_events.persistence_enabled=false
	game.start_scenario(2,{"environment":"sector07","build_type":"workshop","position":"left"})
	game._entity("enemy",Vector2(1350,430),{"kind":"shield_guard","wave":8})
	game._entity("projectile",Vector2(900,300))
	var world:=WORLD.new()
	world.bind(game)
	var baseline: Dictionary=world.capture()
	var original:=var_to_bytes(baseline)
	var cases: Array[Dictionary]=[]
	var packet: Dictionary=baseline.duplicate(true)
	packet.entities=packet.entities.filter(func(entry): return not entry.id.begins_with("player:1"))
	for entry in packet.entities:
		for field in entry.refs:
			if str(entry.refs[field]).begins_with("player:1"): entry.refs[field]=""
	cases.append({"label":"omitted worker subtree","packet":packet})
	packet=baseline.duplicate(true)
	var extra: Dictionary=record(packet,"wall").duplicate(true)
	extra.id="fixed:wall:999:430"
	packet.entities.append(extra)
	packet.structure.view_stage=2
	packet.game.view_stage=2
	record(packet,"core").state.hp=1.0
	cases.append({"label":"unconstructible fixed entity after earlier valid edits","packet":packet})
	packet=baseline.duplicate(true)
	var projectile: Dictionary=record(packet,"projectile")
	projectile.parent=projectile.id
	cases.append({"label":"cyclic dynamic parenting","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"wall").parent="player:1"
	cases.append({"label":"reparented existing wall","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"player").refs.mounted_turret=record(packet,"core").id
	cases.append({"label":"wrong reference class","packet":packet})
	packet=baseline.duplicate(true)
	packet.boss="player:1"
	cases.append({"label":"worker used as boss reference","packet":packet})
	packet=baseline.duplicate(true)
	packet.structure.rooms=4
	cases.append({"label":"room unlocked before required wave","packet":packet})
	packet=baseline.duplicate(true)
	packet.structure.rooms=1
	cases.append({"label":"construction without its new entities","packet":packet})
	packet=baseline.duplicate(true)
	packet.structure.dome_available=true
	cases.append({"label":"dome before unlock wave","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"enemy").state.profile={"label":"forged"}
	cases.append({"label":"incomplete arbitrary enemy profile","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"player").state.inventory={"ore":-1}
	cases.append({"label":"negative cargo","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"player").state.inventory={"unknown_resource":1}
	cases.append({"label":"foreign resource key","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"player").state.character_id="ivo"
	cases.append({"label":"changed established crew identity","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"worker_weapon").state.loaded.rifle=999
	cases.append({"label":"magazine exceeds catalog capacity","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"round_controller").state.phase="foreign_phase"
	cases.append({"label":"unknown wave phase","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"station").state.output_amount=1000000
	cases.append({"label":"unbounded drawn output count","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"player").state.position=Vector2(1e20,0)
	cases.append({"label":"finite but extreme coordinates","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"wall").state.position.x+=1
	cases.append({"label":"moved fixed collision geometry","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"core").state.hp="wrong type"
	cases.append({"label":"wrong HP type without a validation exception","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"player").state.erase("inventory")
	cases.append({"label":"missing required entity field","packet":packet})
	packet=baseline.duplicate(true)
	packet.game.erase("camera_target_zoom")
	cases.append({"label":"missing required global field","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"core").state={}
	cases.append({"label":"empty state cannot bypass property schema setup","packet":packet})
	packet=baseline.duplicate(true)
	record(packet,"player").state.erase("position")
	cases.append({"label":"missing actor transform","packet":packet})
	for item in cases:
		check(not world.apply(item.packet),item.label+" rejected")
		check(not world.last_error.is_empty(),item.label+" diagnosed")
		check(not world.client and game.is_processing(),item.label+" does not freeze simulation")
		check(var_to_bytes(world.capture())==original,item.label+" leaves entire captured state unchanged")
	check(world.apply(baseline),"Valid authoritative state still applies after malformed packets: "+world.last_error)
	var posed: Dictionary=baseline.duplicate(true)
	record(posed,"worker_weapon").state.position=Vector2(-10,-21)
	check(world.apply(posed),"A held weapon may change its local aiming/crouching pose")
	game.rounds.wave=15
	game.rounds.phase="salvage"
	game.dome.unlock()
	var unlocked: Dictionary=world.capture()
	check(game.dome.available,"Host can unlock dome in wave-fifteen salvage")
	check(await CLEANUP.free_scene(game,self),"Boundary scene releases cleanly")
	var guest=load("res://scenes/main.tscn").instantiate()
	root.add_child(guest)
	current_scene=guest
	guest.combat_events.persistence_enabled=false
	guest.start_scenario(2,{"environment":"sector07","build_type":"workshop","position":"left"})
	var replica:=WORLD.new()
	replica.bind(guest)
	check(replica._validate(unlocked),"Valid dome construction can be validated before mutation")
	var premature: Dictionary=unlocked.duplicate(true)
	premature.structure.wave=14
	record(premature,"round_controller").state.wave=14
	record(premature,"round_controller").state.phase="salvage"
	check(not replica.apply(premature),"A warm constructor plan still enforces the current dome unlock wave")
	check(not guest.dome.available and not replica.client,"Rejected premature dome construction cannot unlock or freeze the guest")
	check(replica.apply(unlocked),"Incoming salvage phase is applied before dome constructor: "+replica.last_error)
	check(guest.dome.available and guest.dome.segments.size()==14,"Wave-fifteen reconnect reconstructs every physical dome panel")
	check(await CLEANUP.free_scene(guest,self),"Salvage replica releases cleanly")
	print("NETWORK SNAPSHOT BOUNDARIES: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
