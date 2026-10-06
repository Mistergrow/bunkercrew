extends Node
## Authoritative bridge between a defended bunker, a driven convoy and the next siege.
const Vehicle := preload("res://scripts/convoy_vehicle.gd")
const NetInput := preload("res://scripts/network_input.gd")
const Storage := preload("res://scripts/medic_storage.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const ROAD_START := 900.0
const ROAD_END := 3300.0
const ROAD_BOUND := 3700.0
var game
var state: CampaignState
var vehicle
var road_open := false
var route: Dictionary = {}
var progress := 0.0
var ambushes := 0
var guard_count := 0
var stop_done := false
var transitioning := false
var _sync_time := 0.0
var _repair_defense_active := false
var _repair_guard_clock := 0.0
var _repair_guard_batches := 0
var _offline_resume_archive: Dictionary = {}
var _offline_resume_original: Dictionary = {}
const MAX_ROAD_GUARDS := 24
var stage: String:
	get: return str(state.expedition.stage) if state!=null else "defense"

func _ready() -> void:
	state=game.campaign
	game.upgrades.changed.connect(_research_changed)

func authoritative() -> bool:
	return not is_instance_valid(game.network) or not game.network.active or game.network.is_host

func vehicle_unlocked() -> bool:
	return state!=null and state.active and bool(state.expedition.vehicle.unlocked)

func can_manage() -> bool:
	return vehicle_unlocked() and stage in ["preparation","map"]

func start_defense() -> void:
	if not authoritative() or state.active: return
	if state.begin_new(game.scenario_options,game.selected_characters,game.player_count): state.mission_start()

func on_victory() -> bool:
	if not authoritative() or not state.active or not state.mission_running or _living_guards()>0: return false
	CampaignSalvage.recover_remaining(game)
	var stock:=_capture_stock()
	var result:=state.complete_mission(state.mission_id,game.rounds.wave,game.players,game.upgrades,stock)
	if result.is_empty():
		game.notify(state.last_error)
		return false
	_site_secured()
	_mirror_stock()
	return true

func _capture_stock() -> Dictionary:
	var stock:=_capture_physical_stock()
	var reserve:=storage_reserve()
	for kind in reserve: _add_stock(stock,kind,int(reserve[kind]))
	return stock

func storage_reserve() -> Dictionary:
	if authoritative(): return Storage.reserved(game)
	# The existing checkpoint carries the complete warehouse total. Replicas
	# derive its reserve from the synchronized physical ownership records.
	var reserve: Dictionary={}
	if not can_manage(): return reserve
	var physical:=_capture_physical_stock()
	for kind in state.expedition.garage_stock:
		var remaining:=int(state.expedition.garage_stock[kind])-int(physical.get(kind,0))
		if remaining>0: reserve[kind]=remaining
	return reserve

func _capture_physical_stock() -> Dictionary:
	var stock: Dictionary={}
	for supply in get_tree().get_nodes_in_group("supplies"):
		if supply.game==game and not supply.is_queued_for_deletion() and supply.kind in CampaignCatalog.CARGO_KINDS:
			stock[supply.kind]=int(stock.get(supply.kind,0))+int(supply.amount)
	for pickup in get_tree().get_nodes_in_group("pickups"):
		if pickup.game==game and not pickup.is_queued_for_deletion() and pickup.kind in CampaignCatalog.CARGO_KINDS:
			stock[pickup.kind]=int(stock.get(pickup.kind,0))+int(pickup.amount)
	for player in game.players:
		if not is_instance_valid(player) or player.is_queued_for_deletion(): continue
		for kind in player.inventory:
			if kind in CampaignCatalog.CARGO_KINDS: stock[kind]=int(stock.get(kind,0))+int(player.inventory[kind])
	for station in get_tree().get_nodes_in_group("stations"):
		if not _recoverable_station(station): continue
		for kind: String in station.recipe().inputs:
			var amount: int=station.amount_for(kind) if station is RecipeStation else station.input_amount
			# Starting a batch already debits its ingredients. Until it finishes,
			# those finite units still belong to the machine, not to a product.
			if station.working: amount+=station.input_cost(kind)
			if station.kind=="furnace":
				amount-=station.input_scrap+(station.working_scrap if station.working else 0)
			_add_stock(stock,kind,amount)
		if station.kind=="furnace":
			_add_stock(stock,"scrap",station.input_scrap+(station.working_scrap if station.working else 0))
		_add_stock(stock,station.output_kind(),station.output_amount)
	var medic = game.get("medic")
	if is_instance_valid(medic) and not medic.is_queued_for_deletion() and medic.logistics_cargo in CampaignCatalog.CARGO_KINDS:
		stock[medic.logistics_cargo]=int(stock.get(medic.logistics_cargo,0))+1
	return stock

func _recoverable_station(station: Node) -> bool:
	return station is ProductionStation and station.game==game and not station.is_queued_for_deletion()

func _add_stock(stock: Dictionary,kind: String,amount: int) -> void:
	if amount>0 and kind in CampaignCatalog.CARGO_KINDS:
		stock[kind]=int(stock.get(kind,0))+amount

func _mirror_stock() -> void:
	if not authoritative() or not CampaignState.valid_stock(state.expedition.garage_stock): return
	# The garage ledger is a snapshot of actual recovered stores, not a new grant.
	var remaining: Dictionary=state.expedition.garage_stock.duplicate()
	Storage.clear_reserve(game)
	var medic = game.get("medic")
	if is_instance_valid(medic) and medic.logistics_cargo in CampaignCatalog.CARGO_KINDS:
		# The committed garage ledger now owns that physical unit. Clear the
		# old trip before materializing stores, so it cannot be credited again.
		medic.logistics_cargo=""
		medic.logistics._clear_trip()
	for pickup in get_tree().get_nodes_in_group("pickups"):
		if pickup.game==game and pickup.kind in CampaignCatalog.CARGO_KINDS: pickup.queue_free()
	for player in game.players:
		if not is_instance_valid(player) or player.is_queued_for_deletion(): continue
		for kind in CampaignCatalog.CARGO_KINDS: player.inventory.erase(kind)
	for station in get_tree().get_nodes_in_group("stations"):
		if not _recoverable_station(station): continue
		# Ownership changes only after the checkpoint commit. An unfinished
		# batch returns its raw inputs; cancel it and return its spent binder
		# exactly once, without manufacturing output or awarding batch XP.
		if station.working: station.binder+=int(station.recipe().get("binder",0))
		station.input_amount=0
		station.input_scrap=0
		station.working_scrap=0
		station.output_amount=0
		station.working=false
		station.production_time=0.0
		station.transfer.clear()
		station.batch_donors.clear()
		if station is RecipeStation: station.ingredient_amounts.clear()
		station.queue_redraw()
	for supply in get_tree().get_nodes_in_group("supplies"):
		if supply.game!=game or supply.is_queued_for_deletion() or not supply.kind in CampaignCatalog.CARGO_KINDS: continue
		supply.amount=mini(int(remaining.get(supply.kind,0)),Balance.PICKUP_STACK_MAX)
		remaining[supply.kind]=int(remaining.get(supply.kind,0))-supply.amount
		supply.transfer.clear()
		supply.deposit_transfer.clear()
		supply.queue_redraw()
	var positions: Array[Vector2]=Storage._positions(game,medic) if is_instance_valid(medic) else []
	# Every material receives an accessible chest before extra copies of a
	# common material use the remaining safe floor slots.
	for kind in remaining:
		if int(remaining[kind])<=0: continue
		var existing:=false
		for supply in get_tree().get_nodes_in_group("supplies"):
			if supply.game==game and not supply.is_queued_for_deletion() and supply.kind==kind: existing=true; break
		if existing: continue
		var amount:=mini(int(remaining[kind]),Balance.PICKUP_STACK_MAX)
		if not positions.is_empty() and is_instance_valid(_supply_at(kind,amount,positions.pop_front())):
			remaining[kind]=int(remaining[kind])-amount
	for kind in remaining:
		while int(remaining[kind])>0:
			var amount:=mini(int(remaining[kind]),Balance.PICKUP_STACK_MAX)
			if positions.is_empty() or not is_instance_valid(_supply_at(kind,amount,positions.pop_front())):
				# No overlap, off-map fallback or resource truncation. A bounded
				# warehouse reserve replenishes the material's real storage chest.
				if not Storage.add_reserve(game,kind,int(remaining[kind])): push_error("Invalid campaign storage reserve")
				break
			remaining[kind]=int(remaining[kind])-amount

func request(action: String,args: Dictionary={}) -> void:
	if is_instance_valid(game.network) and game.network.active and not game.network.is_host and action in ["map","back"]:
		game.hud.overlay="expedition" if action=="map" else ""
		return
	if is_instance_valid(game.network) and game.network.active:
		game.network.send_command("expedition",{"action":action,"data":args})
	else:
		handle_command(action,args,1)

static func valid_command(action: String,args: Dictionary) -> bool:
	match action:
		"prepare","depart","resume","retry","garage","map","back","refuel","repair","cinematic_skip": return args.is_empty()
		"route":
			return args.size()<=2 and args.get("id") is String and CampaignCatalog.contains(args.id) and (not args.has("unlock") or args.unlock is bool) and args.keys().all(func(key):return key in ["id","unlock"])
		"stop": return args.size()==1 and args.get("id") is String and (args.id=="" or not CampaignCatalog.stop(args.id).is_empty())
		"load","unload": return args.size()==2 and args.get("kind") in CampaignCatalog.CARGO_KINDS and args.get("amount") is int and args.amount>=1 and args.amount<=18
	return false

func handle_command(action: String,args: Dictionary,player_id: int) -> bool:
	if not authoritative() or not valid_command(action,args) or not vehicle_unlocked() or transitioning: return false
	if action in ["depart","retry","garage"] and is_instance_valid(game.network) and game.network.active:
		if game.network._loading or game.network.state!="playing": return false
	# Shared routing and scarce garage stock are host decisions. Seats remain
	# independently operable by both participants through ordinary player input.
	if player_id!=1: return false
	if action=="cinematic_skip": return game.travel_cinematic.skip(player_id)
	if game.travel_cinematic.blocks_gameplay(): return false
	if boarding_active():
		if not action in ["map","back"]: return false
		_cancel_boarding()
	if action=="prepare" and can_manage():
		state.expedition.garage_stock=_capture_stock()
		_sync_vehicle()
		_spawn_vehicle(Vector2(game.scenario_bunker.room_right+170,430))
		game.rounds.running=false
		game.rounds.phase="convoy"
		_open_panel()
		return true
	if action=="retry" and can_retry_journey():
		var backup:=_transition_backup()
		route=state.retry_journey()
		if route.is_empty(): return false
		# Occupation already uses the destination scenery. Retry starts from the
		# departure checkpoint, so its environment must follow current_node.
		var selection: Dictionary=state.options.duplicate()
		if state.current_node!=CampaignCatalog.ENTRY: selection.environment=CampaignCatalog.node(state.current_node).environment
		return _change_world("travel",selection,backup)
	if action=="garage" and stage in ["failed","travel","stop","occupation"]:
		var backup:=_transition_backup()
		if state.retry_journey().is_empty(): return false
		state.expedition.stage="preparation"
		state.expedition.departure={}
		# The safe stop owned these recovered hands separately from the source
		# warehouse. Returning transfers them once before its mirror clears hands.
		for snapshot: Dictionary in state.snapshots.values():
			var carried: Dictionary=snapshot.get("inventory",{})
			for kind: String in CampaignCatalog.CARGO_KINDS:
				var amount:=int(carried.get(kind,0))
				if amount>0:
					state.expedition.garage_stock[kind]=int(state.expedition.garage_stock.get(kind,0))+amount
					carried.erase(kind)
		# Returning to the garage changes the durable resume mode. Commit it
		# before handoff, including when the user closes without loading/refueling.
		if not state.save_checkpoint():
			var error: String=state.last_error
			_restore_transition(backup)
			game.notify(error)
			return false
		var selection: Dictionary=state.options.duplicate()
		if state.current_node!=CampaignCatalog.ENTRY: selection.environment=CampaignCatalog.node(state.current_node).environment
		return _change_world("preparation",selection,backup)
	if action=="map" and (can_manage() or stage in ["travel","stop","occupation"] or outpost_pending()):
		if can_manage(): state.expedition.garage_stock=_capture_stock()
		_open_panel()
		return true
	if action=="back":
		if stage in ["travel","stop","occupation"] or can_manage() or outpost_pending():
			game.hud.overlay=""
			_set_pause(false)
			return true
		return false
	if action=="resume" and stage=="stop" and _living_guards()==0:
		var backup:=_transition_backup()
		_sync_vehicle()
		var reward:=state.secure_stop(game.players,game.upgrades)
		if reward.is_empty():
			var error: String=state.last_error
			_restore_transition(backup)
			if not error.is_empty(): game.notify(error)
			return false
		vehicle.configure_trip(vehicle.position,Vector2(ROAD_START-100,ROAD_BOUND-100),state.expedition.vehicle)
		stop_done=true
		game.core.hp=game.core.max_hp
		if game.combat_events.has_method("record_campaign_event"): game.combat_events.record_campaign_event("roadside_complete",{"weapon":reward.get("weapon","")})
		game.hud.overlay=""
		_set_pause(false)
		game.notify(LocaleText.text("Zwischenhalt gesichert · Beute verstaut · Weiterfahrt zum Bunker"))
		return true
	if not can_manage(): return false
	match action:
		"route":
			if not _capture_preparation(): return false
			if bool(args.get("unlock",false)) and not state.unlock_route(args.id): return false
			if not state.select_destination(args.id): return false
		"stop":
			if not _capture_preparation(): return false
			if not state.select_stop(args.id): return false
		"load","unload","refuel","repair":
			return _garage_transaction(action,args)
		"depart":
			return _begin_boarding()
		_:
			return false
	return true

func boarding_active() -> bool:
	return is_instance_valid(vehicle) and can_manage() and vehicle.journey_state.phase in ["boarding","departure"]

func connected_crew() -> Array:
	var result: Array=[]
	for player in game.players:
		if not is_instance_valid(player) or player.is_queued_for_deletion() or player.get("game")!=game or bool(player.get_meta("network_departed",false)): continue
		if player.has_method("is_downed") and player.is_downed(): continue
		if is_instance_valid(game.network) and game.network.active and game.network.has_method("is_player_connected") and not game.network.is_player_connected(int(player.player_id)): continue
		result.append(player)
	return result

func crew_ready() -> bool:
	if not is_instance_valid(vehicle) or vehicle.destroyed: return false
	var crew:=connected_crew()
	if crew.is_empty() or not is_instance_valid(vehicle.driver_seat.occupant) or not vehicle.driver_seat.occupant in crew: return false
	return crew.all(func(player): return vehicle.seat_for(player)!=null and player.mounted_turret==vehicle.seat_for(player))

func crew_seat_roles() -> Array[String]:
	var result: Array[String]=[]
	result.resize(state.player_count)
	var used: Array[String]=[]
	if is_instance_valid(vehicle):
		for seat in vehicle.seats:
			if not is_instance_valid(seat.occupant) or seat.occupant.is_queued_for_deletion(): continue
			var slot:=int(seat.occupant.get("player_id"))-1
			if slot<0 or slot>=result.size() or not result[slot].is_empty() or seat.role in used: continue
			result[slot]=str(seat.role)
			used.append(str(seat.role))
	for slot in result.size():
		if not result[slot].is_empty(): continue
		for role: String in Vehicle.SEAT_ROLES:
			if not role in used:
				result[slot]=role
				used.append(role)
				break
	return result

func _begin_boarding() -> bool:
	_sync_vehicle()
	var data: Dictionary=state.expedition.vehicle
	var cost:=CampaignCatalog.route_fuel(state.pending_node,state.expedition.selected_stop,data.upgrades)
	if not state.route_status(state.pending_node).can_travel or cost<1 or float(data.hp)<=0 or float(data.fuel)<cost:
		game.notify(LocaleText.text("Abfahrt nicht möglich · Route wählen, Fahrzeug reparieren und ausreichend tanken"))
		return false
	if not state.completed.has(state.pending_node) and not _crew_has_ammunition():
		game.notify(LocaleText.text("Keine Reisemunition · Persönliche Waffen vor der Abfahrt nachladen"))
		return false
	if not is_instance_valid(vehicle): _spawn_vehicle(Vector2(game.scenario_bunker.room_right+170,430))
	vehicle.journey_state=Journey.new_state("boarding")
	Journey.event(vehicle.journey_state,"boarding")
	vehicle.driving_enabled=false
	vehicle.velocity=Vector2.ZERO
	game.hud.overlay=""
	_set_pause(false)
	game.notify(LocaleText.text("Abfahrt vorbereiten · Alle steigen mit E in den Transporter"))
	return true

func _crew_has_ammunition() -> bool:
	if is_instance_valid(vehicle) and vehicle.has_mg and vehicle.ammo+vehicle.reserve+vehicle.open_pack>0: return true
	for player in connected_crew():
		var weapon=player.get_node_or_null("WorkerWeapon")
		if not weapon is WorkerWeapon: continue
		if weapon.reserve+weapon.open_pack>0: return true
		for kind: String in weapon.available_weapons():
			if int(weapon.loaded.get(kind,0))>=int(WorkerWeapon.WEAPONS[kind].cost): return true
	return false

func _cancel_boarding() -> void:
	if not is_instance_valid(vehicle): return
	for seat in vehicle.seats: seat.exit()
	vehicle.journey_state=Journey.new_state()
	vehicle.driving_enabled=false
	vehicle.velocity=Vector2.ZERO

func _launch_journey() -> bool:
	if not crew_ready(): return false
	if not state.completed.has(state.pending_node) and not _crew_has_ammunition():
		_cancel_boarding()
		_open_panel()
		game.notify(LocaleText.text("Keine Reisemunition · Persönliche Waffen vor der Abfahrt nachladen"))
		return false
	_sync_vehicle()
	state.expedition.garage_stock=_capture_stock()
	var backup:=_transition_backup()
	var roles:=crew_seat_roles()
	if not state.prepare_expedition(game.players,game.upgrades):
		_cancel_boarding()
		_open_panel()
		game.notify(state.last_error)
		return false
	# Preparation mirrors the whole source ledger and therefore still owns
	# hands there. The committed trip carries those finite units separately.
	var remaining: Dictionary=state.expedition.garage_stock.duplicate()
	for snapshot: Dictionary in state.snapshots.values():
		for kind: String in CampaignCatalog.CARGO_KINDS:
			var amount:=int(snapshot.get("inventory",{}).get(kind,0))
			if amount<=0: continue
			if not CampaignState._integer(remaining.get(kind),amount,CampaignState.MAX_STOCK_PER_KIND):
				_restore_transition(backup)
				_cancel_boarding()
				_open_panel()
				game.notify(LocaleText.text("Ungültiger Kampagnenstand wurde nicht gespeichert."))
				return false
			remaining[kind]=int(remaining[kind])-amount
	state.expedition.garage_stock=remaining
	route=state.begin_journey()
	if route.is_empty():
		_restore_transition(backup)
		_cancel_boarding()
		_open_panel()
		game.notify(LocaleText.text("Abfahrt nicht möglich · Route wählen, Fahrzeug reparieren und ausreichend tanken"))
		return false
	if _change_world("travel",game.scenario_options,backup,roles): return true
	_cancel_boarding()
	_open_panel()
	return false

func _garage_transaction(action: String,args: Dictionary) -> bool:
	if not _capture_preparation(): return false
	var previous:=state.checkpoint()
	var truck: Dictionary=state.expedition.vehicle
	var stock: Dictionary=state.expedition.garage_stock
	var specs:=CampaignCatalog.vehicle_stats(truck.upgrades)
	if action in ["load","unload"]:
		var kind: String=args.kind
		var amount: int=args.amount
		if action=="load":
			if int(stock.get(kind,0))<amount or CampaignCatalog.cargo_count(truck.cargo)+amount>int(specs.cargo_capacity): return false
			stock[kind]=int(stock.get(kind,0))-amount
			truck.cargo[kind]=int(truck.cargo.get(kind,0))+amount
		else:
			if int(truck.cargo.get(kind,0))<amount: return false
			truck.cargo[kind]=int(truck.cargo[kind])-amount
			if truck.cargo[kind]==0: truck.cargo.erase(kind)
			stock[kind]=int(stock.get(kind,0))+amount
	elif action=="refuel":
		if int(stock.get("scrap",0))<2 or float(truck.fuel)>=float(specs.fuel_capacity): return false
		stock.scrap=int(stock.scrap)-2
		truck.fuel=minf(float(specs.fuel_capacity),float(truck.fuel)+4)
	elif action=="repair":
		if int(stock.get("steel",0))<2 or float(truck.hp)>=float(specs.max_hp): return false
		stock.steel=int(stock.steel)-2
		truck.hp=minf(float(specs.max_hp),float(truck.hp)+150*float(specs.get("repair_multiplier",1.0)))
	if not state.save_checkpoint():
		state._restore(previous)
		return false
	if is_instance_valid(vehicle): vehicle.configure_trip(vehicle.position,Vector2(game.world_left+100,game.world_right-100),truck)
	_mirror_stock()
	state.changed.emit()
	if is_instance_valid(vehicle): preload("res://scripts/spatial_sound.gd").emit(game,"pickup",vehicle.global_position)
	else: game.sound("pickup") # Garage management may run before its world vehicle is installed.
	return true

func commit_research() -> bool:
	# Purchase calls this before applying effects or emitting success. Keep the
	# finite points, persistent unlocks and increased vehicle HP in one write.
	if not authoritative(): return false
	if not can_manage(): return true
	var portable: Array=game.upgrades.persistent_owned()
	if portable.size()==state.shared_personal_upgrades.size() and portable.all(func(id):return state.shared_personal_upgrades.has(id)) and game.upgrades.points==int(state.expedition.tech_points): return true
	_sync_vehicle()
	var previous:=state.checkpoint()
	var old_stats:=CampaignCatalog.vehicle_stats(state.expedition.vehicle.upgrades)
	if not _capture_preparation(): return false
	var new_stats:=CampaignCatalog.vehicle_stats(state.expedition.vehicle.upgrades)
	if float(state.expedition.vehicle.hp)>0:
		state.expedition.vehicle.hp=minf(float(new_stats.max_hp),float(state.expedition.vehicle.hp)+maxf(0,float(new_stats.max_hp)-float(old_stats.max_hp)))
	if not state.save_checkpoint():
		state._restore(previous)
		game.notify(state.last_error)
		return false
	if is_instance_valid(vehicle): vehicle.refresh_upgrades()
	return true

func _capture_preparation() -> bool:
	# Every durable garage action shares one safe ownership boundary. Personal
	# reloads can turn warehouse boxes into reserve rounds and an open package;
	# persisting either half alone loses or recreates finite ammunition on resume.
	if not can_manage(): return false
	var previous:=state.checkpoint()
	var stock:=_capture_stock()
	_sync_vehicle()
	if not CampaignState.valid_stock(stock) or not state._capture_crew(game.players,game.upgrades):
		state._restore(previous)
		state.last_error=LocaleText.text("Ungültiger Kampagnenstand wurde nicht gespeichert.")
		return false
	state.expedition.garage_stock=stock
	return true

func _research_changed() -> void:
	if not authoritative() or not can_manage(): return
	if commit_research(): return
	# Point grants also emit changed. A failed write must not publish a balance
	# that disappears on reconnect; purchase itself restores its full dictionary.
	game.upgrades.points=int(state.expedition.tech_points)
	for id in CampaignCatalog.PERSISTENT_UPGRADES: game.upgrades.owned.erase(id)
	for id in state.shared_personal_upgrades: game.upgrades.owned[id]=true

func _sync_vehicle() -> void:
	if is_instance_valid(vehicle): state.update_vehicle(vehicle.vehicle_data(),false)

func _spawn_vehicle(at: Vector2) -> void:
	if is_instance_valid(vehicle):
		vehicle.configure_trip(at,Vector2(game.world_left+100,game.world_right-100),state.expedition.vehicle)
		if can_manage(): vehicle.driving_enabled=false
		return
	vehicle=Vehicle.new()
	vehicle.game=game
	vehicle.expedition=self
	game.add_child(vehicle)
	vehicle.configure_trip(at,Vector2(game.world_left+100,game.world_right-100),state.expedition.vehicle)
	if can_manage(): vehicle.driving_enabled=false

func _open_panel() -> void:
	game.hud.overlay="expedition"
	_set_pause(true)

func _set_pause(value: bool) -> void:
	if is_instance_valid(game.network) and game.network.active:
		game.network.pause_match(value)
	else:
		get_tree().paused=value

func _transition_backup() -> Dictionary:
	return {"checkpoint":state.checkpoint(),"route":route.duplicate(true),"mission":{"mission_id":state.mission_id,"mission_salvage":state.mission_salvage,"mission_running":state.mission_running,"_issued":state._issued.duplicate(),"_collected":state._collected.duplicate()}}

func _restore_transition(backup: Dictionary) -> void:
	if backup.is_empty(): return
	# A refused scene handoff never owns the old world's resources or mission.
	# Restore the transient drop ledger as well as the durable campaign state.
	state._restore(backup.checkpoint)
	for key: String in backup.mission:
		state.set(key,backup.mission[key])
	route=backup.route.duplicate(true)
	if not state.save_checkpoint(): game.notify(state.last_error)
	state.changed.emit()

func _change_world(mode: String,selection: Dictionary,backup: Dictionary={},crew_seats: Array[String]=[]) -> bool:
	transitioning=true
	var payload: Dictionary={"checkpoint":state.checkpoint(),"mode":mode,"options":ScenarioCatalog.validate(selection)}
	if mode=="travel" and not crew_seats.is_empty(): payload.crew_seats=crew_seats.duplicate()
	if is_instance_valid(game.network) and game.network.active:
		if not game.network.expedition_transition(payload):
			transitioning=false
			_restore_transition(backup)
			return false
	else:
		get_tree().set_meta("expedition_resume",payload)
		get_tree().set_meta("session_preferences",game.session_preferences())
		get_tree().paused=false
		get_tree().reload_current_scene.call_deferred()
	game._restart_pending=true
	return true

func restore(payload: Dictionary) -> bool:
	# start_scenario refuses rebuilding a live world. Match that boundary before
	# replacing its campaign/mission ledger or delivering another cargo snapshot.
	if game.started or not valid_transition(payload): return false
	state._restore(payload.checkpoint)
	if not game.solo_story.wants_campaign(state):
		for site in state.completed: CharacterCatalog.unlock_for_site(site)
	game.selected_characters.assign(state.character_ids)
	game.start_scenario(state.player_count,payload.options)
	CampaignBonus.restore_players(game,state)
	CampaignBonus.apply_bunker(game,state)
	if payload.mode=="preparation" or (payload.mode=="occupation" and state.completed.has(state.pending_node)):
		_clear_preparation_starter_ammo()
	if CampaignCatalog.all_complete(state.completed) and payload.mode not in ["travel","occupation"] and not (game.solo_story.wants_campaign(state) and game.solo_story.has_pending_recruits()):
		# A terminal save still owns its finite garage ledger. Suppress fresh
		# scene starter supplies before any host snapshot can capture them.
		if authoritative() and stage in ["preparation","map"]: _mirror_stock()
		game.rounds.running=false
		game.rounds.phase="victory"
		game.hud.overlay="campaign_victory"
		_set_pause(true)
		return true
	match payload.mode:
		"travel":
			route=CampaignCatalog.journey(state.pending_node)
			route.stop=state.expedition.selected_stop
			stop_done=state.expedition.claimed_stops.has(route.stop)
			_start_road(stop_done,payload.get("crew_seats",[]))
		"occupation": _start_occupation()
		"preparation":
			game.rounds.running=false
			game.rounds.wave=20
			game.rounds.phase="convoy"
			if authoritative(): _mirror_stock()
			_spawn_vehicle(Vector2(game.scenario_bunker.room_right+170,430))
			_open_panel()
		"defense":
			state.mission_start()
			_apply_delivery()
			if CampaignCatalog.site_kind(state.pending_node)=="outpost":
				game.rounds.running=false
				game.rounds.phase="occupation"
				_spawn_guards(int(CampaignCatalog.objective(state.pending_node).guards),game.scenario_bunker.room_right+70,false)
	return true

func _clear_preparation_starter_ammo() -> void:
	# The fresh scene's first-shift roof magazines are not stored in the
	# campaign departure. Rebuilding a secured garage must not grant another
	# magazine on every continuation or return visit. Personal and convoy
	# ammunition were restored from their finite snapshots above.
	if not is_instance_valid(game.scenario_bunker): return
	for gun: RoofTurret in game.scenario_bunker.roof_guns:
		if not is_instance_valid(gun): continue
		gun.ammo=0
		gun.reserve=0
		gun.reload_timer=0.0

static func valid_transition(payload: Variant) -> bool:
	if not payload is Dictionary or payload.size()<3 or payload.size()>4: return false
	for key in payload:
		if not key in ["checkpoint","mode","options","crew_seats"]: return false
	if not payload.get("checkpoint") is Dictionary or not CampaignState.valid_checkpoint(payload.checkpoint): return false
	if not payload.get("mode") in ["travel","occupation","preparation","defense"] or not payload.get("options") is Dictionary: return false
	if ScenarioCatalog.validate(payload.options)!=payload.options: return false
	var saved: Dictionary=payload.checkpoint
	if payload.has("crew_seats"):
		if payload.mode!="travel" or not payload.crew_seats is Array or payload.crew_seats.size()!=saved.player_count: return false
		var used: Array=[]
		for role in payload.crew_seats:
			if not role is String or not role in Vehicle.SEAT_ROLES or role in used: return false
			used.append(role)
		if not "driver" in used: return false
	var allowed: Dictionary={"travel":["travel"],"occupation":["occupation"],"preparation":["preparation","map"],"defense":["defense"]}
	if not saved.expedition.stage in allowed[payload.mode]: return false
	var site: String=saved.pending_node if payload.mode in ["occupation","defense"] else saved.current_node
	var environment: String=str(saved.options.environment) if site==CampaignCatalog.ENTRY else str(CampaignCatalog.node(site).get("environment",""))
	return payload.options.environment==environment

func has_saved_campaign() -> bool:
	return state!=null and state.persistence_enabled and (FileAccess.file_exists(state.save_path) or FileAccess.file_exists(state.save_path+".bak"))

func saved_resume_payload(guest_characters: Variant="",offline_solo: bool=false) -> Dictionary:
	# Read into a separate state: invalid files and failed lobby starts must not
	# mutate either the live campaign or its durable checkpoint.
	if state!=null: state.last_error=""
	_offline_resume_archive.clear()
	_offline_resume_original.clear()
	if not has_saved_campaign(): return {}
	var saved:=CampaignState.new(state.save_path,false)
	saved.persistence_enabled=true
	if not saved.load_checkpoint():
		state.last_error=saved.last_error
		return {}
	saved.persistence_enabled=false
	var original := saved.checkpoint()
	var mode: String=saved.expedition.stage
	if mode in ["travel","stop","occupation","failed"]:
		if saved.retry_journey().is_empty(): return {}
		mode="travel"
	elif mode in ["preparation","map"]: mode="preparation"
	else: mode="defense"
	var joining: Array=[]
	if guest_characters is String and not guest_characters.is_empty(): joining=[guest_characters]
	elif guest_characters is Array: joining=guest_characters.duplicate()
	elif not guest_characters is String: return {}
	if joining.size()>3: return {}
	for id in joining:
		if not id is String or not CharacterCatalog.contains(id): return {}
	if offline_solo:
		if not joining.is_empty(): return {}
		var parked := OfflineCampaignArchive.park(saved.checkpoint(),saved.offline_crew_archive)
		if parked.is_empty(): return {}
		_offline_resume_archive=parked
		_offline_resume_original=original if saved.player_count>1 else {}
		saved.player_count=1
		for slot in range(2,PartyConfig.MAX_PLAYERS+1):
			saved.snapshots.erase(str(slot))
			if not saved.expedition.departure.is_empty(): saved.expedition.departure.snapshots.erase(str(slot))
	if not joining.is_empty():
		var count:=joining.size()+1
		if count<saved.player_count:
			state.last_error=LocaleText.format("Dieser Spielstand benötigt %d verbundene Spieler.",saved.player_count)
			return {}
		saved.character_ids=PartyConfig.normalize_characters(saved.character_ids,4)
		for slot in range(saved.player_count+1,count+1):
			var character: String=joining[slot-2]
			saved.character_ids[slot-1]=character
			var initial := saved.reserved_crew_snapshot(slot,character)
			if initial.is_empty(): initial={"character":character,"level":1,"xp":0.0,"skill_points":0,"skills":{"vitality":0,"combat":0,"engineering":0},"armor_tier":0,"weapon_kind":"rifle"}
			if not saved.completed.is_empty(): saved.snapshots[str(slot)]=initial.duplicate(true)
			if not saved.expedition.departure.is_empty():
				var departure := saved.reserved_crew_snapshot(slot,character,true)
				saved.expedition.departure.snapshots[str(slot)]=initial.duplicate(true) if departure.is_empty() else departure
		saved.player_count=count
	var selection: Dictionary=saved.options.duplicate()
	var site: String=saved.pending_node if mode in ["occupation","defense"] else saved.current_node
	if site!=CampaignCatalog.ENTRY: selection.environment=CampaignCatalog.node(site).environment
	var payload: Dictionary={"checkpoint":saved.checkpoint(),"mode":mode,"options":selection}
	return payload if valid_transition(payload) else {}

func resume_saved() -> bool:
	if game.started or (is_instance_valid(game.network) and game.network.active): return false
	var payload:=saved_resume_payload("",true)
	if payload.is_empty(): return false
	var parked := _offline_resume_archive.duplicate(true)
	var original := _offline_resume_original.duplicate(true)
	if not original.is_empty():
		# Reserve all absent crew before a smaller primary can become durable.
		# A failed primary write leaves the original primary plus a safe extra
		# archive; it never removes the only copy of another player's progress.
		if not OfflineCampaignArchive.save_records(state.save_path,parked) or not state._write_checkpoint(payload.checkpoint):
			if state.last_error.is_empty(): state.last_error=LocaleText.text("Kampagnenstand und Sicherung konnten nicht gelesen werden.")
			return false
	var previous_archive := state.offline_crew_archive.duplicate(true)
	state.offline_crew_archive=parked
	if restore(payload): return true
	state.offline_crew_archive=previous_archive
	if not original.is_empty() and not state._write_checkpoint(original): game.notify(state.last_error)
	return false

func ensure_road() -> void:
	if road_open: return
	road_open=true
	if is_instance_valid(game.perimeter): game.perimeter.enter_road_view()
	# The source bunker may be centered or on the east edge, overlapping the
	# road's first metres. Keep its campaign-owned nodes, but its hidden walls
	# must never catch shots or dismounted crew in the dedicated travel world.
	for body: Node in game.find_children("*","StaticBody2D",true,false):
		body.collision_layer=0
		if body is LadderPassage:
			body.set_physics_process(false)
			body.remove_from_group("ladder_passages")
	game.ladders.clear()
	game.world_left=ROAD_START-160
	game.world_right=ROAD_BOUND
	game.scenario_combat.arena_left=game.world_left
	game.scenario_combat.arena_right=ROAD_BOUND
	game.add_terrain(Rect2(game.world_left,430,ROAD_BOUND-game.world_left,24))
	var scenery: Node2D=load("res://scripts/expedition_road_art.gd").new()
	scenery.game=game
	scenery.controller=self
	scenery.z_index=-1
	game.add_child(scenery)
	var air: Node2D=preload("res://scripts/convoy_air_encounters.gd").new()
	air.name="ConvoyAirEncounters"
	air.game=game
	air.controller=self
	game.add_child(air)

func _start_road(after_stop: bool=false,crew_seats: Array=[]) -> void:
	ensure_road()
	game.rounds.running=false
	game.rounds.phase="convoy"
	game.rounds.wave=20
	state.expedition.stage="travel"
	ambushes=0
	if after_stop:
		var planned := int(route.get("ambushes",2))
		while ambushes<planned and lerpf(.20,.70,float(ambushes)/maxi(1,planned-1))<=.5: ambushes+=1
	progress=.5 if after_stop else 0.0
	_spawn_vehicle(Vector2(ROAD_START+(1200 if after_stop else 0),430))
	vehicle.journey_state=Journey.new_state("starting",after_stop or state.completed.has(state.pending_node) or not Journey.breakdown_required(state.pending_node))
	vehicle.driving_enabled=false
	for player in game.players:
		player.position=vehicle.position+Vector2(-90-player.player_id*18,0)
		var slot:=int(player.player_id)-1
		var preferred: String=str(crew_seats[slot]) if slot>=0 and slot<crew_seats.size() else Vehicle.SEAT_ROLES[clampi(slot,0,Vehicle.SEAT_ROLES.size()-1)]
		vehicle.board(player,preferred)
	game.hud.overlay=""
	game.player_camera.update_view(0,true)
	game.notify(LocaleText.text("Konvoi unterwegs · A/D fahren · E aussteigen · Karte: M"))

func _start_occupation() -> void:
	game.rounds.running=false
	game.rounds.phase="occupation"
	game.rounds.wave=1
	state.expedition.stage="occupation"
	_spawn_vehicle(Vector2(game.scenario_bunker.room_right+240,430))
	vehicle.remove_from_group("walls")
	for player in game.players:
		player.position=vehicle.position+Vector2(80+player.player_id*30,0)
	var count: int=0 if state.completed.has(state.pending_node) else int(CampaignCatalog.objective(state.pending_node).guards) if CampaignCatalog.site_kind(state.pending_node)=="outpost" else int(CampaignCatalog.journey(state.pending_node).guards)
	_spawn_guards(count,game.scenario_bunker.room_right+70,false)
	game.hud.overlay=""
	game.player_camera.update_view(0,true)
	game.notify(LocaleText.text("Gesicherter Ort erreicht · Crewkontakte können nachgeholt werden") if state.completed.has(state.pending_node) else LocaleText.text("Bunker besetzt · Verbliebene Gegner ausschalten, bevor die neue Schicht beginnt"))

func _physics_process(delta: float) -> void:
	if not authoritative() or not is_finite(delta) or delta<=0 or not game.started or not state.active or transitioning: return
	if boarding_active():
		if not crew_ready():
			if vehicle.journey_state.phase=="departure": Journey.change_phase(vehicle.journey_state,"boarding")
		elif vehicle.journey_state.phase=="boarding": Journey.change_phase(vehicle.journey_state,"departure","departure")
		elif float(vehicle.journey_state.phase_time)>=Journey.DEPARTURE_TIME: _launch_journey()
		return
	if stage not in ["travel","stop","occupation"]:
		if outpost_pending() and (game.core.hp<=0 or game.players.all(func(player):return player.is_downed())):
			game.rounds.running=false
			game.rounds.phase="defeat"
			game._finished(false)
		return
	guard_count=_living_guards()
	if game.players.all(func(player):return player.is_downed()):
		vehicle_destroyed()
		return
	_sync_time+=delta
	if _sync_time>=.20:
		_sync_time=0
		_sync_vehicle()
	if stage=="occupation":
		if guard_count==0: _secure_bunker()
		return
	if not is_instance_valid(vehicle): return
	progress=clampf((vehicle.position.x-ROAD_START)/(ROAD_END-ROAD_START),0,1)
	if vehicle.journey_state.phase=="starting":
		if int(vehicle.journey_state.event_serial)==0 and float(vehicle.journey_state.phase_time)>=.12: Journey.event(vehicle.journey_state,"engine_start")
		if float(vehicle.journey_state.phase_time)>=game.travel_cinematic.startup_duration():
			Journey.change_phase(vehicle.journey_state,"driving")
			vehicle.driving_enabled=true
		return
	if vehicle.journey_state.phase=="repair":
		_repair_defense_tick(delta)
		return
	_repair_defense_active=false
	if vehicle.journey_state.phase=="reboarding":
		if crew_ready() and float(vehicle.journey_state.phase_time)>=Journey.REBOARD_TIME:
			Journey.change_phase(vehicle.journey_state,"driving","engine_start")
			vehicle.driving_enabled=true
		return
	if stage=="stop":
		if guard_count==0 and game.hud.overlay!="expedition": _open_panel()
		return
	if not vehicle.journey_state.breakdown_done and progress>=Journey.BREAKDOWN_PROGRESS:
		vehicle.position.x=ROAD_START+(ROAD_END-ROAD_START)*Journey.BREAKDOWN_PROGRESS
		if vehicle.begin_breakdown():
			var count:=2 if connected_crew().size()<=1 else 3
			_spawn_guards(count,vehicle.position.x+300,true,Balance.CONVOY_DEFENSE_MAX_ENEMIES)
			game.notify(LocaleText.text("Reifenpanne · Begleiter decken dich; am Hinterrad E halten" if vehicle.active_defenders()>0 else "Reifenpanne · Ein Spieler wechselt; die übrige Crew gibt Deckung"))
		return
	var planned := 0 if state.completed.has(state.pending_node) else int(route.get("ambushes",2))
	while ambushes<planned and progress>=lerpf(.20,.70,float(ambushes)/maxi(1,planned-1)):
		_spawn_guards(2+mini(ambushes,2),vehicle.position.x+(280 if ambushes==0 else 250),true)
		ambushes += 1
	if not stop_done and not state.expedition.selected_stop.is_empty() and progress>=.5:
		if state.reach_stop():
			# Detour mileage has a real, finite fuel cost in addition to road travel.
			var halt:=CampaignCatalog.stop(state.expedition.selected_stop)
			vehicle.fuel=maxf(0,vehicle.fuel-float(halt.extra_fuel)*float(CampaignCatalog.vehicle_stats(state.expedition.vehicle.upgrades).fuel_multiplier))
			_spawn_guards(int(halt.guards),vehicle.position.x+220,true)
			game.notify(LocaleText.text("Zwischenhalt · Umgebung sichern, dann Beute bergen"))
	if progress>=1.0 and guard_count==0:
		var backup:=_transition_backup()
		_sync_vehicle()
		if not state.arrive_at_destination(game.players,game.upgrades):
			var error: String=state.last_error
			_restore_transition(backup)
			if not error.is_empty(): game.notify(error)
			return
		var selection: Dictionary=state.options.duplicate()
		selection.environment=CampaignCatalog.node(state.pending_node).environment
		if _change_world("occupation",selection,backup):
			Journey.change_phase(vehicle.journey_state,"complete","route_complete")
			vehicle.driving_enabled=false
			if game.combat_events.has_method("record_campaign_event"):
				game.combat_events.record_campaign_event("route_complete",{"fuel":vehicle.fuel})

func _repair_defense_tick(delta: float) -> void:
	if not authoritative() or not is_finite(delta) or delta<=0 or not is_instance_valid(vehicle) or vehicle.destroyed or vehicle.journey_state.phase!="repair": return
	if not _repair_defense_active:
		_repair_defense_active=true
		_repair_guard_clock=0.0
		_repair_guard_batches=0
	if _repair_guard_batches>=Balance.CONVOY_DEFENSE_BATCHES: return
	_repair_guard_clock=minf(Balance.CONVOY_DEFENSE_INTERVAL,_repair_guard_clock+minf(delta,.1))
	if _repair_guard_clock<Balance.CONVOY_DEFENSE_INTERVAL or guard_count>=Balance.CONVOY_DEFENSE_MAX_ENEMIES: return
	_repair_guard_clock=0.0
	var rear: bool=_repair_guard_batches%2==0
	_spawn_guards(2,vehicle.position.x+(-360 if rear else 320),true,Balance.CONVOY_DEFENSE_MAX_ENEMIES)
	_repair_guard_batches+=1
	game.notify(LocaleText.text("Heckangriff · Transporter und Reifenwechsler schützen" if rear else "Verstärkung voraus · Reifenwechsel decken"))

func _spawn_guards(count: int,at_x: float,mobile_target: bool,limit: int=MAX_ROAD_GUARDS) -> void:
	if not authoritative(): return
	count=ceili(count*Balance.wave_multiplier(Balance.active_players(game)))
	if mobile_target: count=mini(count,maxi(0,mini(limit,MAX_ROAD_GUARDS)-_living_guards()))
	var kinds: Array[String]=["rifle_guard","scout","runner","grenadier","strider"]
	var start_x:=clampf(at_x,game.world_left+60,game.world_right-180)
	var spacing:=minf(74.0,(game.world_right-60-start_x)/maxi(1,count-1))
	for index in count:
		var kind: String=kinds[(index+state.completed.size())%kinds.size()]
		var scene: PackedScene=game.ENEMY if not EnemyCatalog.is_human(kind) else load("res://scenes/ground_infantry.tscn")
		var enemy=scene.instantiate()
		enemy.kind=kind
		enemy.game=game
		enemy.wave=mini(8,2+state.completed.size())
		enemy.position=Vector2(start_x+index*spacing,430)
		enemy.attack_direction=-1.0 if mobile_target else 1.0
		enemy.set_meta("expedition_guard",true)
		game.add_child(enemy)
		if mobile_target: enemy.target=vehicle
	guard_count=_living_guards()

func _living_guards() -> int:
	var count:=0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.game==game and not enemy.is_queued_for_deletion() and not enemy.dead: count+=1
	return count

func combat_target_for(enemy: Node2D) -> Node2D:
	if not enemy.get_meta("expedition_guard",false): return null
	if stage=="occupation" or outpost_pending():
		var closest: Node2D
		var distance:=INF
		for player in game.players:
			if not is_instance_valid(player) or not player.can_be_targeted(): continue
			var separation: float=enemy.global_position.distance_squared_to(player.global_position)
			if separation<distance:
				distance=separation
				closest=player
		if is_instance_valid(closest):
			enemy.attack_direction=1.0 if closest.global_position.x>enemy.global_position.x else -1.0
			return closest
	if stage in ["travel","stop"] and is_instance_valid(vehicle) and vehicle.hp>0 and enemy.get_meta("expedition_guard",false):
		var protected_target: Node2D=_repair_defense_target(enemy) if vehicle.journey_state.phase=="repair" else vehicle
		enemy.attack_direction=1.0 if protected_target.global_position.x>enemy.global_position.x else -1.0
		return protected_target
	return null

func _repair_defense_target(enemy: Node2D) -> Node2D:
	var nearest: Node2D=vehicle
	var distance: float=enemy.global_position.distance_squared_to(vehicle.global_position)
	# Only the nearest exposed defender needs a sight ray. Mounted crew stays
	# behind the hull; an invisible/blocked ally never redirects hostile shots.
	for group: Array in [game.players,vehicle.defenders]:
		for candidate in group:
			if not is_instance_valid(candidate) or not candidate is Node2D or candidate.is_queued_for_deletion() or candidate.get("game")!=game: continue
			if not candidate.has_method("can_be_targeted") or not candidate.can_be_targeted() or is_instance_valid(candidate.get("mounted_turret")): continue
			if candidate.global_position.distance_squared_to(vehicle.global_position)>350.0*350.0: continue
			var separation: float=enemy.global_position.distance_squared_to(candidate.global_position)
			if separation<distance:
				distance=separation
				nearest=candidate
	if nearest==vehicle: return vehicle
	var origin: Vector2=enemy.global_position-Vector2(0,30)
	var weapon=enemy.get("weapon_part")
	if is_instance_valid(weapon) and weapon is Node2D: origin=weapon.global_position
	var aim: Vector2=nearest.attack_point() if nearest.has_method("attack_point") else nearest.global_position-Vector2(0,23)
	var query:=PhysicsRayQueryParameters2D.create(origin,aim,1|2|8)
	query.hit_from_inside=true
	if enemy is CollisionObject2D: query.exclude=[enemy.get_rid()]
	var hit:=enemy.get_world_2d().direct_space_state.intersect_ray(query)
	return nearest if not hit.is_empty() and hit.collider==nearest else vehicle

func _secure_bunker() -> void:
	var backup:=_transition_backup()
	var revisit: bool=state.completed.has(state.pending_node)
	_sync_vehicle()
	if not state.secure_destination(game.players,game.upgrades):
		var error: String=state.last_error
		_restore_transition(backup)
		if not error.is_empty(): game.notify(error)
		return
	if revisit:
		_change_world("preparation",game.scenario_options,backup)
		return
	_apply_delivery()
	state.mission_start()
	if game.combat_events.has_method("record_campaign_event"):
		game.combat_events.record_campaign_event("occupation_complete",{"cargo_count":CampaignCatalog.cargo_count(state.take_cargo())})
	if CampaignCatalog.site_kind(state.pending_node)=="outpost":
		game.core.repair_work=0
		game.rounds.running=false
		game.rounds.phase="occupation"
		game.notify(LocaleText.text("Außenposten geräumt · Anlage am Bunkerkern wieder in Betrieb nehmen"))
		return
	game.rounds.start_round(game.player_count)
	game.notify(LocaleText.text("Bunker eingenommen · Fahrzeugfracht eingelagert · Neue Schicht beginnt"))

func _apply_delivery() -> void:
	if not authoritative() or game.has_meta("expedition_delivery"): return
	game.set_meta("expedition_delivery",true)
	var cargo:=state.take_cargo()
	var index:=0
	for kind in cargo:
		var amount: int=cargo[kind]
		for supply in get_tree().get_nodes_in_group("supplies"):
			if supply.game!=game or supply.is_queued_for_deletion() or supply.kind!=kind: continue
			var stored:=mini(amount,maxi(0,Balance.PICKUP_STACK_MAX-int(supply.amount)))
			supply.amount+=stored
			amount-=stored
			supply.queue_redraw()
			if amount<=0: break
		while amount>0:
			var stored:=mini(amount,Balance.PICKUP_STACK_MAX)
			if not is_instance_valid(_new_supply(kind,stored,index)):
				if not Storage.add_reserve(game,kind,amount): push_error("Invalid deployment storage reserve")
				break
			amount-=stored
			index+=1
	if is_instance_valid(vehicle):
		vehicle.cargo.clear()
		vehicle.remove_from_group("walls")

func vehicle_destroyed() -> void:
	if not authoritative() or not stage in ["travel","stop","occupation"]: return
	if is_instance_valid(vehicle):
		if vehicle.journey_state.phase!="failed": Journey.change_phase(vehicle.journey_state,"failed","failed")
		vehicle.driving_enabled=false
	_sync_vehicle()
	state.fail_journey()
	game.rounds.phase="convoy"
	_open_panel()
	game.notify(LocaleText.text("Konvoi verloren · Am letzten gesicherten Reisepunkt erneut starten"))

func can_retry_journey() -> bool:
	return stage=="failed" or (stage in ["travel","stop"] and is_instance_valid(vehicle) and vehicle.fuel<=0)

func status_text() -> String:
	if stage=="failed": return LocaleText.text("Konvoi verloren · Letzten Reisepunkt wiederholen")
	if can_retry_journey(): return LocaleText.text("Tank leer · Auf der Karte den letzten gesicherten Reisepunkt wiederholen")
	if is_instance_valid(vehicle):
		match str(vehicle.journey_state.phase):
			"boarding": return LocaleText.format("Einsteigen · %d / %d Crewmitglieder an Bord",[connected_crew().filter(func(player):return vehicle.seat_for(player)!=null).size(),connected_crew().size()])
			"departure": return LocaleText.text("Crew bereit · Abfahrt")
			"starting": return LocaleText.text("Motor startet · Gleich geht es los")
			"repair": return vehicle.service_prompt()
			"reboarding": return LocaleText.text("Reparatur beendet · Alle einsteigen")
	if stage=="occupation": return LocaleText.format("Bunker sichern · %d Gegner verblieben",guard_count)
	if stage=="stop": return LocaleText.format("Zwischenhalt sichern · %d Gegner verblieben",guard_count)
	if stage=="travel": return LocaleText.format("Unterwegs · %d %% · %d Feindkontakte",[roundi(progress*100),guard_count])
	return LocaleText.text("Transporter vorbereiten · Fracht, Treibstoff und Route prüfen")

func capture_state() -> Dictionary:
	if authoritative() and can_manage() and not CampaignCatalog.all_complete(state.completed):
		var stock:=_capture_stock()
		if CampaignState.valid_stock(stock): state.expedition.garage_stock=stock
	return {"checkpoint":state.checkpoint(),"road":road_open,"progress":progress,"ambushes":ambushes,"guards":guard_count,"stop_done":stop_done} if state.active else {}

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary: return false
	if data.is_empty(): return true
	if data.size()!=6 or not data.get("checkpoint") is Dictionary or not CampaignState.valid_checkpoint(data.checkpoint): return false
	if not data.get("road") is bool or not data.get("stop_done") is bool: return false
	if not (data.get("progress") is float or data.get("progress") is int) or not is_finite(float(data.progress)) or data.progress<0 or data.progress>1: return false
	return data.get("ambushes") is int and data.ambushes>=0 and data.ambushes<=4 and data.get("guards") is int and data.guards>=0 and data.guards<=32

func apply_state(data: Dictionary) -> void:
	if data.is_empty(): return
	state._restore(data.checkpoint)
	for site in state.completed: CharacterCatalog.unlock_for_site(site)
	progress=float(data.progress)
	ambushes=int(data.ambushes)
	guard_count=int(data.guards)
	stop_done=bool(data.stop_done)
	if data.road: ensure_road()
	for candidate in get_tree().get_nodes_in_group("convoy_vehicles"):
		if candidate.game==game: vehicle=candidate

func _new_supply(kind: String,amount: int,_index: int) -> Supply:
	var medic=game.get("medic")
	if not is_instance_valid(medic): return null
	var positions:=Storage._positions(game,medic)
	if positions.is_empty(): return null
	return _supply_at(kind,amount,positions[0])

func _supply_at(kind: String,amount: int,point: Vector2) -> Supply:
	# Mirror reserves a set of mutually clear slots once, before creating any
	# chests. Repeated broad terrain queries would stall every garage action.
	var crate=preload("res://scripts/convoy_supply.gd").new()
	crate.game=game
	crate.kind=kind
	crate.amount=amount
	crate.position=point
	game.add_child(crate)
	return crate

func outpost_pending() -> bool:
	return state!=null and state.active and stage=="defense" and not state.completed.has(state.pending_node) and CampaignCatalog.site_kind(state.pending_node)=="outpost"

func outpost_prompt() -> String:
	var objective:=CampaignCatalog.objective(state.pending_node)
	return LocaleText.text(str(objective.title))+"\n"+LocaleText.text("Gegner ausschalten, dann E halten · Anlage sichern")

func secure_outpost(worker: Node,delta: float) -> void:
	if not authoritative() or not outpost_pending() or _living_guards()>0 or not is_instance_valid(worker) or not worker in game.players or not worker.can_act(): return
	if not is_finite(delta) or delta<=0 or game.core.hp<=0 or worker.global_position.distance_to(game.core.interaction_point())>120: return
	game.core.repair_work=clampf(game.core.repair_work+delta/float(CampaignCatalog.objective(state.pending_node).hold_time),0,1)
	if game.core.repair_work<1: return
	CampaignSalvage.recover_remaining(game)
	_sync_vehicle()
	var result:=state.complete_outpost(state.mission_id,0,true,game.players,game.upgrades,_capture_stock())
	if result.is_empty():
		game.core.repair_work=0
		game.notify(state.last_error)
		return
	_site_secured()
	_mirror_stock()
	game.rounds.running=false
	game.rounds.phase="victory"
	game._finished(true)

func _site_secured() -> void:
	if is_instance_valid(game.solo_story) and game.solo_story.enabled:
		game.solo_story.site_secured(state.current_node)
	else:
		for id in CharacterCatalog.unlock_for_site(state.current_node):
			game.notify(LocaleText.format("Crewmitglied gerettet: %s · Beim nächsten Spiel wählbar",CharacterCatalog.data(id).title))

	if CampaignCatalog.all_complete(state.completed) and game.combat_events.has_method("record_campaign_event"):
		game.combat_events.record_campaign_event("campaign_complete")

func retry_defense() -> bool:
	if not authoritative() or not state.active or stage!="defense" or transitioning: return false
	var backup:=_transition_backup()
	state.fail_mission()
	var selection: Dictionary=state.options.duplicate()
	if state.pending_node!=CampaignCatalog.ENTRY: selection.environment=CampaignCatalog.node(state.pending_node).environment
	return _change_world("defense",selection,backup)

func restart_payload() -> Dictionary:
	# Build from a copy: asking for confirmation or a new generation must not
	# commit unfinished XP, research, cargo, salvage or roadside rewards.
	if state==null or not state.active or transitioning: return {}
	if game.rounds.phase=="victory" or game.hud.overlay in ["victory","campaign_victory"]: return {}
	var checkpoint: Dictionary=state.checkpoint()
	if not CampaignState.valid_checkpoint(checkpoint): return {}
	var saved := CampaignState.new(state.save_path,false)
	saved._restore(checkpoint)
	var mode: String=saved.expedition.stage
	if mode in ["travel","stop","occupation","failed"]:
		if saved.retry_journey().is_empty(): return {}
		mode="travel"
	elif mode in ["preparation","map"]:
		mode="preparation"
	elif mode!="defense" or saved.completed.has(saved.pending_node):
		return {}
	var selection: Dictionary=saved.options.duplicate()
	var site: String=saved.pending_node if mode=="defense" else saved.current_node
	if site!=CampaignCatalog.ENTRY: selection.environment=CampaignCatalog.node(site).environment
	var payload := {"checkpoint":saved.checkpoint(),"mode":mode,"options":selection}
	return payload if valid_transition(payload) else {}
