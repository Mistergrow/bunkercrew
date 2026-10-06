extends SceneTree
## Real scene reloads preserve setup and local choices, while uncommitted
## mission progress rolls back to its verified campaign deployment.
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const OPTIONS := {"environment":"ash_foundry","build_type":"workshop","position":"right"}
var game
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> bool:
	checks += 1
	if not ok: failures += 1; push_error(label)
	else: print("RESTART PASS ",label)
	return ok

func frames(count: int=5) -> void:
	for frame in count: await process_frame

func freeze() -> void:
	paused=true
	game.rounds.set_process(false)
	game.expedition.set_physics_process(false)
	for worker in game.players:
		worker.set_physics_process(false)
		worker.get_node("WorkerWeapon").set_physics_process(false)
	if is_instance_valid(game.expedition.vehicle): game.expedition.vehicle.set_physics_process(false)

func reloaded(old_id: int,started: bool=true) -> bool:
	var deadline := Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_id and current_scene.started==started:
			game=current_scene
			await frames()
			return true
	return check(false,"Actual scene reload completed")

func preferences() -> void:
	game.set_camera_mode("overview")
	game.set_camera_zoom(1.73)
	game.audio.set_music_volume(.32)
	game.audio.set_sfx_volume(.43)
	game.audio.set_voice_volume(.54)
	game.audio.set_music_style("minimal_techno")
	game.audio.set_music_calibration(.07)
	game.audio.set_rhythm_motion_reduced(true)
	game.audio.set_dance_configuration(1.2,{"mara":{"style":"mara_lockstep","intensity":1.1}})
	game.weather.set_reduced_effects(true)
	game.combat_events.record_character_dance_level("mara",10)
	game.combat_events.unlock("armor")
	game.combat_events.record_mined(7)

func check_preferences() -> void:
	check(game.camera_settings().mode=="overview" and is_equal_approx(game.camera_settings().zoom,1.73),"Latest camera mode and zoom survive without profile writes")
	check(is_equal_approx(game.audio.music_volume,.32) and is_equal_approx(game.audio.sfx_volume,.43) and is_equal_approx(game.audio.voice_volume,.54),"Latest three channel volumes survive delayed saves")
	check(game.audio.music_style=="minimal_techno" and game.audio.rhythm_motion_reduced and is_equal_approx(game.audio.music_calibration_seconds,.07),"Music style, accessibility and beat calibration survive")
	check(is_equal_approx(game.audio.dance_intensity,1.2) and game.audio.dance_profiles.mara.style=="mara_lockstep","Selected dances and their intensity survive")
	check(game.weather.reduced_effects,"F3 preference survives replacing the weather node")
	check(game.combat_events.dance_level("mara")==10 and game.combat_events.unlocked.has("armor") and game.combat_events.counters.mined>=7,"Permanent cosmetic records survive a local scene reload")
	check(not game.combat_events.earned_this_shift.has("armor"),"Reloading an old achievement does not broadcast a newly earned crew reward")

func run() -> void:
	root.size=Vector2i(1440,900)
	change_scene_to_file("res://scenes/main.tscn")
	await frames()
	game=current_scene
	game.combat_events.restore_session_records({"achievements":["unknown_id","armor"],"dance_levels":{"ivo":6,"mara":31,"branko":"10","unknown":10},"counters":{"mined":-9,"crafted":999999999}})
	check(game.combat_events.unlocked.has("armor") and not game.combat_events.unlocked.has("unknown_id") and game.combat_events.earned_this_shift.is_empty(),"Restored profiles reject unknown achievements and cannot fake new crew rewards")
	check(game.combat_events.dance_level("ivo")==6 and game.combat_events.dance_level("mara")==1 and game.combat_events.dance_level("branko")==1,"Restored profiles reject unknown, oversized and incorrectly typed dance levels")
	check(game.combat_events.counters.mined==0 and game.combat_events.counters.crafted==1000000,"Restored activity counters remain within their safe persistent range")
	game.combat_events.restore_session_records({"dance_levels":{"ivo":2},"counters":{"crafted":1}})
	check(game.combat_events.dance_level("ivo")==6 and game.combat_events.counters.crafted==1000000,"Older profile copies cannot roll back permanent levels or activity")
	game.selected_characters.assign(["ivo","branko","mara","ivo"])
	game.start(4)
	freeze()
	preferences()
	var old_id: int=game.get_instance_id()
	var old_worker: WeakRef=weakref(game.players[0])
	game.players[0].inventory["ore"]=6
	game.players[0].take_damage(10)
	check(game.restart() and not game.restart(),"Rapid duplicate restarts schedule exactly one replacement")
	if not await reloaded(old_id): quit(1); return
	check(game.started and game.player_count==4 and game.players.size()==4 and game.scenario_bunker==null,"Classic bunker restarts immediately with its original four-worker party")
	check(game.selected_characters==["ivo","branko","mara","ivo"] and game.players[0].character_id=="ivo","Restart preserves the chosen crew and their order")
	check(old_worker.get_ref()==null and get_nodes_in_group("players").size()==4,"Old workers release without duplicate player nodes")
	check(game.players[0].hp==game.players[0].max_hp and game.players[0].inventory.is_empty() and game.rounds.wave==1,"Classic restart resets damage, cargo and the current wave")
	check(not paused and game.hud.overlay=="","Restart from pause returns to playable gameplay")
	check_preferences()
	freeze()
	old_id=game.get_instance_id()
	check(game.return_to_menu() and not game.restart(),"Return to menu and restart cannot race to reload twice")
	if not await reloaded(old_id,false): quit(1); return
	check(game.hud.overlay=="menu" and paused and game.players.is_empty() and not game.campaign.active,"Return to menu constructs no hidden gameplay party or running campaign")
	check_preferences()
	game.selected_characters.assign(["mara","ivo","branko","mara"])
	game.start_scenario(2,OPTIONS)
	freeze()
	var campaign_id: String=game.campaign.campaign_id
	game.players[0].progression.level=4
	game.players[0].progression.skill_points=3
	game.players[0].progression.xp=19
	game.players[0].inventory={"ore":6}
	game.upgrades.owned["boots"]=true
	game.upgrades.points=12
	var checkpoint: Dictionary=game.campaign.checkpoint()
	var payload: Dictionary=game.expedition.restart_payload()
	check(not payload.is_empty() and game.campaign.checkpoint()==checkpoint and game.campaign.mission_running,"Preparing a restart never commits or mutates the current campaign")
	old_id=game.get_instance_id()
	check(game.restart(),"An unfinished defense accepts restart")
	if not await reloaded(old_id): quit(1); return
	freeze()
	check(game.scenario_options==OPTIONS and game.player_count==2 and game.players[1].character_id=="ivo","Scenario restart preserves environment, build type, attack side and crew")
	check(game.campaign.campaign_id==campaign_id and game.campaign.mission_running and game.campaign.pending_node==CampaignCatalog.ENTRY,"Current defense restarts inside the same campaign")
	check(game.players[0].progression.level==1 and game.players[0].progression.xp==0 and game.players[0].inventory.is_empty(),"Uncommitted personal XP and mission cargo do not survive retry")
	check(not game.upgrades.has_upgrade("boots") and game.upgrades.points==0 and game.rounds.wave==1,"Uncommitted research and waves restart from deployment")
	# Prepare a real wave20 reward, then use the production campaign ledger to
	# establish journey/occupation/defense boundaries with finite earned stock.
	game.players[0].progression.level=3
	game.players[0].progression.skill_points=2
	game.players[0].progression.xp=11
	game.players[1].progression.level=2
	game.players[1].progression.skill_points=1
	game.upgrades.points=7
	game.upgrades.owned["boots"]=true
	game.rounds.wave=20
	check(game.expedition.on_victory(),"Prepared actual victory banks valid crew and research snapshots")
	check(game.campaign.select_destination("harbor") and game.campaign.select_stop("harbor:weapon"),"Next journey selects its finite weapon cache")
	check(game.campaign.prepare_expedition(game.players,game.upgrades) and not game.campaign.begin_journey().is_empty(),"Campaign records a valid departure boundary")
	check(game.campaign.reach_stop() and not game.campaign.secure_stop().is_empty(),"Secured stop updates the retry boundary exactly once")
	game.campaign.expedition.vehicle.hp=123
	game.campaign.expedition.vehicle.fuel=1
	checkpoint=game.campaign.checkpoint()
	payload=game.expedition.restart_payload()
	check(not payload.is_empty() and payload.mode=="travel" and game.campaign.checkpoint()==checkpoint,"Journey retry is built without changing live fuel, cargo or claims")
	old_id=game.get_instance_id()
	check(game.restart(),"Journey restart accepts the last secured travel point")
	if not await reloaded(old_id): quit(1); return
	freeze()
	check(game.expedition.stage=="travel" and game.scenario_options==OPTIONS and game.campaign.pending_node=="harbor","Journey retry returns to the departure environment with its chosen destination")
	check(game.players[0].progression.level==3 and game.players[1].progression.level==2 and game.upgrades.has_upgrade("boots") and game.upgrades.points==7,"Only banked crew levels and portable research survive retry")
	check(game.campaign.expedition.claimed_stops.has("harbor:weapon") and game.campaign.expedition.epic_weapons.size()==1 and game.expedition.stop_done,"Claimed roadside weapon is retained without duplicate reward")
	check(game.expedition.vehicle.position.x>1900 and game.expedition.vehicle.hp>123 and game.expedition.vehicle.fuel>1,"Retry starts at the secured halfway point with its banked vehicle state")
	check(game.campaign.arrive_at_destination(),"Prepared journey reaches occupation with its existing claim")
	old_id=game.get_instance_id()
	check(game.restart(),"Occupation restart accepts the journey checkpoint")
	if not await reloaded(old_id): quit(1); return
	freeze()
	check(game.expedition.stage=="travel" and game.scenario_options.environment=="ash_foundry" and game.campaign.current_node==CampaignCatalog.ENTRY,"Occupation retry returns to the correct origin instead of resetting the entire campaign")
	check(game.campaign.arrive_at_destination() and game.campaign.secure_destination(),"Destination creates a banked defense deployment")
	game.players[0].progression.level=5
	game.players[0].progression.skill_points=4
	old_id=game.get_instance_id()
	check(game.restart(),"A destination defense restarts from its banked deployment")
	if not await reloaded(old_id): quit(1); return
	freeze()
	check(game.expedition.stage=="defense" and game.scenario_options.environment==CampaignCatalog.node("harbor").environment and game.campaign.completed==[CampaignCatalog.ENTRY],"Defense retry keeps completed sites and uses the destination environment")
	check(game.players[0].progression.level==3 and game.players[1].progression.level==2 and game.campaign.mission_running,"Destination defense discards new XP while retaining its banked crew")
	game.rounds.wave=20
	game.rounds.running=true
	game.rounds.victory()
	check(game.hud.overlay=="victory" and game.expedition.restart_payload().is_empty(),"A completed mission chooses a fresh shift with the current setup")
	var won_id: String=game.campaign.campaign_id
	var won_options: Dictionary=game.scenario_options.duplicate()
	old_id=game.get_instance_id()
	check(game.restart(),"Victory permits a fresh shift")
	if not await reloaded(old_id): quit(1); return
	freeze()
	check(game.scenario_options==won_options and game.player_count==2 and game.campaign.campaign_id!=won_id and game.campaign.completed.is_empty(),"Fresh shift retains setup and party while creating a clean campaign")
	check(game.players[0].progression.level==1 and game.rounds.wave==1,"Fresh shift starts wave one with clean personal run progression")
	check_preferences()
	check(not game.combat_events.persistence_enabled and not game.campaign.persistence_enabled,"Lifecycle regressions never write the user's profile")
	check(await CLEANUP.free_scene(game,self),"Final game and native audio release cleanly")
	print("RESTART LIFECYCLE: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
