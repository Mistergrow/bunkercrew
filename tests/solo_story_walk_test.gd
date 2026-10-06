extends SceneTree
## Six real collision worlds. The worker always starts at its native spawn;
## movement and E are real input actions, never teleports or direct interactions.
const Catalog := preload("res://scripts/solo_story_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const MAX_WALK_FRAMES := 420
var game: Node
var checks := 0
var failures := 0
var routes: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int = 3) -> void:
	for unused in count: await process_frame

func physics_frames(count: int = 3) -> void:
	for unused in count: await physics_frame

func _release_inputs() -> void:
	for action: StringName in InputMap.get_actions():
		if str(action).begins_with("p1_"): Input.action_release(action)

func _prepare(site: String, position_mode: String) -> void:
	_release_inputs()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(5)
	game.audio.persistence_enabled = false
	game.combat_events.persistence_enabled = false
	game.campaign.persistence_enabled = false
	game.solo_story.records.persistence_enabled = false
	game.network.set_process(false)
	game.social_bridge.set_process(false)
	var options := {"environment":str(CampaignCatalog.node(site).environment),"build_type":"bastion","position":position_mode}
	check(game.campaign.begin_new(options,["mara"],1), "Initialize genuine unsaved campaign for "+site+"/"+position_mode)
	var parent := str(CampaignCatalog.node(site).parent)
	while not parent.is_empty():
		game.campaign.completed.push_front(parent)
		parent = str(CampaignCatalog.node(parent).parent)
	for id: String in game.campaign.completed: game.campaign.claimed_missions.append(game.campaign.campaign_id+":"+id)
	game.campaign.current_node = str(game.campaign.completed[-1])
	game.campaign.total_salvage_earned = 30
	game.campaign.banked_salvage = 30
	check(game.campaign.select_destination(site) and not game.campaign.mission_start().is_empty(), "Genuine route and mission APIs authorize the later chapter")
	game.story_mode = true
	game.start_scenario(1,options)
	var worker: Worker = game.players[0]
	# Freeze timed world systems and other actors. Collider geometry is retained.
	# The real player's CharacterBody2D physics remains enabled throughout.
	for node: Node in game.find_children("*","Node",true,false):
		if node != worker: node.set_physics_process(false)
	game.rounds.running = false
	game.rounds.set_process(false)
	game.solo_story.set_process(false)
	game.story.set_process(false)
	game.expedition.set_process(false)
	game.set_process(false)
	game.rounds.phase = "build"
	game.rounds.wave = 1
	game.campaign.snapshots = {"1":CampaignBonus.snapshot_player(worker)}
	worker.inventory.clear()
	await physics_frames(3)
	check(worker.is_physics_processing() and worker.is_on_floor(), "Normal worker physics settles at the native spawn")
	check(worker.global_position.distance_to(game.scenario_bunker.spawn_position(1)) <= 2.0, "Spawn is never teleported or repositioned by the fixture")
	check(CampaignState.valid_checkpoint(game.campaign.checkpoint()), "Prepared parent claims, currency and actual worker snapshot form a valid campaign ledger")
	check(game.solo_story.enabled and not game.story.enabled, "Later solo chapter enables encounters without the entry tutorial wall")
	check(not game.network.active and not game.microphone.capturing, "Walking fixture opens no socket or microphone")

func _walk_to(target: Node2D, label: String) -> Dictionary:
	var worker: Worker = game.players[0]
	var start: Vector2 = worker.global_position
	var maximum_ground_error := 0.0
	var elapsed_frames := 0
	while elapsed_frames < MAX_WALK_FRAMES and absf(worker.global_position.x-target.global_position.x) > 5.0:
		var move_right: bool = target.global_position.x > worker.global_position.x
		Input.action_release("p1_left" if move_right else "p1_right")
		Input.action_press("p1_right" if move_right else "p1_left")
		await physics_frame
		elapsed_frames += 1
		maximum_ground_error = maxf(maximum_ground_error,absf(worker.global_position.y-game.scenario_bunker.ground_y))
	Input.action_release("p1_left")
	Input.action_release("p1_right")
	await physics_frames(2)
	check(elapsed_frames > 0 and elapsed_frames < MAX_WALK_FRAMES and absf(worker.global_position.x-target.global_position.x) <= 5.0, label+": real left/right input reaches the object within 420 physics frames")
	check(worker.is_on_floor() and maximum_ground_error <= 2.0 and absf(worker.global_position.y-game.scenario_bunker.ground_y) <= 2.0, label+": complete walk stays on the actual 430px floor, including the shaft and bunker exits")
	check(worker.velocity.length() < 1.0 and not worker.climbing and not is_instance_valid(worker.mounted_turret), label+": releasing movement stops a normal grounded worker")
	check(game.valid_focus(worker,target) and worker._chosen_focus() == target, label+": native focus automatically selects the reached object without a preferred-target fixture")
	return {"label":label,"start":[start.x,start.y],"end":[worker.global_position.x,worker.global_position.y],"target":[target.global_position.x,target.global_position.y],"physics_frames":elapsed_frames,"maximum_ground_error":maximum_ground_error}

func _press_e(expected_overlay: String, label: String) -> void:
	Input.action_press("p1_interact")
	await physics_frames(2)
	check(game.hud.overlay == expected_overlay and paused, label+": real E action and enabled worker physics open the native reader")
	Input.action_release("p1_interact")
	# HUD uses PROCESS_MODE_ALWAYS while the encounter pauses game physics.
	await frames(3)
	game.hud._close_solo_story()
	await physics_frames(3)
	check(game.hud.overlay.is_empty() and not paused and game.players[0].is_physics_processing(), label+": closing the reader returns to live worker physics")

func _route(site: String, position_mode: String) -> void:
	await _prepare(site,position_mode)
	var director: Node = game.solo_story
	var worker: Worker = game.players[0]
	var campaign_before: Dictionary = game.campaign.checkpoint()
	var health_before: float = worker.hp
	var inventory_before: Dictionary = worker.inventory.duplicate(true)
	var walks: Array[Dictionary] = []
	for id: String in Catalog.chapter(site).find_ids:
		var target: Node2D = director.finds[id]
		walks.append(await _walk_to(target,site+"/"+position_mode+"/"+id))
		await _press_e("story_journal",id)
		check(id in director.records.events, "Walked-to find records its actual authored entry")
	var profile: Dictionary = Catalog.profiles().filter(func(person: Dictionary) -> bool: return str(person.site) == site)[0]
	var npc: Node2D = director.npcs[str(profile.id)]
	walks.append(await _walk_to(npc,site+"/"+position_mode+"/"+str(profile.id)))
	await _press_e("story_encounter",str(profile.id))
	check(str(profile.id) in director.records.met and str(profile.id) not in director.records.recruited and not CharacterCatalog.is_unlocked(str(profile.id)), "Approaching and talking records contact without bypassing the three-wave rescue job")
	check(game.campaign.checkpoint() == campaign_before and worker.inventory == inventory_before and is_equal_approx(worker.hp,health_before), "Walking and reading do not pay rescue costs, alter campaign rewards or damage the worker")
	routes.append({"site":site,"position":position_mode,"walks":walks,"events":director.records.events.duplicate(),"met":director.records.met.duplicate()})
	_release_inputs()
	paused = false
	check(await Cleanup.free_scene(game,self), "Actual collision world and audio handles release after the walk")
	game = null

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		quit(2)
		return
	root.size = Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	InputSetup.install()
	CrewRoster.persistence_enabled = false
	CrewRoster._loaded = true
	CrewRoster.unlocked.clear()
	LocaleText.set_locale("de",false)
	for site: String in ["quarry","power_station"]:
		for position_mode: String in ["left","center","right"]:
			await _route(site,position_mode)
	CrewRoster.unlocked.clear()
	var report := {"checks":checks,"failures":failures,"routes":routes,"prepared_states":["Six actual main scenes: quarry/Oskar and power_station/Rika, each with left/center/right bastion geometry.","Valid completed-parent claims/currency and a real worker snapshot authorize later missions; this does not claim their prior combat was played.","Enemies/wave spawning and other world physics are frozen; all static collisions and normal Player._physics_process remain active.","Each worker starts at ScenarioBunker.spawn_position and walks to both finds and its NPC using actual p1_left/p1_right actions; no position/velocity assignments or preferred-focus overrides.","Actual p1_interact action opens native journals/encounters through enabled worker physics; no direct find/NPC/controller interaction call.","The three-wave NPC job is not completed: only contact is recorded, no materials are paid and no character is recruited.","Headless deterministic --fixed-fps60, master muted, isolated unsaved XDG, no UPnP/socket/microphone, protected editor untouched."],"limits":["Validates traversability and physical interaction in six prepared maps, not combat balance, a rendered gallery, a full campaign or wall-clock performance."]}
	var output_path := "res://artifacts/solo-story/runtime/walk-test.json"
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))==OK,"Clean checkout can create its walk report directory")
	var output := FileAccess.open(output_path,FileAccess.WRITE)
	check(output!=null,"Walk report file opens in a clean checkout")
	if output!=null: output.store_string(JSON.stringify(report,"\t"))
	print("Solo story walk: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
