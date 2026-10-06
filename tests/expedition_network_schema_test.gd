extends SceneTree
const SCHEMA := preload("res://scripts/network_replication_schema.gd")
const MESSAGES := preload("res://scripts/network_messages.gd")
var passed := 0
var failed := 0
func check(value: bool,label: String) -> void:
	if value: passed+=1
	else: failed+=1; push_error(label)
func _initialize() -> void:
	var state := CampaignState.new("user://network_schema_never_save.json",false)
	state.begin_new(ScenarioCatalog.validate({}),["mara","branko"],2)
	var payload := {"checkpoint":state.checkpoint(),"mode":"defense","options":state.options.duplicate()}
	var start := {"kind":"start","generation":2,"reset":true,"options":state.options.duplicate(),"characters":["mara","branko"],"story":false,"expedition":payload}
	check(MESSAGES.valid(start,false),"Valid bounded campaign transition accepted")
	check(not MESSAGES.valid(start,true),"Guest cannot issue host start envelope")
	var bad := start.duplicate(true)
	bad.expedition.mode="execute"
	check(not MESSAGES.valid(bad,false),"Arbitrary transition mode rejected")
	bad=start.duplicate(true); bad.characters=["branko","mara"]
	check(not MESSAGES.valid(bad,false),"Transition cannot replace checkpoint crew identity")
	bad=start.duplicate(true); bad.expedition.checkpoint.player_count=1
	check(not MESSAGES.valid(bad,false),"Online transition cannot silently remove a player")
	bad=start.duplicate(true); bad.expedition.checkpoint.expedition.vehicle.reserve=241
	check(not MESSAGES.valid(bad,false),"Campaign reserve above240 rejected before new scene")
	var command := {"kind":"command","generation":2,"command":"expedition","args":{"action":"load","data":{"kind":"steel","amount":1}}}
	check(MESSAGES.valid(command,true),"Bounded supply intent uses audited command envelope")
	bad=command.duplicate(true); bad.args.data.amount=10000
	check(not MESSAGES.valid(bad,true),"Oversized supply request rejected")
	bad=command.duplicate(true); bad.args.action="secure_stop"
	check(not MESSAGES.valid(bad,true),"Guests cannot submit direct reward completion commands")
	bad=command.duplicate(true); bad.args.player_id=1
	check(not MESSAGES.valid(bad,true),"Envelope rejects forged host player identity")
	var vehicle := preload("res://scripts/convoy_vehicle.gd").new()
	vehicle.road_bounds=Vector2(100,3600)
	var wire := {}
	for field: String in SCHEMA.fields("convoy_vehicle"): wire[field]=vehicle.get(field)
	check(SCHEMA.valid_state("convoy_vehicle",wire),"Fresh convoy values satisfy strict entity schema")
	bad=wire.duplicate(true); bad.max_hp=1100.0
	check(not SCHEMA.valid_state("convoy_vehicle",bad),"Vehicle armor requires matching research")
	bad=wire.duplicate(true); bad.ammo=41
	check(not SCHEMA.valid_state("convoy_vehicle",bad),"Loaded MG cannot exceed forty rounds")
	bad=wire.duplicate(true); bad.reserve=241
	check(not SCHEMA.valid_state("convoy_vehicle",bad),"Vehicle reserve cannot exceed240")
	bad=wire.duplicate(true); bad.cargo={"crystal":1}
	check(not SCHEMA.valid_state("convoy_vehicle",bad),"Unsupported cargo cannot enter convoy")
	bad=wire.duplicate(true); bad.road_bounds=Vector2(0,99999)
	check(not SCHEMA.valid_state("convoy_vehicle",bad),"Vehicle road bounds stay inside supported arena")
	check(SCHEMA.valid_state("convoy_seat",{"role":"driver","enter_frame":1}),"Driver role is a valid fixed child")
	check(not SCHEMA.valid_state("convoy_seat",{"role":"pilot","enter_frame":1}),"Unknown crew roles rejected")
	check(SCHEMA.valid_state("campaign_salvage",{"claim_id":"test:first","drop_id":"wave_03","amount":1,"elapsed":0.0,"fall_speed":0.0,"collected":false}),"Finite route-data pickup has bounded replication state")
	var weapon:=WorkerWeapon.new()
	var weapon_state:={"weapon_kind":"rifle","loaded":weapon.loaded.duplicate(),"reserve":120,"open_pack":19}
	check(SCHEMA.valid_state("worker_weapon",weapon_state) and SCHEMA.valid_weapon_research(weapon_state,{}),"Finite partial ammunition pack and base reserve validate")
	weapon_state.loaded.rifle=36
	weapon_state.reserve=180
	check(SCHEMA.valid_state("worker_weapon",weapon_state),"Maximum researched magazine and reserve fit wire caps")
	check(not SCHEMA.valid_weapon_research(weapon_state,{}),"Unresearched extra magazine or reserve rounds are rejected")
	check(SCHEMA.valid_weapon_research(weapon_state,{"weapon_magazines":true,"weapon_pouches":true}),"Snapshot research authorizes extra finite capacity")
	weapon_state.open_pack=20
	check(not SCHEMA.valid_state("worker_weapon",weapon_state),"A complete pack cannot be duplicated into partial-pack storage")
	weapon.free()
	vehicle.free()
	print("EXPEDITION WIRE: %d passed, %d failed"%[passed,failed])
	quit(1 if failed else 0)
