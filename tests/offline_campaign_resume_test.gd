extends SceneTree
## Genuine menu Continue from finite 2/3/4-person saved checkpoints.
## Persistence exceptions are restricted to this test's own artifact directory.
const Archive := preload("res://scripts/offline_campaign_archive.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var game: Node
var checks := 0
var failures := 0
var fixture_root := ""
var cases: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(detail)

func same(left: Variant,right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left))==JSON.parse_string(JSON.stringify(right))

func frames(count: int=3) -> void:
	for _frame in count: await process_frame

func _freeze() -> void:
	game.set_process(false)
	game.rounds.running=false
	game.rounds.set_process(false)
	game.expedition.set_process(false)
	game.solo_story.set_process(false)
	game.network.set_process(false)
	game.social_bridge.set_process(false)
	for node: Node in game.find_children("*","Node",true,false): node.set_physics_process(false)

func _main(path: String="") -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await frames(5)
	game.audio.persistence_enabled=false
	game.combat_events.persistence_enabled=false
	game.campaign.persistence_enabled=false
	game.solo_story.records.persistence_enabled=false
	game.network.set_process(false)
	game.social_bridge.set_process(false)
	if not path.is_empty():
		game.campaign.save_path=path
		game.campaign.persistence_enabled=true
		game.hud._rebuild_buttons()
		await frames()

func _dispose() -> void:
	game.network.active=false
	paused=false
	check(await Cleanup.free_scene(game,self),"Actual main scene and all audio handles release")
	game=null

func _source(count: int) -> Dictionary:
	await _main()
	game.start_scenario(count,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	_freeze()
	game.rounds.wave=Balance.TOTAL_WAVES
	for index in count:
		var worker: Worker=game.players[index]
		worker.progression.level=index+3
		worker.progression.skill_points=index+2
		worker.progression.xp=11.0+index
		worker.progression.armor_tier=1
		worker.inventory={"steel":index+1,"ammo":1,"jaw_trap":1}
		var weapon: WorkerWeapon=worker.get_node("WorkerWeapon")
		var rounds:=WorkerWeapon.initial_ammunition()
		rounds.loaded.rifle=19+index
		rounds.reserve=30+index
		rounds.open_pack=index+1
		check(weapon.restore_ammunition(rounds),"Prepared crew carries distinct real finite magazines")
	check(game.expedition.on_victory(),"Actual wave20 completion banks all crew cargo exactly once")
	var source: Dictionary=game.campaign.checkpoint()
	check(CampaignState.valid_checkpoint(source),"Actual cooperative victory yields a valid durable source")
	await _dispose()
	return source

func _variants(source: Dictionary) -> Dictionary:
	var saved:=CampaignState.new("",false)
	saved._restore(source)
	var variants: Dictionary={"preparation":saved.checkpoint()}
	check(saved.select_destination("harbor") and saved.select_stop("harbor:salvage"),"Prepare a real selected route and bounded salvage detour")
	variants.map=saved.checkpoint()
	# These carried materials belong to the prepared departure, outside the
	# already banked warehouse. The test checks conservation against this source.
	for slot: String in saved.snapshots:
		saved.snapshots[slot].inventory={"scrap":int(slot),"jaw_trap":1}
	check(not saved.begin_journey().is_empty(),"Finite saved convoy departs through its production state API")
	variants.travel=saved.checkpoint()
	check(saved.reach_stop(),"Prepared stop retains the original real departure boundary")
	variants.stop=saved.checkpoint()
	check(not saved.secure_stop().is_empty(),"Real finite stop reward is claimed once before resume")
	variants.after_stop=saved.checkpoint()
	check(saved.arrive_at_destination(),"Prepared occupation retains secured detour ownership")
	variants.occupation=saved.checkpoint()
	var failed:=saved.checkpoint()
	failed.expedition.stage="failed"
	variants.failed=failed
	check(saved.secure_destination(),"Real destination delivery produces a valid defense snapshot")
	variants.defense=saved.checkpoint()
	for name: String in variants: check(CampaignState.valid_checkpoint(variants[name]),"Every stored "+name+" fixture passes the actual schema")
	return variants

func _store(path: String,data: Dictionary) -> void:
	var saved:=CampaignState.new(path,false)
	saved.persistence_enabled=true
	saved._restore(data)
	check(saved.save_checkpoint(),"Write only the isolated saved campaign fixture")

func _disk(path: String) -> Dictionary:
	var saved:=CampaignState.new(path,false)
	saved.persistence_enabled=true
	return saved.checkpoint() if saved.load_checkpoint() else {}

func _case(count: int,name: String,source: Dictionary) -> void:
	var path:=fixture_root.path_join("%d-%s.json" % [count,name])
	_store(path,source)
	await _main(path)
	var original_hash:=FileAccess.get_sha256(path)
	var default_payload: Dictionary=game.expedition.saved_resume_payload()
	check(not default_payload.is_empty() and int(default_payload.checkpoint.player_count)==count,"Default/shared payload keeps original cooperative player count")
	check(FileAccess.get_sha256(path)==original_hash and not FileAccess.file_exists(Archive.path_for(path,str(source.campaign_id))),"Payload preview changes neither original file nor local crew archive")
	var online: Dictionary=game.expedition.saved_resume_payload(source.character_ids.slice(1,count))
	check(not online.is_empty() and int(online.checkpoint.player_count)==count,"Online continuation remains a full original-party transition")
	var panel: Control=game.hud.main_menu_panel
	check(is_instance_valid(panel.continue_button) and not panel.continue_button.disabled,"Genuine main-menu Continue is visible for the isolated save")
	panel.continue_button.pressed.emit()
	check(game.started and game.player_count==1 and game.players.size()==1 and game.campaign.player_count==1,"Main-menu offline Continue starts exactly one physical and campaign player")
	_freeze()
	paused=true
	check(not game.network.active and not game.microphone.capturing and not game.solo_story.enabled,"Ordinary coop save becomes offline solo without forcing solo-story or opening a network")
	check(CampaignState.valid_checkpoint(game.campaign.checkpoint()) and not game.campaign.checkpoint().has("offline_crew_archive"),"Active solo checkpoint retains unchanged strict shared schema")
	check(game.players[0].progression.level==int(source.snapshots["1"].level) and is_equal_approx(game.players[0].progression.xp,float(source.snapshots["1"].xp)),"Solo player retains original first-slot progression")
	check(same(game.players[0].get_node("WorkerWeapon").capture_ammunition(),source.snapshots["1"].ammunition),"Solo player retains exact personal finite magazines and reserves")
	var archive: Dictionary=game.campaign.offline_crew_archive
	check(Archive.matches(archive,str(source.campaign_id)),"Parked crew is attached only to the original campaign identity")
	var expected: Dictionary=default_payload.checkpoint
	var warehouse: bool=name in ["preparation","map"]
	for slot in range(2,count+1):
		var character:=str(source.character_ids[slot-1])
		var row: Dictionary=archive.slots[str(slot)][character]
		check(same(row.snapshot,expected.snapshots[str(slot)]),"Absent slot retains its complete original character/progress/ammo/inventory snapshot")
		var restored:=Archive.snapshot(archive,slot,character)
		var expected_inventory: Dictionary=expected.snapshots[str(slot)].get("inventory",{}).duplicate(true)
		if warehouse:
			for kind: String in CampaignCatalog.CARGO_KINDS: expected_inventory.erase(kind)
		check(same(restored.inventory,expected_inventory),"Only cargo already owned by the warehouse is excluded from restored hands")
		check(not game.campaign.snapshots.has(str(slot)) and (game.campaign.expedition.departure.is_empty() or not game.campaign.expedition.departure.snapshots.has(str(slot))),"Absent slot does not remain in active or departure snapshots")
	check(same(game.campaign.expedition.garage_stock,expected.expedition.garage_stock) and same(game.campaign.expedition.vehicle.cargo,expected.expedition.vehicle.cargo),"Solo adaptation grants no extra warehouse/cargo units and deletes none")
	var disk:=_disk(path)
	check(not disk.is_empty() and int(disk.player_count)==1,"Reduced active party and its reserve survive a new real JSON read")
	var source_state:=CampaignState.new(path,false)
	source_state.persistence_enabled=true
	check(source_state.load_checkpoint() and same(source_state.offline_crew_archive,archive),"Fresh CampaignState loads its separate original crew reserve")
	var preferences: Dictionary=game.session_preferences()
	check(same(preferences.offline_crew_archive,archive),"No-profile internal scene preferences carry a deep local reserve copy")
	if count==3 and name=="defense":
		game.campaign.persistence_enabled=false
		var old_id:=game.get_instance_id()
		check(game.restart(),"Actual F5 path accepts the active single-player defense")
		var deadline:=Time.get_ticks_msec()+10000
		while Time.get_ticks_msec()<deadline:
			await process_frame
			if is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_id and bool(current_scene.get("started")):
				game=current_scene
				break
		check(game.get_instance_id()!=old_id and game.player_count==1 and game.players.size()==1,"Actual F5 scene replacement preserves the single active player")
		check(same(game.campaign.offline_crew_archive,archive) and not game.campaign.persistence_enabled,"Actual no-profile reload retains the separate reserve entirely through local session metadata")
		game.campaign.save_path=path
		game.campaign.persistence_enabled=true
		_freeze()
		paused=true
	var before_stock: Dictionary=game.expedition._capture_stock()
	for slot in range(2,count+1):
		var character:=str(source.character_ids[slot-1])
		var reserved:=Archive.snapshot(archive,slot,character)
		game.join_coop()
		check(game.player_count==slot and game.players.size()==slot,"Explicit local rejoin activates exactly one requested original slot")
		var actor: Worker=game.players[-1]
		actor.set_physics_process(false)
		actor.get_node("WorkerWeapon").set_physics_process(false)
		check(actor.character_id==character and actor.progression.level==int(reserved.level) and is_equal_approx(actor.progression.xp,float(reserved.xp)),"Rejoining original character receives parked personal progression")
		check(same(actor.get_node("WorkerWeapon").capture_ammunition(),reserved.ammunition) and same(actor.inventory,reserved.inventory),"Rejoining original slot receives exact finite ammo and its owned hands")
		check(CampaignState.valid_checkpoint(game.campaign.checkpoint()),"Explicit rejoin produces a strict valid active checkpoint")
		check(int(_disk(path).player_count)==slot,"Join count/progress becomes durable before the partner can play")
	var after_stock: Dictionary=game.expedition._capture_stock()
	if warehouse: check(same(before_stock,after_stock),"Garage rejoins cannot manufacture cargo already banked at victory")
	else:
		var extra: Dictionary={}
		for slot in range(2,count+1):
			for kind: String in Archive.snapshot(archive,slot,str(source.character_ids[slot-1])).inventory:
				if kind in CampaignCatalog.CARGO_KINDS: extra[kind]=int(extra.get(kind,0))+int(Archive.snapshot(archive,slot,str(source.character_ids[slot-1])).inventory[kind])
		for kind: String in CampaignCatalog.CARGO_KINDS:
			check(int(after_stock.get(kind,0))-int(before_stock.get(kind,0))==int(extra.get(kind,0)),"Rejoin restores only previously parked material ownership: "+kind)
	cases.append({"players_before":count,"boundary":name,"players_offline":1,"players_after_explicit_rejoin":game.player_count,"archive_slots":archive.slots.keys(),"stock_before_rejoin":before_stock,"stock_after_rejoin":after_stock})
	await _dispose()

func _failures(source: Dictionary) -> void:
	var path:=fixture_root.path_join("failure.json")
	_store(path,source)
	var archive_path:=Archive.path_for(path,str(source.campaign_id))
	check(DirAccess.make_dir_absolute(archive_path)==OK,"Owned directory deliberately blocks the archive destination")
	await _main(path)
	var before:=FileAccess.get_sha256(path)
	check(not game.expedition.resume_saved() and not game.started and game.players.is_empty(),"Failed archive commit never starts a smaller party")
	check(FileAccess.get_sha256(path)==before,"Failed reserve write preserves the complete original coop file")
	check(DirAccess.remove_absolute(archive_path)==OK,"Remove only the owned obstructing archive directory")
	var blocked:=path+".bak"
	check(DirAccess.make_dir_absolute(blocked)==OK,"Owned directory deliberately blocks the primary backup destination")
	check(not game.expedition.resume_saved() and not game.started and game.players.is_empty(),"Failed primary commit cannot start a party even after a valid reserve commit")
	check(FileAccess.get_sha256(path)==before and bool(Archive.load_records(path,str(source.campaign_id)).ok),"Failed primary commit preserves original coop file and the already secured local reserve")
	check(DirAccess.remove_absolute(blocked)==OK,"Remove the temporary mainfile obstruction")
	check(game.expedition.resume_saved(),"Valid archive retry then starts a safe one-player continuation")
	_freeze()
	paused=true
	var original_path: String=game.campaign.save_path
	game.campaign.save_path=fixture_root.path_join("missing-parent/join.json")
	var count_before: int=game.player_count
	var state_before: Dictionary=game.campaign.checkpoint()
	game.join_coop()
	check(game.player_count==count_before and game.players.size()==count_before and same(game.campaign.checkpoint(),state_before),"Failed durable reserved-join commit creates no partner and preserves active progress")
	game.campaign.save_path=original_path
	game.join_coop()
	check(game.players.size()==2 and game.players[1].progression.level==int(source.snapshots["2"].level),"Retry rejoin recovers the same original progress without resetting it")
	await _dispose()
	var good:=Archive.park(source)
	check(Archive.save_records(path,good),"Create real local crew reserve for malformed-file recovery")
	var modified:=good.duplicate(true)
	modified.slots["2"][str(source.character_ids[1])].snapshot.xp+=1.0
	check(Archive.save_records(path,modified),"Rotate a valid local crew reserve backup atomically")
	FileAccess.open(archive_path,FileAccess.WRITE).store_string("{broken")
	var recovered:=Archive.load_records(path,str(source.campaign_id))
	check(bool(recovered.ok) and same(recovered.data,good),"Syntactically damaged reserve loads its valid previous backup without script errors")
	FileAccess.open(archive_path+".bak",FileAccess.WRITE).store_string("{also broken")
	check(not bool(Archive.load_records(path,str(source.campaign_id)).ok),"Two damaged reserve copies are refused rather than silently losing parked crew")
	for invalid in [null,true,"wrong",[],{},INF,NAN]:
		var data:=good.duplicate(true)
		data.version=invalid
		check(not Archive.valid(data),"Malformed archive versions never trigger unsafe numeric comparison")
	var another:=Archive.empty("another-campaign")
	check(Archive.valid(another) and Archive.snapshot(another,2,str(source.character_ids[1])).is_empty(),"Unrelated campaign cannot grant another crew's progress or supplies")
	var foreign_path:=fixture_root.path_join("foreign-reserve.json")
	_store(foreign_path,source)
	FileAccess.open(Archive.path_for(foreign_path,"unrelated-old-campaign"),FileAccess.WRITE).store_string("{broken")
	var independent:=CampaignState.new(foreign_path,false)
	independent.persistence_enabled=true
	check(independent.load_checkpoint() and independent.player_count==int(source.player_count),"Damaged reserve of a different campaign cannot block the complete current coop checkpoint")
	var changed_character:=source.duplicate(true)
	changed_character.character_ids[1]="ivo"
	changed_character.snapshots["2"].character="ivo"
	var combined:=Archive.park(changed_character,good)
	check(Archive.valid(combined) and combined.slots["2"].has(str(source.character_ids[1])) and combined.slots["2"].has("ivo"),"Switching the character in a slot does not erase the parked original identity's progression")
	check(Archive.snapshot(good,1,str(source.character_ids[0])).is_empty(),"Archive cannot duplicate the always-active first player")
	var input_copy:=Archive.snapshot(good,2,str(source.character_ids[1]))
	input_copy.inventory.clear()
	check(not Archive.snapshot(good,2,str(source.character_ids[1])).inventory.is_empty(),"Archive read returns deep copies and cannot delete parked supplies")
	var first:=CampaignState.new("",false)
	check(first.begin_new({"environment":"ash_foundry","build_type":"bastion","position":"left"},["mara","branko"],2),"Prepare a genuine pre-victory campaign with no committed personal snapshots")
	var first_path:=fixture_root.path_join("first-defense.json")
	_store(first_path,first.checkpoint())
	await _main(first_path)
	check(game.expedition.resume_saved() and game.players.size()==1 and game.campaign.snapshots.is_empty(),"Pre-victory offline Continue starts one player without manufacturing saved XP")
	_freeze()
	paused=true
	game.join_coop()
	check(game.players.size()==2 and game.players[1].progression.level==1 and game.campaign.snapshots.is_empty(),"Explicit pre-victory rejoin restores only the legitimate original baseline and unchanged empty snapshot schema")
	await _dispose()
	var complete:=source.duplicate(true)
	complete.completed.clear()
	complete.claimed_missions.clear()
	complete.unlocked_routes.clear()
	complete.blueprints.clear()
	complete.banked_salvage=0
	complete.total_salvage_earned=0
	for site: Dictionary in CampaignCatalog.NODES:
		complete.completed.append(str(site.id))
		complete.claimed_missions.append(str(complete.campaign_id)+":"+str(site.id))
		if int(site.cost)>0:
			complete.unlocked_routes.append(str(site.id))
			complete.total_salvage_earned+=int(site.cost)
		if not str(site.blueprint).is_empty(): complete.blueprints.append(str(site.blueprint))
	complete.current_node="mountain_pass"
	complete.pending_node="mountain_pass"
	var complete_path:=fixture_root.path_join("terminal.json")
	_store(complete_path,complete)
	await _main(complete_path)
	check(game.expedition.resume_saved() and game.players.size()==1 and game.hud.overlay=="campaign_victory","Completed coop campaign resumes offline with one player and its existing terminal result")
	check(game.campaign.claimed_missions.size()==12 and game.campaign.completed.size()==12 and not game.campaign.mission_running,"Terminal continuation creates no extra mission, loot or blueprint reward")
	await _dispose()

func _cleanup(path: String) -> void:
	if fixture_root.is_empty() or not path.begins_with(fixture_root): return
	var directory:=DirAccess.open(path)
	if directory==null: return
	for name: String in directory.get_files(): DirAccess.remove_absolute(path.path_join(name))
	for name: String in directory.get_directories(): _cleanup(path.path_join(name))
	DirAccess.remove_absolute(path)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2);return
	root.size=Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	fixture_root=ProjectSettings.globalize_path("res://artifacts/solo-story/offline-resume/fixtures-%d" % OS.get_process_id())
	check(DirAccess.make_dir_recursive_absolute(fixture_root)==OK,"Persistence lives exclusively in a disposable artifact directory")
	var sample: Dictionary={}
	for count in [2,3,4]:
		var source: Dictionary=await _source(count)
		if count==2: sample=source.duplicate(true)
		var variants:=_variants(source)
		for name: String in variants: await _case(count,name,variants[name])
	await _failures(sample)
	var report:={"checks":checks,"failures":failures,"cases":cases,"prepared_states":["Three genuine main scenes produce actual finite 2/3/4-player wave20 completion checkpoints from prepared levels, XP, hands and magazines.","Eight stage variants per party use genuine CampaignState route/departure/cache/occupation/delivery APIs; travel-hand quantities are explicitly prepared and conservation is measured against them.","Fresh actual main-menu Continue button starts each file offline; each absent slot subsequently returns only through explicit game.join_coop.","Master muted, world simulation frozen for deterministic ownership assertions, no transports/microphones/UPnP, isolated XDG and disposable artifact-only persistence.","Archive and primary files contain unchanged strict multiplayer checkpoints; local crew reserve lives only in a separate sidecar and local session preferences."],"limits":["Prepared safe checkpoint boundaries test continuation/resource ownership and rejoin; this is not a full campaign combat playthrough or native rendering benchmark."]}
	FileAccess.open("res://artifacts/solo-story/offline-resume/test-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	_cleanup(fixture_root)
	print("Offline campaign resume: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
