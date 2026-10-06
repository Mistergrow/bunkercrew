extends SceneTree
## Real local inputs, actual main-scene transitions and isolated legacy save data.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const NetInput := preload("res://scripts/network_input.gd")
const OPTIONS := {"environment":"ash_foundry","build_type":"workshop","position":"left"}
var game
var checks:=0
var failures:=0
var legacy: Dictionary={}
var capture_enabled:=false
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> bool:
	checks+=1
	print("PARTY RUNTIME %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok: failures+=1
	return ok
func frames(count: int=3) -> void:
	for unused in count: await process_frame
func capture(label: String) -> void:
	if not capture_enabled: return
	await frames(3)
	await RenderingServer.frame_post_draw
	var rendered:=root.get_texture().get_image()
	check(rendered.get_size()==Vector2i(2560,1440),"native QHD capture: "+label)
	rendered.save_png("res://artifacts/expedition/party-runtime-"+label+".png")
func fresh() -> void:
	paused=false
	if is_instance_valid(game): await Cleanup.free_scene(game,self)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await frames(4)
	game.campaign.persistence_enabled=false
	game.combat_events.persistence_enabled=false
func freeze_game() -> void:
	game.rounds.running=false
	game.rounds.set_process(false)
	game.expedition.set_physics_process(false)
	for player in game.players:
		player.set_physics_process(false)
		player.get_node("WorkerWeapon").set_physics_process(false)
	if is_instance_valid(game.expedition.vehicle): game.expedition.vehicle.set_physics_process(false)
func joy_axis(device: int,axis: JoyAxis,value: float) -> void:
	var event:=InputEventJoypadMotion.new()
	event.device=device
	event.axis=axis
	event.axis_value=value
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func key(code: Key,pressed: bool) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func joined_with_f2() -> void:
	key(KEY_F2,true)
	await frames(2)
	key(KEY_F2,false)
	await frames(2)
func wait_reload(old_id: int,stage: String) -> bool:
	var end:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<end:
		await frames()
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_id:
			game=current_scene
			if game.started and game.expedition.stage==stage:
				freeze_game()
				return true
	return check(false,"actual main-scene reload reaches "+stage)
func validate_layout() -> void:
	var rects: Array[Rect2]=[]
	for index in game.players.size():
		var bounds: Rect2=game.hud.player_bounds(index)
		check(game.hud.screen_rect().encloses(bounds),"P%d HUD card stays within the actual fitted viewport"%(index+1))
		for prior in rects: check(not prior.intersects(bounds),"HUD cards do not overlap")
		rects.append(bounds)
	game.hud._toggle_personnel()
	await frames()
	var panel: PersonalPanel=game.hud.personal_panel
	check(panel.player_buttons.size()==4,"personal menu exposes all four crew tabs")
	for index in panel.player_buttons.size():
		var button: Button=panel.player_buttons[index]
		check(Rect2(Vector2.ZERO,panel.size).encloses(button.get_rect()),"P%d personnel tab stays within the current full-screen panel"%(index+1))
		if index>0: check(not button.get_rect().intersects(panel.player_buttons[index-1].get_rect()),"adjacent personnel tabs do not overlap")
	panel.select_player(3)
	check(panel.selected_player==3,"fourth player progression can be inspected independently")
	await capture("personnel-four")
	game.hud._close_personnel()
	await frames()
func input_checks() -> void:
	for slot in [3,4]:
		for action in ["left","right","jump","fire","interact","reload","cycle_weapon","cycle_target"]:
			var events:=InputMap.action_get_events("p%d_%s"%[slot,action])
			check(not events.is_empty() and events.all(func(event):return event.device==slot-2),"P%d %s binds only its own physical pad"%[slot,action])
	for index in game.players.size(): game.players[index].position=Vector2(1100+index*55,430)
	for unused in 3: await physics_frame
	var p3_before: Vector2=game.players[2].position
	var p4_before: Vector2=game.players[3].position
	joy_axis(1,JOY_AXIS_LEFT_X,1)
	for unused in 6: await physics_frame
	check(NetInput.strength(game.players[2],"right")>.9 and NetInput.strength(game.players[3],"right")==0 and NetInput.strength(game.players[1],"right")==0,"device1 motion reaches only player3")
	check(game.players[2].position.x>p3_before.x+4 and absf(game.players[3].position.x-p4_before.x)<1,"device1 physically moves only player3")
	joy_axis(1,JOY_AXIS_LEFT_X,0)
	joy_axis(2,JOY_AXIS_TRIGGER_RIGHT,1)
	await physics_frame
	check(NetInput.strength(game.players[3],"fire")>.9 and NetInput.strength(game.players[2],"fire")==0,"device2 trigger reaches only player4")
	joy_axis(2,JOY_AXIS_TRIGGER_RIGHT,0)
	key(KEY_RIGHT,true)
	await physics_frame
	check(NetInput.strength(game.players[1],"right")>.9 and NetInput.strength(game.players[2],"right")==0,"arrow keyboard remains exclusive to player2")
	key(KEY_RIGHT,false)
func legacy_checks() -> void:
	check(CampaignState.valid_checkpoint(legacy),"legacy two-person version1 checkpoint remains valid")
	var path: String="user://party-runtime-legacy-%d.json"%OS.get_process_id()
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var original_contents:=FileAccess.get_file_as_string(path)
	var blocked:=CampaignState.new(path,false)
	blocked.persistence_enabled=true
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(path+".tmp"))
	check(not blocked.load_checkpoint() and not blocked.active and not blocked.last_error.is_empty() and FileAccess.get_file_as_string(path)==original_contents,"failed atomic migration preserves the original legacy file and inactive runtime")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".tmp"))
	var restored:=CampaignState.new(path,false)
	restored.persistence_enabled=true # Isolated test path; never touches the profile.
	check(restored.load_checkpoint(),"real legacy file loads through atomic one-time migration")
	var loaded:=restored.checkpoint()
	var migrated: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(migrated is Dictionary and migrated.version==2 and migrated.snapshots["1"].has("ammunition") and migrated.expedition.vehicle.has("open_pack"),"legacy ammunition fallback is durably written on the first load")
	var migrated_contents:=FileAccess.get_file_as_string(path)
	check(restored.load_checkpoint() and FileAccess.get_file_as_string(path)==migrated_contents,"second load uses stable migrated stores without another rewrite")
	remove_test_save(path)
	check(not loaded.is_empty() and loaded.version==2 and loaded.player_count==2,"JSON legacy file migrates while retaining two-person party")
	if loaded.is_empty(): return
	await fresh()
	var payload: Dictionary={"checkpoint":loaded,"mode":"preparation","options":loaded.options}
	check(game.expedition.restore(payload),"real controller restores migrated legacy save")
	await frames()
	freeze_game()
	check(game.players.size()==2 and game.campaign.player_count==2 and game.selected_characters.size()==4,"legacy restore spawns two actors and normalizes future local slots")
func remove_test_save(path: String) -> void:
	for suffix in ["",".bak",".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
func ammunition_disk_checks() -> void:
	var path: String="user://party-runtime-ammunition-%d.json"%OS.get_process_id()
	var before: Dictionary=game.campaign.checkpoint()
	# Four real departing actors, plus prepared finite vehicle ammunition.
	before.expedition.vehicle.ammo=7
	before.expedition.vehicle.reserve=11
	before.expedition.vehicle.open_pack=29
	before.expedition.departure.vehicle=before.expedition.vehicle.duplicate(true)
	var forged:=before.duplicate(true)
	forged.snapshots["1"].ammunition.loaded.rifle=31
	check(not CampaignState.valid_checkpoint(forged),"save rejects oversized magazine without magazine research")
	forged=before.duplicate(true)
	forged.snapshots["1"].ammunition.reserve=121
	check(not CampaignState.valid_checkpoint(forged),"save rejects expanded reserve without reserve-pouch research")
	forged=before.duplicate(true)
	forged.shared_personal_upgrades.erase("shotgun")
	check(not CampaignState.valid_checkpoint(forged),"save rejects stored rounds for an unresearched weapon")
	forged=before.duplicate(true)
	forged.expedition.departure.snapshots["1"].ammunition.loaded.rifle=31
	check(not CampaignState.valid_checkpoint(forged),"retry snapshot enforces its own research capacity")
	forged=before.duplicate(true)
	for id in ["weapon_magazines","weapon_pouches"]:
		forged.shared_personal_upgrades.append(id)
		forged.expedition.departure.shared_personal_upgrades.append(id)
	for stores in [forged.snapshots,forged.expedition.departure.snapshots]:
		stores["1"].ammunition.loaded.rifle=36
		stores["1"].ammunition.reserve=180
	check(CampaignState.valid_checkpoint(forged),"matching research permits exact expanded capacities in save and departure")
	var saved:=CampaignState.new(path,false)
	saved._restore(before)
	saved.persistence_enabled=true
	check(saved.save_checkpoint(),"four actual crew ammunition snapshots save to isolated disk")
	var restored:=CampaignState.new(path,false)
	restored.persistence_enabled=true
	check(restored.load_checkpoint() and JSON.parse_string(JSON.stringify(restored.checkpoint()))==JSON.parse_string(JSON.stringify(before)),"disk round trip preserves every inactive magazine, reserve, box remainder and vehicle departure")
	var historical:=before.duplicate(true)
	for snapshot in historical.snapshots.values(): snapshot.erase("ammunition")
	for snapshot in historical.expedition.departure.snapshots.values(): snapshot.erase("ammunition")
	historical.expedition.vehicle.erase("open_pack")
	historical.expedition.departure.vehicle.erase("open_pack")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(historical))
	file.close()
	check(restored.load_checkpoint() and restored.expedition.vehicle.ammo==7 and restored.expedition.vehicle.reserve==11 and restored.expedition.vehicle.open_pack==0 and restored.expedition.departure.vehicle.open_pack==0,"old version2 vehicle and departure keep finite ammunition through migration")
	check(restored.snapshots.values().all(func(snapshot):return snapshot.ammunition==WorkerWeapon.initial_ammunition()) and restored.expedition.departure.snapshots.values().all(func(snapshot):return snapshot.has("ammunition")),"old version2 crew and retry snapshots normalize all four slots")
	remove_test_save(path)
func story_reply_checks() -> void:
	game.story._reply_cursor=1
	var replies: Array=[]
	for unused in 8: replies.append(game.story.reply_player_id())
	check(replies==[2,3,4,1,2,3,4,1],"story replies rotate across the complete four-person crew")
	var saved_state: String=game.players[2].medical.state
	game.players[2].medical.state="downed"
	replies.clear()
	for unused in 6: replies.append(game.story.reply_player_id())
	check(not replies.has(3) and replies.has(1) and replies.has(2) and replies.has(4),"story replies skip unconscious crew members")
	game.players[2].medical.state=saved_state
func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args(): quit(2); return
	capture_enabled="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	if capture_enabled:
		root.mode=Window.MODE_FULLSCREEN
		root.size=Vector2i(2560,1440)
	for count in [1,2,3,4]:
		await fresh()
		if count==1:
			check(str(ProjectSettings.get_setting("application/config/name"))=="Bunkercrew" and root.title=="Bunkercrew","project and real window title use Bunkercrew")
			for language in ["de","en"]:
				LocaleText.set_locale(language,false)
				check(LocaleText.text("BUNKERCREW")=="BUNKERCREW","localized game title stays BUNKERCREW in "+language)
				await capture("menu-"+language)
		game.start_scenario(count,OPTIONS)
		await frames()
		game.rounds.running=false
		check(game.started and game.player_count==count and game.players.size()==count,"main game spawns exactly %d active actors"%count)
		check(game.campaign.player_count==count and CampaignState.valid_checkpoint(game.campaign.checkpoint()),"new %d-person campaign checkpoint validates"%count)
		check(game.players.all(func(player):return player.player_id>=1 and player.player_id<=count and player.character_id==game.selected_characters[player.player_id-1]),"all %d actors retain their selected identity and slot"%count)
		if count==4:
			await input_checks()
			freeze_game()
			story_reply_checks()
			game.players[2].get_node("WorkerWeapon").open_pack=13
			await validate_layout()
			for player in game.players: player.focus=null
			await capture("hud-four")
			LocaleText.set_locale("de",false)
			await capture("hud-four-de")
			LocaleText.set_locale("en",false)
			game.rounds.wave=20
			game.rounds.running=true
			game.rounds.victory()
			await frames()
			check(game.campaign.snapshots.size()==4 and game.campaign.player_count==4 and CampaignState.valid_checkpoint(game.campaign.checkpoint()),"actual four-person wave20 victory commits all four valid crew snapshots")
	await fresh()
	game.start_scenario(1,OPTIONS)
	await frames()
	freeze_game()
	game.players[0].progression.award_damage(700)
	game.rounds.wave=20
	game.rounds.running=true
	game.rounds.victory()
	await frames()
	check(game.expedition.stage=="preparation" and game.campaign.completed.size()==1,"real wave20 victory commits solo departure state")
	var saved_first: Dictionary=game.campaign.snapshots["1"].duplicate(true)
	game.players[0].progression.award_damage(70)
	var live_xp: float=game.players[0].progression.xp
	game.hud.overlay=""
	paused=false
	for expected in [2,3,4]:
		await joined_with_f2()
		check(game.players.size()==expected and game.player_count==expected,"physical F2 joins local player%d"%expected)
		check(game.campaign.snapshots["1"]==saved_first and is_equal_approx(game.players[0].progression.xp,live_xp),"joining neither banks nor resets existing P1 XP")
		check(CampaignState.valid_checkpoint(game.campaign.checkpoint()),"checkpoint remains valid after late join%d"%expected)
	await joined_with_f2()
	check(game.players.size()==4,"fifth F2 cannot exceed four-player limit")
	legacy=game.campaign.checkpoint().duplicate(true)
	legacy.player_count=2
	legacy.character_ids=legacy.character_ids.slice(0,2)
	legacy.snapshots.erase("3")
	legacy.snapshots.erase("4")
	for snapshot in legacy.snapshots.values(): snapshot.erase("ammunition")
	legacy.version=1
	legacy.erase("expedition")
	var ammunition: Dictionary={}
	game.upgrades.owned.shotgun=true
	game.upgrades.owned.arcgun=true
	for player in game.players:
		var weapon: WorkerWeapon=player.get_node("WorkerWeapon")
		weapon.loaded.rifle=3+player.player_id
		weapon.loaded.shotgun=player.player_id
		weapon.loaded.arcgun=player.player_id*2
		weapon.reserve=7+player.player_id
		weapon.open_pack=player.player_id
		ammunition[player.player_id]=weapon.capture_ammunition()
	check(game.expedition.handle_command("route",{"id":"harbor"},1),"four-person crew selects next bunker")
	var old_id: int=game.get_instance_id()
	check(game.expedition.handle_command("depart",{},1),"four-person departure prepares the actual boarding vehicle")
	check(is_instance_valid(game.expedition.vehicle),"boarding creates a real vehicle before the crew enters")
	if is_instance_valid(game.expedition.vehicle):
		for player: Worker in game.players:
			player.global_position = game.expedition.vehicle.global_position
			check(game.expedition.vehicle.board(player,game.expedition.vehicle.SEAT_ROLES[player.player_id-1]),"P%d enters the actual vehicle before departure"%player.player_id)
	game.expedition.set_physics_process(true)
	if await wait_reload(old_id,"travel"):
		var truck=game.expedition.vehicle
		check(game.players.size()==4 and truck.seats.all(func(seat):return is_instance_valid(seat.occupant)),"_start_road boards all four players without MG research")
		check(game.players.all(func(player):return player.mounted_turret==truck.seats[player.player_id-1]),"actual reload restores each distinct crew role")
		check(CampaignState.valid_checkpoint(game.campaign.checkpoint()) and game.campaign.expedition.departure.snapshots.size()==4,"four-person departure checkpoint and rollback snapshots validate")
		check(game.players.all(func(player):return player.get_node("WorkerWeapon").capture_ammunition()==ammunition[player.player_id]),"real four-person scene change preserves spent magazines, reserves and open boxes")
		ammunition_disk_checks()
		var fuel: float=truck.fuel
		truck.advance_motion(.1,1)
		truck.take_damage(truck.max_hp+1)
		check(game.expedition.stage=="failed","real four-person vehicle destruction exposes retry")
		old_id=game.get_instance_id()
		check(game.expedition.handle_command("retry",{},1),"retry accepts four-person departure checkpoint")
		if await wait_reload(old_id,"travel"):
			truck=game.expedition.vehicle
			check(game.players.size()==4 and truck.seats.all(func(seat):return is_instance_valid(seat.occupant)) and is_equal_approx(truck.fuel,fuel),"retry restores four occupied seats and finite departure fuel")
			check(CampaignState.valid_checkpoint(game.campaign.checkpoint()),"retried four-person checkpoint remains valid")
			check(game.players.all(func(player):return player.get_node("WorkerWeapon").capture_ammunition()==ammunition[player.player_id]),"retry restores exact departure ammunition without startup refill")
	await legacy_checks()
	paused=false
	await Cleanup.free_scene(game,self)
	print("PARTY RUNTIME: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
