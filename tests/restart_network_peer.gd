extends "res://tests/network_gameplay_peer.gd"
## Restart authority and campaign retry through two authenticated ENet peers.
var crew_campaign_id := ""
var guest_save_path := ""
var guest_save_hash := ""

func restarted(scene_id: int,generation: int,stage: String) -> bool:
	return await wait_for(func(): return playing() and game.get_instance_id()!=scene_id and game.network._generation==generation and game.expedition.stage==stage,"actual party restart into "+stage,12.0)

func freeze_workers() -> void:
	game.rounds.running=false
	game.expedition.set_physics_process(false)
	for worker in game.players:
		worker.set_physics_process(false)
		worker.get_node("WorkerWeapon").set_physics_process(false)
	if is_instance_valid(game.expedition.vehicle): game.expedition.vehicle.set_physics_process(false)

func set_local_preferences() -> void:
	game.set_camera_mode("overview")
	game.set_camera_zoom(1.7 if role=="host" else 2.1)
	game.audio.set_sfx_volume(.43 if role=="host" else .17)
	game.weather.set_reduced_effects(role=="host")
	game.combat_events.record_character_dance_level("mara" if role=="host" else "ivo",10)
	game.combat_events.unlock("armor" if role=="host" else "craft_five")

func check_local_preferences() -> void:
	check(game.camera_settings().mode=="overview" and is_equal_approx(game.camera_settings().zoom,1.7 if role=="host" else 2.1),"Restart preserves each peer's independent camera choices")
	check(is_equal_approx(game.audio.sfx_volume,.43 if role=="host" else .17) and game.weather.reduced_effects==(role=="host"),"Restart preserves each peer's local audio and weather choices")
	check(game.combat_events.dance_level("mara" if role=="host" else "ivo")==10,"Restart preserves local cosmetic unlocks without profile writes")
	check(not game.combat_events.earned_this_shift.has("armor" if role=="host" else "craft_five"),"Local old achievement is not announced as a fresh party reward")

func host_run() -> void:
	game.hud.scenario_options=OPTIONS.duplicate()
	game.network.host_room("")
	publish("room",{"code":game.network.room_code})
	if not await barrier("joined") or not await wait_for(func():return game.network.peer_connected,"guest authenticated"):
		await finish(false,"lobby"); return
	game.network.start_match(OPTIONS,["mara","ivo"])
	if not await wait_for(playing,"initial world") or not await barrier("guest_started"):
		await finish(false,"initial world"); return
	freeze_workers()
	set_local_preferences()
	crew_campaign_id=game.campaign.campaign_id
	var session_id: int=game.network.get_instance_id()
	var scene_id: int=game.get_instance_id()
	var generation: int=game.network._generation
	publish("authority_ready")
	if not await barrier("guest_denied"):
		await finish(false,"guest authority check"); return
	await delay(.35)
	check(game.get_instance_id()==scene_id and game.network._generation==generation,"Guest restart command cannot reset the host's party")
	game.players[0].progression.level=4
	game.players[0].progression.skill_points=3
	game.players[0].inventory={"ore":5}
	publish("defense_restart",{"generation":generation+1})
	check(game.restart(),"Host can restart an unfinished mission from the game API")
	game.network.restart_match()
	if not await restarted(scene_id,generation+1,"defense") or not await barrier("guest_defense_seen"):
		await finish(false,"defense restart"); return
	freeze_workers()
	check(game.network.get_instance_id()==session_id and game.campaign.campaign_id==crew_campaign_id,"Mission restart retains the authenticated transport and campaign identity")
	check(game.players.size()==2 and game.players[1].character_id=="ivo" and game.players[0].progression.level==1 and game.players[0].inventory.is_empty(),"Mission restart retains crew and resets only uncommitted progression")
	check_local_preferences()
	game.rounds.wave=20
	game.players[0].progression.level=3
	game.players[0].progression.skill_points=2
	game.players[1].progression.level=2
	game.players[1].progression.skill_points=1
	game.upgrades.points=7
	game.upgrades.owned["boots"]=true
	check(game.expedition.on_victory(),"Host banks a real campaign victory before travelling")
	check(game.campaign.select_destination("harbor") and game.campaign.select_stop("harbor:weapon"),"Host selects the next journey and weapon cache")
	check(game.campaign.prepare_expedition(game.players,game.upgrades) and not game.campaign.begin_journey().is_empty(),"Host records a valid departure checkpoint")
	check(game.campaign.reach_stop() and not game.campaign.secure_stop().is_empty(),"Host secures a finite roadside reward")
	game.campaign.expedition.vehicle.hp=123
	game.campaign.expedition.vehicle.fuel=1
	scene_id=game.get_instance_id()
	generation=game.network._generation
	publish("travel_restart",{"generation":generation+1})
	check(game.restart(),"Host can retry travel from its last secured checkpoint")
	if not await restarted(scene_id,generation+1,"travel") or not await barrier("guest_travel_seen"):
		await finish(false,"travel restart"); return
	freeze_workers()
	check(game.campaign.campaign_id==crew_campaign_id and game.campaign.pending_node=="harbor" and game.campaign.completed==[CampaignCatalog.ENTRY],"Travel retry preserves completed campaign sites and selected destination")
	check(game.players[0].progression.level==3 and game.players[1].progression.level==2 and game.upgrades.has_upgrade("boots") and game.upgrades.points==7,"Travel retry restores banked levels and portable research")
	check(game.expedition.stop_done and game.campaign.expedition.claimed_stops.has("harbor:weapon") and game.campaign.expedition.epic_weapons.size()==1,"Travel retry preserves the claimed weapon cache exactly once")
	check(game.expedition.vehicle.position.x>1900 and game.expedition.vehicle.hp>123 and game.expedition.vehicle.fuel>1,"Travel retry restores the actual secured halfway position and vehicle")
	check_local_preferences()
	publish("host_passed")
	if not await barrier("guest_passed"):
		await finish(false,"guest verification"); return
	publish("finish")
	if not await wait_for(func():return not game.network.peer_connected and game.network.connected_player_count()==1,"last guest leaves the running party"):
		await finish(false,"guest departure"); return
	check(game.network.state=="reconnecting" and not game.restart(),"A host cannot restart while its absent guest still has a reconnect reservation")
	# The transport departure above is real. Expire only its configured grace
	# deadline; avoid adding thirty seconds of waiting to each regression run.
	for link: Dictionary in game.network._slots.values(): link.reconnect_until=game.network._clock
	game.network._expire_missing_slots()
	check(game.network._slots.is_empty() and game.network.state=="playing","After the reconnect grace period the host remains an active solo authority")
	scene_id=game.get_instance_id()
	generation=game.network._generation
	check(game.restart(),"An already started host may restart after its last guest leaves")
	if not await wait_for(func():return game.get_instance_id()!=scene_id and game.started and game.network.state=="playing" and not game.network._loading and not paused,"lone host completes restart readiness"):
		await finish(false,"lone host readiness"); return
	freeze_workers()
	check(game.network._generation==generation+1 and not game.network.peer_connected and game.campaign.campaign_id==crew_campaign_id and game.expedition.stage=="travel","Lone-host restart completes once and retains its current campaign")
	check(game.campaign.completed==[CampaignCatalog.ENTRY] and game.campaign.expedition.claimed_stops.has("harbor:weapon"),"Lone-host retry retains completed sites and finite rewards")
	check(game.campaign.arrive_at_destination(),"Lone host can advance its existing journey to occupation")
	scene_id=game.get_instance_id()
	var selection: Dictionary=game.scenario_options.duplicate()
	selection.environment=CampaignCatalog.node("harbor").environment
	check(game.expedition._change_world("occupation",selection),"Lone host can transition to the selected destination without a remote ready packet")
	if not await wait_for(func():return game.get_instance_id()!=scene_id and game.started and game.expedition.stage=="occupation" and not game.network._loading and not paused,"lone host reaches occupied bunker"):
		await finish(false,"lone host expedition transition"); return
	freeze_workers()
	check(game.scenario_options.environment==selection.environment and game.campaign.campaign_id==crew_campaign_id and game.campaign.completed==[CampaignCatalog.ENTRY],"Lone-host transition preserves the campaign and uses its destination environment")
	game.network._loading=true
	check(not game.expedition._change_world("occupation",selection) and not game.expedition.transitioning and not game._restart_pending,"Rejected transitions clear their pending flag instead of wedging the controller")
	game.network._loading=false
	await finish(failures==0,"host-authorized mission and campaign restart")

func guest_run() -> void:
	guest_save_path=ProjectSettings.globalize_path(CampaignState.SAVE_PATH)
	var guest_save:=FileAccess.open(guest_save_path,FileAccess.WRITE)
	guest_save.store_string("guest's independent local campaign")
	guest_save.close()
	guest_save_hash=FileAccess.get_sha256(guest_save_path)
	check(game.campaign.persistence_enabled,"Guest fixture starts with normal persistence inside an isolated profile")
	if not await barrier("room"):
		await finish(false,"host room"); return
	game.network.join_room("",str(read_stage("room").code))
	if not await wait_for(func():return game.network.state=="lobby" and game.network.peer_connected,"guest authenticated"):
		await finish(false,"guest lobby"); return
	publish("joined")
	if not await wait_for(playing,"initial world"):
		await finish(false,"initial world"); return
	set_local_preferences()
	var session_id: int=game.network.get_instance_id()
	var token: String=game.network._client_token
	var scene_id: int=game.get_instance_id()
	var generation: int=game.network._generation
	crew_campaign_id=game.campaign.campaign_id
	publish("guest_started")
	if not await barrier("authority_ready"):
		await finish(false,"authority fixture"); return
	check(not game.restart(),"Guest game API rejects a party restart")
	game.network.send_command("restart")
	publish("guest_denied")
	if not await barrier("defense_restart") or not await restarted(scene_id,generation+1,"defense"):
		await finish(false,"defense restart"); return
	check(game.network.get_instance_id()==session_id and game.network._client_token==token,"Guest retains its authenticated session across restart")
	check(game.players.size()==2 and game.players[0].progression.level==1 and game.players[1].character_id=="ivo" and game.players[0].inventory.is_empty(),"Guest receives the same fresh mission and chosen crew")
	check_local_preferences()
	check(not game.campaign.persistence_enabled and FileAccess.get_sha256(guest_save_path)==guest_save_hash,"Mission retry cannot overwrite the guest's own saved campaign")
	scene_id=game.get_instance_id()
	generation=game.network._generation
	publish("guest_defense_seen")
	if not await barrier("travel_restart") or not await restarted(scene_id,generation+1,"travel"):
		await finish(false,"travel restart"); return
	check(game.network.get_instance_id()==session_id and game.network._client_token==token,"Campaign retry retains the original guest token")
	check(game.campaign.pending_node=="harbor" and game.campaign.completed==[CampaignCatalog.ENTRY] and game.scenario_options==OPTIONS,"Guest receives the current campaign boundary and departure scenery")
	check(game.players[0].progression.level==3 and game.players[1].progression.level==2 and game.upgrades.has_upgrade("boots"),"Guest receives banked progression rather than a new campaign")
	check(game.campaign.expedition.claimed_stops.has("harbor:weapon") and game.campaign.expedition.epic_weapons.size()==1 and game.expedition.stop_done,"Guest sees the same single claimed roadside reward")
	check_local_preferences()
	check(not game.campaign.persistence_enabled and FileAccess.get_sha256(guest_save_path)==guest_save_hash,"Journey retry cannot overwrite the guest's own saved campaign")
	publish("guest_travel_seen")
	if not await barrier("host_passed"):
		await finish(false,"host verification"); return
	publish("guest_passed")
	if not await barrier("finish"):
		await finish(false,"completion"); return
	scene_id=game.get_instance_id()
	check(game.return_to_menu(),"Guest can leave the party independently through the menu API")
	if not await wait_for(func():return not game.started and game.get_instance_id()!=scene_id and game.hud.overlay=="menu","guest's local main menu"):
		await finish(false,"guest local menu"); return
	check(game.campaign.persistence_enabled and not game.network.active and FileAccess.get_sha256(guest_save_path)==guest_save_hash,"Returning to menu restores local saving and retains the guest's independent campaign")
	await finish(failures==0,"guest follows authoritative retries and retains local preferences")
