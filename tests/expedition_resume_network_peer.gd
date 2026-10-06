extends "res://tests/network_gameplay_peer.gd"
## A real online victory writes checkpoints. Fresh host/guest processes then
## resume each prepared boundary through the production lobby action.
var mode := OS.get_environment("LASTSHIFT_RESUME_CASE")
var save_directory := OS.get_environment("LASTSHIFT_RESUME_SAVES")
var party_size := maxi(2,int(OS.get_environment("LASTSHIFT_RESUME_PLAYERS")))
var slot := maxi(1,int(OS.get_environment("LASTSHIFT_PARTY_SLOT")))
var resume_relay := OS.get_environment("LASTSHIFT_RESUME_RELAY")
const GUEST_BARRIERS := ["joined","guest_started","write_seen","resume_seen","guest_checked","guest_passed","corrupt_seen"]

func publish(stage: String,values: Dictionary={}) -> void:
	super.publish(stage+str(slot) if party_size>2 and slot>1 and stage in GUEST_BARRIERS else stage,values)

func barrier(stage: String,timeout: float=8.0) -> bool:
	if party_size>2 and slot==1 and stage in GUEST_BARRIERS:
		for guest_slot in range(2,party_size+1):
			if not await super.barrier(stage+str(guest_slot),timeout): return false
		return true
	return await super.barrier(stage,timeout)

func same_saved_values(actual: Dictionary, expected: Dictionary) -> bool:
	# JSON reads whole-number cargo and magazine fields as floats. Production
	# vehicle code canonicalizes those fields to ints on its first sync tick.
	var matches: bool = JSON.parse_string(JSON.stringify(actual))==JSON.parse_string(JSON.stringify(expected))
	if not matches: print("RESUME_VALUE_DIFF actual=",JSON.stringify(actual)," expected=",JSON.stringify(expected))
	return matches

func connected_world() -> bool:
	return game.started and game.network.state=="playing" and not game.network._loading and game.network.peer_connected

func store_case(id: String, checkpoint: Dictionary) -> void:
	check(CampaignState.valid_checkpoint(checkpoint), id+" prepared checkpoint is valid")
	var file := FileAccess.open(save_directory.path_join(id+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(checkpoint))
	file.close()

func prepare_files() -> void:
	var state: CampaignState=game.campaign
	state.expedition.vehicle.ammo=17
	state.expedition.vehicle.reserve=23
	check(state.save_checkpoint(),"Online host persists finite vehicle ammunition")
	store_case("preparation",state.checkpoint())
	check(not state.begin_journey().is_empty(),"Online campaign records a durable departure")
	store_case("travel",state.checkpoint())
	check(state.reach_stop(),"Prepared guarded stop retains its departure boundary")
	store_case("stop",state.checkpoint())
	check(not state.secure_stop().is_empty(),"Secured cache commits its earned weapon once")
	store_case("after_stop",state.checkpoint())
	var solo:=state.checkpoint()
	solo.player_count=1
	for id in range(2,party_size+1):
		solo.snapshots.erase(str(id))
		solo.expedition.departure.snapshots.erase(str(id))
	store_case("solo",solo)
	check(state.arrive_at_destination(),"Prepared occupation keeps the secured stop boundary")
	store_case("occupation",state.checkpoint())
	var failed:=state.checkpoint()
	failed.expedition.stage="failed"
	store_case("failed",failed)
	check(state.secure_destination(),"Secured bunker records its deployment cargo")
	store_case("defense",state.checkpoint())
	var complete:=state.checkpoint()
	complete.completed.clear()
	complete.claimed_missions.clear()
	complete.unlocked_routes.clear()
	complete.blueprints.clear()
	complete.banked_salvage=0
	complete.total_salvage_earned=0
	for site: Dictionary in CampaignCatalog.NODES:
		complete.completed.append(site.id)
		complete.claimed_missions.append(complete.campaign_id+":"+site.id)
		if int(site.cost)>0:
			complete.unlocked_routes.append(site.id)
			complete.total_salvage_earned+=int(site.cost)
		if not str(site.blueprint).is_empty(): complete.blueprints.append(site.blueprint)
	complete.current_node=CampaignCatalog.NODES[-1].id
	complete.pending_node=complete.current_node
	complete.expedition.stage="preparation"
	complete.expedition.departure={}
	store_case("complete",complete)
	DirAccess.copy_absolute(save_directory.path_join("preparation.json"),save_directory.path_join("backup.json.bak"))
	for id in ["backup","corrupt"]:
		var file:=FileAccess.open(save_directory.path_join(id+".json"),FileAccess.WRITE)
		file.store_string("incomplete checkpoint")
		file.close()

func host_run() -> void:
	game.campaign.save_path=save_directory.path_join("online-written.json" if mode=="write" else mode+".json")
	check(game.expedition.saved_resume_payload().is_empty(),"No-profile-save blocks profile reads until the isolated fixture explicitly opts in")
	game.campaign.persistence_enabled=true
	game.network.host_room(resume_relay)
	if not await wait_for(func():return game.network.state=="lobby" and not game.network.room_code.is_empty(),"isolated resume room creation"):
		await finish(false,"room creation"); return
	check(not game.network.resume_campaign() and not game.started and game.network._generation==0,"Resume requires an authenticated connected partner")
	publish("room",{"code":game.network.room_code})
	if not await barrier("joined") or not await wait_for(func():return game.selected_characters[1]=="mara","guest lobby identity"):
		await finish(false,"lobby"); return
	if mode=="write":
		game.network.start_match(OPTIONS,["branko","ivo"])
		if not await wait_for(connected_world,"writer live world") or not await barrier("guest_started"):
			await finish(false,"writer start"); return
		game.rounds.running=false
		game.rounds.wave=20
		game.upgrades.points=19
		game.upgrades.owned["convoy_mg"]=true
		for index in party_size:
			game.players[index].progression.level=3+index
			game.players[index].progression.skill_points=2+index
			game.players[index].progression.xp=11.0+index
		game.players[0].inventory={"steel":3,"ammo":2}
		check(game.expedition.on_victory(),"Actual online wave20 callback writes host campaign progress")
		check(game.expedition.handle_command("route",{"id":"harbor"},1) and game.expedition.handle_command("stop",{"id":"harbor:weapon"},1),"Host persists chosen route and cache")
		check(game.expedition.handle_command("load",{"kind":"steel","amount":2},1),"Real garage transfer persists finite cargo")
		prepare_files()
		publish("written")
		if not await barrier("write_seen"): await finish(false,"writer guest"); return
	else:
		var before:=FileAccess.get_sha256(game.campaign.save_path)
		var initial_id: String=game.campaign.campaign_id
		var payload: Dictionary=game.expedition.saved_resume_payload(game.selected_characters.slice(1,party_size))
		check(FileAccess.get_sha256(game.campaign.save_path)==before and game.campaign.campaign_id==initial_id,"Reading a lobby continuation changes neither disk nor live campaign")
		if mode=="corrupt":
			check(payload.is_empty() and not game.network.resume_campaign() and game.network.state=="lobby" and game.network._generation==0,"Corrupt save leaves both peers in their existing lobby")
			publish("corrupt_checked")
			if not await barrier("corrupt_seen"): await finish(false,"corrupt guest"); return
		else:
			check(not payload.is_empty(),"Persisted checkpoint produces a validated shared transition")
			if party_size==4 and mode!="solo":
				check(game.expedition.saved_resume_payload(["mara"]).is_empty() and "4" in game.campaign.last_error,"A four-person save cannot silently discard absent crew progression")
				payload=game.expedition.saved_resume_payload(game.selected_characters.slice(1,party_size))
				check(not payload.is_empty() and game.campaign.last_error.is_empty(),"The full crew can retry safely after a smaller-lobby rejection")
			publish("expected",{"mode":mode,"stage":payload.checkpoint.expedition.stage,"characters":payload.checkpoint.character_ids,"vehicle":payload.checkpoint.expedition.vehicle,"stock":payload.checkpoint.expedition.garage_stock,"completed":payload.checkpoint.completed.size(),"weapons":payload.checkpoint.expedition.epic_weapons})
			await delay(.05)
			var panel=game.hud.network_panel
			check(is_instance_valid(panel) and panel.resume_button.visible and not panel.resume_button.disabled and not panel.resume_button.get_rect().intersects(panel.start_button.get_rect()),"Host lobby exposes a separate enabled continuation action")
			panel.resume_button.pressed.emit()
			if not await wait_for(connected_world,"resumed host world") or not await barrier("resume_seen"):
				await finish(false,"resume"); return
			game.rounds.running=false
			if mode in ["travel","stop","occupation","after_stop","solo","failed"]:
				if not await wait_for(func():return game.expedition.stage=="travel" and is_instance_valid(game.expedition.vehicle) and game.expedition.vehicle.journey_state.phase=="driving" and game.expedition.vehicle.driving_enabled,"resumed actual engine interval completes"):
					await finish(false,"resume starting"); return
			else: await delay(.4)
			check(game.campaign.campaign_id==payload.checkpoint.campaign_id and game.campaign.completed.size()==int(read_stage("expected").completed),"Resume retains campaign identity and completed sites")
			for index in party_size:
				check(game.players[index].progression.level==(1 if mode=="solo" and index>0 else 3+index),"Saved P%d progression persists; new solo partners start at level one"%(index+1))
			check(same_saved_values(game.campaign.expedition.vehicle,payload.checkpoint.expedition.vehicle) and same_saved_values(game.campaign.expedition.garage_stock,payload.checkpoint.expedition.garage_stock),"Finite vehicle fuel, cargo, ammo and garage stock survive continuation after the first sync tick")
			if mode=="complete": check(paused and game.hud.overlay=="campaign_victory" and game.rounds.phase=="victory","Completed campaign remains a terminal victory after host load")
			publish("host_checked")
			if not await barrier("guest_checked"): await finish(false,"resume assertions"); return
	publish("finish")
	if not await barrier("guest_passed"): await finish(false,"guest final"); return
	await finish(failures==0,"durable online campaign "+mode)

func guest_run() -> void:
	var untouched:="user://campaign_v1.json"
	var file:=FileAccess.open(untouched,FileAccess.WRITE)
	file.store_string("guest's independent local campaign")
	file.close()
	var original_hash:=FileAccess.get_sha256(untouched)
	game.network.join_room(resume_relay,str(read_stage("room").get("code","")))
	if not await wait_for(func():return game.network.state=="lobby" and game.network.peer_connected,"guest lobby"):
		await finish(false,"join"); return
	check(not game.network.resume_campaign() and not game.started,"Guest cannot initiate or load the host's checkpoint")
	game.network.send_command("character",{"id":"mara"})
	publish("joined")
	if mode=="write":
		if not await wait_for(connected_world,"writer guest world"): await finish(false,"writer world"); return
		publish("guest_started")
		if not await barrier("written"): await finish(false,"saved files"); return
		publish("write_seen")
	elif mode=="corrupt":
		if not await barrier("corrupt_checked"): await finish(false,"corrupt check"); return
		check(not game.started and game.network.state=="lobby","Invalid host checkpoint never replaces guest lobby")
		publish("corrupt_seen")
	else:
		if not await barrier("expected") or not await wait_for(func():return connected_world() and game.network.received_snapshots>=2,"fresh guest receives saved world"):
			await finish(false,"saved guest"); return
		var expected:=read_stage("expected")
		check(game.selected_characters==expected.characters and game.players.size()==party_size,"Both saved crew identities arrive with the new authenticated session")
		check(same_saved_values(game.campaign.expedition.vehicle,expected.vehicle) and same_saved_values(game.campaign.expedition.garage_stock,expected.stock),"Guest sees exact finite checkpoint vehicle and garage stock")
		check(game.campaign.expedition.epic_weapons==expected.weapons and game.campaign.completed.size()==int(expected.completed),"Claimed loot and secured sites replicate without being awarded again")
		if mode in ["travel","stop","occupation","after_stop","solo","failed"]:
			if not await wait_for(func():return game.expedition.vehicle.journey_state.phase=="driving" and game.expedition.vehicle.driving_enabled,"replicated resume engine-start interval"):
				await finish(false,"guest resume starting"); return
			check(game.expedition.stage=="travel" and game.players[0].mounted_turret==game.expedition.vehicle.driver_seat and game.players.all(func(player):return player.mounted_turret==game.expedition.vehicle.seats[player.player_id-1]),"Unsafe road states resume at their safe boundary with both occupied seats")
			check(game.expedition.stop_done==(mode in ["occupation","after_stop","solo","failed"]),"A secured cache remains secured on resumed travel")
		if mode=="complete": check(paused and game.hud.overlay=="campaign_victory" and not game.rounds.running,"Guest also receives the terminal campaign result")
		if mode=="defense": check(game.scenario_options.environment=="abandoned_harbor" and game.expedition.stage=="defense" and game.rounds.wave==1,"Saved destination resumes its next bunker and wave one")
		publish("resume_seen")
		if not await barrier("host_checked"): await finish(false,"host checks"); return
		publish("guest_checked")
	if not await barrier("finish"): await finish(false,"finish"); return
	check(FileAccess.get_sha256(untouched)==original_hash,"Receiving a host campaign never overwrites the guest's local save")
	publish("guest_passed")
	await finish(failures==0,"durable online campaign "+mode)
